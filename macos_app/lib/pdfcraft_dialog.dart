import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cy_localization.dart';
import 'pdfcraft_service.dart';

class PdfcraftDialog extends StatefulWidget {
  const PdfcraftDialog({
    super.key,
    required this.source,
    required this.pageCount,
    this.hasTemporaryMarks = false,
  });
  final PdfcraftSource source;
  final int pageCount;
  final bool hasTemporaryMarks;
  @override
  State<PdfcraftDialog> createState() => _PdfcraftDialogState();
}

class _PdfcraftDialogState extends State<PdfcraftDialog> {
  static const _channel = MethodChannel('com.kimmacaroni.cyviewer/file_access');
  late final _pages = TextEditingController(text: '1-${widget.pageCount}');
  final _additions = <PdfcraftSource>[];
  bool _busy = false;
  String? _error, _savedPath;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String _message(Object error) => error is FormatException
      ? error.message
      : error is PlatformException
      ? error.message ?? error.code
      : error.toString();
  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result.isEmpty) return;
      if (_additions.length + result.length > 19) {
        throw const FormatException('PDF는 20개까지 합칠 수 있습니다.');
      }
      final added = <PdfcraftSource>[];
      for (final file in result) {
        if (await file.length() > 256 * 1024 * 1024) {
          throw const FormatException('한 파일은 256MB까지 처리할 수 있습니다.');
        }
        final path = file.path;
        final bytes = await file.readAsBytes();
        final total =
            widget.source.bytes.length +
            _additions.fold<int>(0, (sum, s) => sum + s.bytes.length) +
            added.fold<int>(0, (sum, s) => sum + s.bytes.length) +
            bytes.length;
        if (total > 512 * 1024 * 1024) {
          throw const FormatException('한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.');
        }
        added.add(PdfcraftSource(file.name, bytes, originalPath: path));
      }
      if (mounted) {
        setState(() {
          _additions.addAll(added);
          _savedPath = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _savedPath = null;
    });
    try {
      parsePdfcraftPages(_pages.text, widget.pageCount);
      final sources = [widget.source, ..._additions];
      final bytes = await PdfcraftService.compose(sources, _pages.text);
      if (!mounted) return;
      final path = await _channel.invokeMethod<String>('savePageCopy', {
        'bytes': bytes,
        'name':
            '${widget.source.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}-pages.pdf',
        'originals': sources
            .map((s) => s.originalPath)
            .whereType<String>()
            .toList(),
      });
      if (mounted && path != null) setState(() => _savedPath = path);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(tr(context, '페이지 구성·병합')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(context, '페이지를 골라 새 PDF로 저장하세요.')),
              const SizedBox(height: 8),
              Text(
                tr(context, '원본은 그대로 유지됩니다. 추가한 PDF는 아래 순서로 이어 붙입니다.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.hasTemporaryMarks)
                Text(
                  tr(context, '페이지 구성에는 원본 PDF를 사용합니다. 화면의 임시 표시는 포함되지 않습니다.'),
                ),
              const SizedBox(height: 20),
              Text('${widget.source.name} · ${widget.pageCount}'),
              const SizedBox(height: 12),
              TextField(
                controller: _pages,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: tr(context, '저장할 페이지와 순서'),
                  helperText: tr(context, '예: 1-3, 5 · 순서 변경: 3, 1, 2'),
                ),
              ),
              const SizedBox(height: 16),
              if (_additions.isEmpty)
                Text(
                  tr(context, '추가할 PDF가 없으면 선택한 페이지만 저장합니다.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              for (var i = 0; i < _additions.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text('${i + 2}'),
                  title: Text(
                    _additions[i].name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: tr(context, '선택 제거'),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _additions.removeAt(i);
                            _savedPath = null;
                          }),
                    icon: const Icon(Icons.close),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'PDF 추가')),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(tr(context, 'PDF를 구성하고 있습니다…')),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      tr(context, _error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (_savedPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '${tr(context, '새 PDF를 저장했습니다. 원본은 변경하지 않았습니다.')}\n$_savedPath',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(tr(context, '닫기')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(tr(context, '새 PDF로 저장')),
        ),
      ],
    ),
  );
}
