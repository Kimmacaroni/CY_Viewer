import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cy_localization.dart';
import 'pdfcraft_service.dart';

class _PageEntry {
  const _PageEntry(this.id, this.index, [this.rotation = 0]);
  final int id;
  final int? index;
  final int rotation;
  _PageEntry turn(int angle) => _PageEntry(id, index, (rotation + angle) % 360);
  Map<String, Object?> toJson() => {'index': index, 'rotation': rotation};
}

class _BookmarkEntry {
  _BookmarkEntry(this.path, String name, int? destination)
    : title = TextEditingController(text: name),
      page = TextEditingController(text: destination?.toString() ?? ''),
      originalTitle = name,
      originalPage = destination;
  final List<int>? path;
  final String originalTitle;
  final int? originalPage;
  final TextEditingController title, page;
  bool removed = false;
  void dispose() {
    title.dispose();
    page.dispose();
  }
}

/// PdfCraft 기능을 페이지·파일·문서·보안 작업 흐름으로 나눈다.
class PdfcraftDialog extends StatefulWidget {
  const PdfcraftDialog({
    super.key,
    required this.source,
    required this.pageCount,
    this.hasTemporaryMarks = false,
    this.backend,
    this.saveResult,
  });
  final PdfcraftSource source;
  final int pageCount;
  final bool hasTemporaryMarks;
  final PdfcraftBackend? backend;
  final Future<String?> Function(PdfcraftResult)? saveResult;
  @override
  State<PdfcraftDialog> createState() => _PdfcraftDialogState();
}

class _PdfcraftDialogState extends State<PdfcraftDialog> {
  static const _channel = MethodChannel('com.kimmacaroni.cyviewer/file_access');
  late final PdfcraftBackend _backend =
      widget.backend ?? const PdfcraftService();
  late List<_PageEntry> _plan = List.generate(
    widget.pageCount,
    (i) => _PageEntry(i, i),
  );
  final _undo = <List<_PageEntry>>[], _redo = <List<_PageEntry>>[];
  final _selected = <int>{},
      _additions = <PdfcraftSource>[],
      _bookmarks = <_BookmarkEntry>[];
  final _range = TextEditingController(),
      _inputPassword = TextEditingController(),
      _newPassword = TextEditingController(),
      _confirm = TextEditingController(),
      _every = TextEditingController(text: '1');
  final _metadata = {
    for (final key in ['Title', 'Author', 'Subject', 'Keywords'])
      key: TextEditingController(),
  };
  bool _busy = true,
      _ready = false,
      _encrypted = false,
      _owner = true,
      _signed = false,
      _split = false;
  int _security = 0, _nextId = 0;
  String? _error, _savedPath, _savedExtension;
  String? _summary;
  bool get _editable => _ready && !_busy && !_signed && _owner;
  @override
  void initState() {
    super.initState();
    _nextId = widget.pageCount;
    _inspect();
  }

  @override
  void dispose() {
    for (final c in [
      _range,
      _inputPassword,
      _newPassword,
      _confirm,
      _every,
      ..._metadata.values,
    ]) {
      c.dispose();
    }
    for (final b in _bookmarks) {
      b.dispose();
    }
    super.dispose();
  }

