import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'web_pdf_picker.dart';

void main() => runApp(const CyViewerWebApp());

class CyViewerWebApp extends StatelessWidget {
  const CyViewerWebApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CY뷰어',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: const _WebLibraryPage(),
  );

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff2563eb),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xffe2e8f0)
          : null,
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      useMaterial3: true,
    );
  }
}

class _WebLibraryPage extends StatefulWidget {
  const _WebLibraryPage();

  @override
  State<_WebLibraryPage> createState() => _WebLibraryPageState();
}

class _WebLibraryPageState extends State<_WebLibraryPage> {
  bool _opening = false;
  String? _error;

  Future<void> _pickPdf() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final file = await pickWebPdf();
      if (file == null) {
        return;
      }
      await _openPickedPdf(file);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'PDF를 열 수 없습니다. 다시 선택해 주세요. ($error)');
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _openPickedPdf(PickedWebPdf file) async {
    if (file.bytes.isEmpty) {
      _handlePickError(const FormatException('선택한 PDF를 읽지 못했습니다.'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _WebReaderPage(name: file.name, bytes: file.bytes),
      ),
    );
    if (mounted) setState(() => _opening = false);
  }

  void _handlePickError(Object error) {
    if (!mounted) return;
    setState(() {
      _opening = false;
      _error = 'PDF를 열 수 없습니다. 다시 선택해 주세요. ($error)';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xff0f172a),
      foregroundColor: Colors.white,
      title: const Text('CY뷰어'),
      actions: [
        IconButton(
          tooltip: '설치 방법',
          icon: const Icon(Icons.install_mobile_outlined),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('아이폰에 설치하기'),
              content: const Text(
                'Safari 아래쪽의 공유 버튼을 누른 다음 '
                '“홈 화면에 추가”를 선택하세요. 이후 CY뷰어 아이콘으로 실행할 수 있습니다.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width - 48, 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '아이폰에서 PDF를 열어 보세요',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '문서는 서버로 전송되지 않고 이 기기에서만 열립니다. '
                    '웹앱을 닫으면 PDF 원본은 저장되지 않습니다.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 160,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FilledButton.icon(
                          onPressed: _opening ? null : _pickPdf,
                          icon: _opening
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.folder_open),
                          label: Text(_opening ? 'PDF 여는 중…' : 'PDF 선택'),
                        ),
                        if (!_opening)
                          WebPdfPickRegion(
                            onPicked: _openPickedPdf,
                            onError: _handlePickError,
                          ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xffdc2626).withAlpha(22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xffdc2626)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

enum _ViewMode { scroll, horizontal, facing }

class _WebReaderPage extends StatefulWidget {
  const _WebReaderPage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  @override
  State<_WebReaderPage> createState() => _WebReaderPageState();
}

class _WebReaderPageState extends State<_WebReaderPage> {
  final _controller = PdfViewerController();
  final _searchInput = TextEditingController();
  PdfTextSearcher? _searcher;
  int _pageCount = 0;
  int _currentPage = 1;
  bool _searching = false;
  bool _busy = false;
  _ViewMode _viewMode = _ViewMode.scroll;
  List<int> _bookmarks = [];

  String get _bookmarkKey =>
      'web_pdf_bookmarks_${base64Url.encode(utf8.encode('${widget.name}:${widget.bytes.length}'))}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadBookmarks());
  }

  Future<void> _loadBookmarks() async {
    final values =
        (await SharedPreferences.getInstance()).getStringList(_bookmarkKey) ??
        const [];
    if (!mounted) return;
    setState(() {
      _bookmarks =
          values
              .map(int.tryParse)
              .whereType<int>()
              .where((e) => e > 0)
              .toSet()
              .toList()
            ..sort();
    });
  }

  Future<void> _saveBookmarks() async => (await SharedPreferences.getInstance())
      .setStringList(_bookmarkKey, _bookmarks.map((e) => '$e').toList());

  Future<void> _toggleBookmark() async {
    if (_pageCount == 0) return;
    setState(() {
      _bookmarks.contains(_currentPage)
          ? _bookmarks.remove(_currentPage)
          : _bookmarks.add(_currentPage);
      _bookmarks.sort();
    });
    await _saveBookmarks();
    _message(
      _bookmarks.contains(_currentPage) ? '책갈피를 저장했습니다.' : '책갈피를 삭제했습니다.',
    );
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _showBookmarks() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 360,
          child: _bookmarks.isEmpty
              ? const Center(child: Text('저장한 책갈피가 없습니다.'))
              : ListView(
                  children: [
                    const ListTile(title: Text('책갈피 목록')),
                    for (final page in _bookmarks)
                      ListTile(
                        leading: const Icon(Icons.bookmark),
                        title: Text('$page 페이지'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _controller.goToPage(pageNumber: page);
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _goToPage() async {
    final input = TextEditingController(text: '$_currentPage');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('페이지로 이동'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1~$_pageCount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(input.text)),
            child: const Text('이동'),
          ),
        ],
      ),
    );
    input.dispose();
    if (page != null && page >= 1 && page <= _pageCount) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Printing.layoutPdf(
        name: widget.name,
        onLayout: (_) async => widget.bytes,
      );
    } on Object catch (error) {
      _message('인쇄 창을 열 수 없습니다: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCopy() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Printing.sharePdf(bytes: widget.bytes, filename: widget.name);
      if (mounted) _message('공유 또는 파일 저장 화면을 열었습니다.');
    } on Object catch (error) {
      _message('PDF 복사본을 내보낼 수 없습니다: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSearch() => setState(() => _searching = true);

  void _hideSearch() {
    _searcher?.resetTextSearch();
    _searchInput.clear();
    setState(() => _searching = false);
  }

  Future<void> _showTools() async {
    Future<void> run(FutureOr<void> Function() action) async {
      Navigator.pop(context);
      await action();
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: ListView(
            children: [
              const ListTile(title: Text('문서 도구'), subtitle: Text('읽기와 저장 기능')),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text('책갈피 목록'),
                onTap: () => run(_showBookmarks),
              ),
              ListTile(
                leading: const Icon(Icons.find_in_page_outlined),
                title: const Text('페이지로 이동'),
                onTap: _pageCount == 0 ? null : () => run(_goToPage),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SegmentedButton<_ViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: _ViewMode.scroll,
                      icon: Icon(Icons.view_day_outlined),
                      label: Text('세로'),
                    ),
                    ButtonSegment(
                      value: _ViewMode.horizontal,
                      icon: Icon(Icons.view_carousel_outlined),
                      label: Text('가로'),
                    ),
                    ButtonSegment(
                      value: _ViewMode.facing,
                      icon: Icon(Icons.menu_book_outlined),
                      label: Text('두 쪽'),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (selection) {
                    setState(() => _viewMode = selection.first);
                    Navigator.pop(context);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('확대'),
                onTap: () => run(_controller.zoomUp),
              ),
              ListTile(
                leading: const Icon(Icons.zoom_out),
                title: const Text('축소'),
                onTap: () => run(_controller.zoomDown),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('인쇄'),
                onTap: () => run(_print),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('PDF 복사본 저장·공유'),
                onTap: () => run(_saveCopy),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('웹 버전 안내'),
                subtitle: Text('OCR과 페이지 이미지 저장은 브라우저 제한으로 제공되지 않습니다.'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchInput.dispose();
    _searcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookmarked = _bookmarks.contains(_currentPage);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff0f172a),
        foregroundColor: Colors.white,
        title: _searching && _searcher != null
            ? TextField(
                controller: _searchInput,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: '문서에서 검색',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onChanged: (text) =>
                    _searcher?.startTextSearch(text, searchImmediately: true),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('CY뷰어', style: TextStyle(fontSize: 12)),
                  Text(widget.name, overflow: TextOverflow.ellipsis),
                ],
              ),
        actions: _searching && _searcher != null
            ? [
                IconButton(
                  tooltip: '이전 결과',
                  onPressed: _searcher!.goToPrevMatch,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: '다음 결과',
                  onPressed: _searcher!.goToNextMatch,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: '검색 닫기',
                  onPressed: _hideSearch,
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                IconButton(
                  tooltip: '검색',
                  onPressed: _searcher == null ? null : _showSearch,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: bookmarked ? '책갈피 삭제' : '이 페이지 책갈피',
                  onPressed: _toggleBookmark,
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  ),
                ),
                IconButton(
                  tooltip: '문서 도구',
                  onPressed: _showTools,
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
      ),
      body: Stack(
        children: [
          PdfViewer.data(
            widget.bytes,
            sourceName: '${widget.name}:${widget.bytes.length}',
            key: ValueKey(_viewMode),
            controller: _controller,
            params: PdfViewerParams(
              errorBannerBuilder: (context, error, _, _) => Center(
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Color(0xffdc2626),
                        ),
                        const SizedBox(height: 12),
                        const Text('PDF를 표시할 수 없습니다.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('다른 PDF 선택'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              onViewerReady: (document, _) {
                _searcher?.dispose();
                final searcher = PdfTextSearcher(_controller);
                if (!mounted) {
                  return;
                }
                setState(() {
                  _pageCount = document.pages.length;
                  _searcher = searcher;
                  _bookmarks.removeWhere((page) => page > _pageCount);
                });
              },
              onPageChanged: (page) {
                if (page != null && mounted) {
                  setState(() => _currentPage = page);
                }
              },
              pagePaintCallbacks: [
                if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
              ],
              layoutPages: _viewMode == _ViewMode.scroll
                  ? null
                  : (pages, params) {
                      if (_viewMode == _ViewMode.horizontal) {
                        final height = pages.fold<double>(
                          0,
                          (value, page) => math.max(value, page.height),
                        );
                        var x = params.margin;
                        final layouts = <Rect>[];
                        for (final page in pages) {
                          layouts.add(
                            Rect.fromLTWH(
                              x,
                              params.margin,
                              page.width,
                              page.height,
                            ),
                          );
                          x += page.width + params.margin;
                        }
                        return PdfPageLayout(
                          pageLayouts: layouts,
                          documentSize: Size(x, height + params.margin * 2),
                        );
                      }
                      final width = pages.fold<double>(
                        0,
                        (value, page) => math.max(value, page.width),
                      );
                      var y = params.margin;
                      final layouts = <Rect>[];
                      for (var index = 0; index < pages.length; index++) {
                        final page = pages[index];
                        final left = index.isOdd;
                        layouts.add(
                          Rect.fromLTWH(
                            left
                                ? params.margin * 2 + width
                                : params.margin + width - page.width,
                            y,
                            page.width,
                            page.height,
                          ),
                        );
                        if (left || index == pages.length - 1) {
                          y += page.height + params.margin;
                        }
                      }
                      return PdfPageLayout(
                        pageLayouts: layouts,
                        documentSize: Size(width * 2 + params.margin * 3, y),
                      );
                    },
            ),
          ),
          if (_pageCount > 0)
            Positioned(
              right: 12,
              bottom: 12,
              child: Chip(label: Text('$_currentPage / $_pageCount')),
            ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