  String t(String s) => tr(context, s);
  String message(Object e) => e is FormatException
      ? e.message
      : e is PlatformException
      ? e.message ?? e.code
      : e.toString();
  Future<void> _inspect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _backend.inspect(widget.source, _inputPassword.text);
      if (!mounted) return;
      for (final entry in _metadata.entries) {
        entry.value.text =
            (data['metadata'] as Map? ?? const {})[entry.key] as String? ?? '';
      }
      for (final b in _bookmarks) {
        b.dispose();
      }
      _bookmarks.clear();
      for (final b in (data['bookmarks'] as List? ?? const [])) {
        _bookmarks.add(
          _BookmarkEntry(
            (b['path'] as List).cast<int>(),
            b['title'] as String,
            b['page'] as int?,
          ),
        );
      }
      setState(() {
        _ready = true;
        _encrypted = data['encrypted'] == true;
        _owner = data['owner'] != false;
        _signed = data['signed'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _change(List<_PageEntry> next) {
    if (next.isEmpty) {
      setState(() => _error = t('문서는 최소 한 페이지를 유지해야 합니다.'));
      return;
    }
    setState(() {
      _undo.add(List.of(_plan));
      if (_undo.length > 30) _undo.removeAt(0);
      _redo.clear();
      _plan = next;
      _selected.removeWhere((id) => !next.any((p) => p.id == id));
      _savedPath = null;
      _error = null;
    });
  }

  void _history(bool undo) {
    setState(() {
      final from = undo ? _undo : _redo, to = undo ? _redo : _undo;
      to.add(_plan);
      _plan = from.removeLast();
      _selected.clear();
      _savedPath = null;
      _error = null;
    });
  }

  void _selectRange() {
    try {
      final ids = parsePdfcraftPages(
        _range.text,
        widget.pageCount,
      ).map((p) => p - 1).toSet();
      setState(() {
        _selected.clear();
        _selected.addAll(
          _plan.where((p) => ids.contains(p.index)).map((p) => p.id),
        );
        _error = null;
      });
    } catch (e) {
      setState(() => _error = message(e));
    }
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (_additions.length + files.length > 19) {
        throw const FormatException('PDF는 20개까지 합칠 수 있습니다.');
      }
      final staged = <PdfcraftSource>[];
      var total =
          widget.source.bytes.length +
          _additions.fold<int>(0, (n, s) => n + s.bytes.length);
      for (final file in files) {
        final size = await file.length();
        total += size;
        if (size > 256 * 1024 * 1024 || total > 512 * 1024 * 1024) {
          throw const FormatException('한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.');
        }
        staged.add(
          PdfcraftSource(
            file.name,
            await file.readAsBytes(),
            originalPath: file.path,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _additions.addAll(staged);
          _savedPath = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, Object?> _options() {
    final edits = <Map<String, Object?>>[];
    for (final b in _bookmarks) {
      if (b.path != null && b.removed) {
        edits.add({'action': 'delete', 'path': b.path});
        continue;
      }
      if (b.removed) continue;
      final destination = int.tryParse(b.page.text);
      if (b.path == null ||
          b.title.text != b.originalTitle ||
          destination != b.originalPage) {
        if (b.title.text.trim().isEmpty) {
          throw const FormatException('책갈피 이름을 입력하세요.');
        }
        if (destination == null ||
            destination < 1 ||
            destination > widget.pageCount) {
          throw const FormatException('책갈피 페이지가 문서 범위를 벗어났습니다.');
        }
        edits.add({
          'action': b.path == null ? 'add' : 'update',
          'path': b.path ?? [],
          'title': b.title.text,
          'page': destination,
        });
      }
    }
    final options = <String, Object?>{
      'metadata': {for (final e in _metadata.entries) e.key: e.value.text},
      'bookmarks': edits,
    };
    final unchanged =
        _plan.length == widget.pageCount &&
        _plan.indexed.every((e) => e.$2.index == e.$1 && e.$2.rotation == 0);
    if (!unchanged) {
      options['page_plan'] = _plan.map((p) => p.toJson()).toList();
    }
    if (_split) {
      final n = int.tryParse(_every.text);
      if (n == null || n < 1) {
        throw const FormatException('분할 간격은 1 이상으로 입력하세요.');
      }
      options['split_every'] = n;
    }
    if (_security == 1) {
      if (_newPassword.text.isEmpty || _newPassword.text != _confirm.text) {
        throw const FormatException('새 암호와 확인 암호를 같게 입력하세요.');
      }
      options['new_password'] = _newPassword.text;
    }
    if (_security == 2) options['remove_password'] = true;
    if (_encrypted && _security == 0) {
      throw const FormatException('암호 PDF는 새 암호 설정 또는 암호 해제를 선택하세요.');
    }
    return options;
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _savedPath = null;
      _busy = true;
    });
    try {
      final result = await _backend.edit(
        [widget.source, ..._additions],
        _options(),
        _inputPassword.text,
      );
      if (!mounted) return;
      final path = widget.saveResult != null
          ? await widget.saveResult!(result)
          : await _channel.invokeMethod<String>('savePageCopy', {
              'bytes': result.bytes,
              'extension': result.extension,
              'name':
                  '${widget.source.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}-${result.extension == 'zip' ? 'split' : 'edited'}.${result.extension}',
              'originals': [
                widget.source,
                ..._additions,
              ].map((s) => s.originalPath).whereType<String>().toList(),
            });
      if (mounted && path != null) {
        setState(() {
          _savedPath = path;
          _savedExtension = result.extension;
          _summary = tr(context, '{0}쪽 · 파일 {1}개를 저장했습니다.', [
            result.pages,
            result.files,
          ]);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey(label),
      controller: controller,
      enabled: _editable,
      obscureText: obscure,
      onChanged: (_) => setState(() => _savedPath = null),
      decoration: InputDecoration(labelText: t(label)),
    ),
  );
  Widget _pagesTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          tr(context, '저장할 페이지 {0}쪽 · 선택 {1}쪽', [
            _plan.length,
            _selected.length,
          ]),
        ),
      ),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton(
            onPressed: _editable
                ? () => setState(() => _selected.addAll(_plan.map((p) => p.id)))
                : null,
            child: Text(t('전체 선택')),
          ),
          TextButton(
            onPressed: _editable
                ? () => setState(() => _selected.clear())
                : null,
            child: Text(t('선택 해제')),
          ),
          IconButton(
            tooltip: t('페이지 편집 되돌리기'),
            onPressed: _editable && _undo.isNotEmpty
                ? () => _history(true)
                : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: t('페이지 편집 다시 실행'),
            onPressed: _editable && _redo.isNotEmpty
                ? () => _history(false)
                : null,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      SizedBox(
        height: MediaQuery.sizeOf(context).height < 700 ? 112 : 230,
        child: ReorderableListView.builder(
          itemCount: _plan.length,
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            if (!_editable) return;
            final next = List<_PageEntry>.of(_plan);
            next.insert(newIndex, next.removeAt(oldIndex));
            _change(next);
          },
          itemBuilder: (context, i) {
            final p = _plan[i];
            return ListTile(
              key: ValueKey(p.id),
              dense: true,
              leading: Checkbox(
                value: _selected.contains(p.id),
                onChanged: _editable
                    ? (value) => setState(() {
                        value == true
                            ? _selected.add(p.id)
                            : _selected.remove(p.id);
                      })
                    : null,
              ),
              title: Text(
                p.index == null
                    ? tr(context, '{0}. 빈 페이지', [i + 1])
                    : tr(context, '{0}. 원본 {1}쪽', [i + 1, p.index! + 1]),
              ),
              subtitle: p.rotation == 0
                  ? null
                  : Text(tr(context, '추가 회전 {0}°', [p.rotation])),
              trailing: _editable
                  ? ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    )
                  : null,
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: _editable && _selected.isNotEmpty
                ? () => _change(
                    _plan
                        .map((p) => _selected.contains(p.id) ? p.turn(-90) : p)
                        .toList(),
                  )
                : null,
            icon: const Icon(Icons.rotate_left),
            label: Text(t('왼쪽 회전')),
          ),
          TextButton.icon(
            onPressed: _editable && _selected.isNotEmpty
                ? () => _change(
                    _plan
                        .map((p) => _selected.contains(p.id) ? p.turn(90) : p)
                        .toList(),
                  )
                : null,
            icon: const Icon(Icons.rotate_right),
            label: Text(t('오른쪽 회전')),
          ),
          TextButton.icon(
            onPressed: _editable && _selected.isNotEmpty
                ? () => _change(
                    _plan.where((p) => !_selected.contains(p.id)).toList(),
                  )
                : null,
            icon: const Icon(Icons.delete_outline),
            label: Text(t('선택 페이지 삭제')),
          ),
          TextButton.icon(
            onPressed: _editable
                ? () {
                    final next = List<_PageEntry>.of(_plan);
                    final at = _plan.lastIndexWhere(
                      (p) => _selected.contains(p.id),
                    );
                    next.insert(
                      at < 0 ? next.length : at + 1,
                      _PageEntry(_nextId++, null),
                    );
                    _change(next);
                  }
                : null,
            icon: const Icon(Icons.note_add_outlined),
            label: Text(t('빈 페이지 삽입')),
          ),
          TextButton(
            onPressed: _editable && _selected.isNotEmpty
                ? () => _change(
                    _plan.where((p) => _selected.contains(p.id)).toList(),
                  )
                : null,
            child: Text(t('선택 페이지만 추출')),
          ),
        ],
      ),
      TextField(
        controller: _range,
        enabled: _editable,
        decoration: InputDecoration(
          labelText: t('원본 페이지 범위로 선택'),
          hintText: '1-3, 5',
          suffixIcon: IconButton(
            tooltip: t('범위 선택'),
            onPressed: _editable ? _selectRange : null,
            icon: const Icon(Icons.check),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        t('핸들을 드래그해 순서를 바꾸세요. 빈 페이지는 선택한 페이지 다음에 삽입합니다.'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
  Widget _filesTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t('현재 편집한 페이지 뒤에 PDF를 순서대로 합칩니다.')),
      const SizedBox(height: 12),
      if (_additions.isEmpty) Text(t('추가할 PDF가 없으면 현재 문서만 저장합니다.')),
      for (var i = 0; i < _additions.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _additions[i].name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            children: [
              IconButton(
                tooltip: t('위로 이동'),
                onPressed: _editable && i > 0
                    ? () => setState(() {
                        final item = _additions.removeAt(i);
                        _additions.insert(i - 1, item);
                        _savedPath = null;
                      })
                    : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: t('아래로 이동'),
                onPressed: _editable && i < _additions.length - 1
                    ? () => setState(() {
                        final item = _additions.removeAt(i);
                        _additions.insert(i + 1, item);
                        _savedPath = null;
                      })
                    : null,
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: t('선택 제거'),
                onPressed: _editable
                    ? () => setState(() {
                        _additions.removeAt(i);
                        _savedPath = null;
                      })
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _editable ? _add : null,
          icon: const Icon(Icons.add),
          label: Text(t('합칠 PDF 추가')),
        ),
      ),
      const Divider(height: 32),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(t('PDF 분할')),
        subtitle: Text(t('결과를 여러 PDF로 나누어 ZIP 파일 하나로 저장합니다.')),
        value: _split,
        onChanged: _editable
            ? (value) => setState(() {
                _split = value;
                _savedPath = null;
              })
            : null,
      ),
      if (_split)
        TextField(
          controller: _every,
          onChanged: (_) => setState(() => _savedPath = null),
          enabled: _editable,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: t('몇 쪽마다 나눌까요?'),
            helperText: t('1이면 한 페이지씩 분할합니다. 결과는 최대 500개입니다.'),
          ),
        ),
    ],
  );
  Widget _documentTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t('문서 정보'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      for (final e in const {
        'Title': '제목',
        'Author': '작성자',
        'Subject': '주제',
        'Keywords': '키워드',
      }.entries)
        _field(_metadata[e.key]!, e.value),
      const Divider(height: 24),
      Text(t('PDF에 저장되는 책갈피'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        t('책갈피의 페이지는 편집 전 원본 기준입니다. 페이지 순서가 바뀌면 목적지도 함께 옮깁니다.'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (_bookmarks.where((b) => !b.removed).isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(t('문서 책갈피가 없습니다.')),
        ),
      for (final b in _bookmarks)
        if (!b.removed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('bookmark-name-${_bookmarks.indexOf(b)}'),
                    controller: b.title,
                    onChanged: (_) => setState(() => _savedPath = null),
                    enabled: _editable,
                    decoration: InputDecoration(
                      labelText: t('책갈피 이름'),
                      helperText: b.path != null && b.path!.length > 1
                          ? t('하위 책갈피')
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: TextField(
                    key: ValueKey('bookmark-page-${_bookmarks.indexOf(b)}'),
                    controller: b.page,
                    onChanged: (_) => setState(() => _savedPath = null),
                    enabled: _editable,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t('원본 쪽')),
                  ),
                ),
                IconButton(
                  tooltip: t('책갈피 삭제'),
                  onPressed: _editable
                      ? () => setState(() {
                          b.removed = true;
                          _savedPath = null;
                        })
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _editable
              ? () => setState(() {
                  _bookmarks.add(_BookmarkEntry(null, '', 1));
                  _savedPath = null;
                })
              : null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(t('책갈피 추가')),
        ),
      ),
    ],
  );
  Widget _securityTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t('출력 PDF의 암호'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        _encrypted
            ? t('암호 PDF는 소유자 암호로 연 뒤 새 암호를 정하거나 암호를 해제해야 합니다.')
            : t('새 암호를 설정하면 PDF를 열 때 암호를 입력해야 합니다.'),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: _security,
        decoration: InputDecoration(labelText: t('암호 처리')),
        items: [
          DropdownMenuItem(value: 0, child: Text(t('암호 변경 안 함'))),
          DropdownMenuItem(value: 1, child: Text(t('새 암호 설정'))),
          DropdownMenuItem(value: 2, child: Text(t('암호 해제'))),
        ],
        onChanged: _editable
            ? (value) => setState(() {
                _security = value!;
                _savedPath = null;
              })
            : null,
      ),
      const SizedBox(height: 16),
      if (_security == 1) ...[
        _field(_newPassword, '새 암호', obscure: true),
        _field(_confirm, '새 암호 확인', obscure: true),
        Text(
          t('AES-256으로 보호합니다. 암호는 문서 열기와 소유자 암호로 함께 사용합니다.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      if (_security == 2) Text(t('저장한 사본에서는 암호가 제거됩니다. 원본은 그대로 유지됩니다.')),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: DefaultTabController(
      length: 4,
      child: AlertDialog(
        title: Text(t('PDF 도구')),
        content: SizedBox(
          width: 760,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.source.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                t('변경은 새 파일에 저장합니다. 원본은 유지됩니다.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.hasTemporaryMarks)
                Text(
                  t('화면의 임시 텍스트 표시는 이 도구의 결과에 포함되지 않습니다.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (!_ready || (_encrypted && !_owner))
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputPassword,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: InputDecoration(labelText: t('현재 PDF 암호')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _busy ? null : _inspect,
                      child: Text(t('문서 확인')),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: t('페이지 편집')),
                  Tab(text: t('합치기·분할')),
                  Tab(text: t('정보·책갈피')),
                  Tab(text: t('보안')),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _ready
                    ? TabBarView(
                        children: [
                          for (final child in [
                            _pagesTab(),
                            _filesTab(),
                            _documentTab(),
                            _securityTab(),
                          ])
                            SingleChildScrollView(child: child),
                        ],
                      )
                    : Center(
                        child: _busy
                            ? const CircularProgressIndicator()
                            : Text(t('문서를 확인한 뒤 도구를 사용할 수 있습니다.')),
                      ),
              ),
              if (_signed)
                Text(
                  t('전자서명된 PDF는 편집할 수 없습니다.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_ready && !_owner)
                Text(
                  t('편집하려면 PDF의 소유자 암호를 입력하세요.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy && _ready) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      t(_error!),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (_savedPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '$_summary\n$_savedPath',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(t('닫기')),
          ),
          if (_savedPath != null && _savedExtension == 'pdf')
            TextButton.icon(
              onPressed: () => Navigator.pop(context, _savedPath),
              icon: const Icon(Icons.open_in_new),
              label: Text(t('결과 열기')),
            ),
          FilledButton(
            onPressed: _editable ? _save : null,
            child: Text(t(_split ? '분할 ZIP으로 저장' : '새 PDF로 저장')),
          ),
        ],
      ),
    ),
  );
}
