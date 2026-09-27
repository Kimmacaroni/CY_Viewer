import 'cy_localization.dart';

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
import 'web_pdf_load_guard.dart';
import 'cy_design.dart';
import 'recent_web_store.dart';
import 'cy_recent_files.dart';
import 'web_inline_print.dart';
import 'web_native_control.dart';
import 'web_print_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CyLanguage.instance.load();
  runApp(const CyViewerWebApp());
}

class CyViewerWebApp extends StatelessWidget {
  const CyViewerWebApp({super.key, this.saveRecent = recentWebSave});

  final Future<void> Function(String, Uint8List) saveRecent;

  @override
  Widget build(BuildContext context) => CyLanguageScope(
    child: ListenableBuilder(
      listenable: CyLanguage.instance,
      builder: (context, _) => MaterialApp(
        title: tr(context, "CY뷰어"),
        debugShowCheckedModeBanner: false,
        locale: CyLanguage.instance.locale,
        supportedLocales: [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: CyDesign.theme(Brightness.light),
        darkTheme: CyDesign.theme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: _WebLibraryPage(saveRecent: saveRecent),
      ),
    ),
  );
}

class _WebLibraryPage extends StatefulWidget {
  const _WebLibraryPage({required this.saveRecent});

  final Future<void> Function(String, Uint8List) saveRecent;

  @override
  State<_WebLibraryPage> createState() => _WebLibraryPageState();
}

class _WebLibraryPageState extends State<_WebLibraryPage> {
  bool _opening = false;
  String? _error;
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
  }

  Future<void> _loadRecent() async {
    try {
      final rows = await recentWebList().timeout(const Duration(seconds: 10));
      if (mounted) setState(() => _recent = rows);
    } on Object {
      if (mounted) {
        setState(
          () => _error = trNow('최근 파일 목록을 불러오지 못했습니다. PDF 열기는 계속 사용할 수 있습니다.'),
        );
      }
    }
  }

  Future<void> _remember(PickedWebPdf file) async {
    try {
      await recentWebSave(
        file.name,
        file.bytes,
      ).timeout(const Duration(seconds: 15));
      await _loadRecent();
    } on Object {
      if (mounted) {
        setState(
          () => _error = trNow('최근 파일을 저장하지 못했습니다. 브라우저 저장 공간을 확인해 주세요.'),
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error!)));
      }
    }
  }

  Future<void> _openRecent(Map<String, dynamic> row) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final bytes = await recentWebRead(row['id'] as String)
          .timeout(const Duration(seconds: 15));
      if (bytes == null) {
        throw StateError(trNow('저장된 사본을 찾을 수 없습니다. PDF를 다시 선택해 주세요.'));
      }
      if (mounted) {
        await _openPickedPdf(
          PickedWebPdf(name: row['name'] as String, bytes: bytes),
        );
      }
    } on Object catch (error) {
      _handlePickError(error);
    }
  }

  Future<void> _removeRecent(String id) async {
    try {
      await recentWebRemove(id).timeout(const Duration(seconds: 10));
      await _loadRecent();
    } on Object catch (error) {
      _handlePickError(error);
    }
  }

  Future<void> _openPickedPdf(PickedWebPdf file) async {
    if (file.bytes.isEmpty) {
      _handlePickError(FormatException(tr(context, "선택한 PDF를 읽지 못했습니다.")));
      return;
    }
    if (!mounted) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _WebReaderPage(
            name: file.name,
            bytes: file.bytes,
            onOpened: () => unawaited(_remember(file)),
          ),
        ),
      );
    } finally {
      // 최근 사본 저장은 백그라운드 작업이다. 복귀 후 파일 선택을 막지 않는다.
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _filePicker() => _opening
      ? const Center(child: CircularProgressIndicator())
      : WebPdfPickRegion(onPicked: _openPickedPdf, onError: _handlePickError);

  void _handlePickError(Object error) {
    if (!mounted) return;
    setState(() {
      _opening = false;
      _error = tr(context, "PDF를 열 수 없습니다. 다시 선택해 주세요. ({0})", [error]);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: CyBrand(),
      actions: [
        const CyLanguageButton(),
        IconButton(
          tooltip: tr(context, "설치 방법"),
          icon: Icon(Icons.install_mobile_outlined),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(tr(context, "아이폰에 설치하기")),
              content: Text(
                tr(context, "Safari 아래쪽의 공유 버튼을 누른 다음 ") +
                    tr(context, "“홈 화면에 추가”를 선택하세요. 이후 CY뷰어 아이콘으로 실행할 수 있습니다."),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr(context, "확인")),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_recent.isNotEmpty) ...[
                  SizedBox(
                    height: math.max(
                      52,
                      MediaQuery.textScalerOf(context).scale(16) + 28,
                    ),
                    child: _filePicker(),
                  ),
                  const SizedBox(height: 20),
                  CyRecentFiles(
                    files: _recent,
                    enabled: !_opening,
                    onOpen: _openRecent,
                    onRemove: _removeRecent,
                  ),
                ] else
                  CyDocumentWelcome(
                    web: true,
                    action: SizedBox(
                      height: math.max(
                        52,
                        MediaQuery.textScalerOf(context).scale(16) + 28,
                      ),
                      child: _filePicker(),
                    ),
                  ),
                if (_error != null) ...[
                  SizedBox(height: 24),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
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
  );
}

enum _ViewMode { scroll, horizontal, facing }

class _WebReaderPage extends StatefulWidget {
  const _WebReaderPage({
    required this.name,
    required this.bytes,
    required this.onOpened,
  });

  final String name;
  final Uint8List bytes;
  final VoidCallback onOpened;

  @override
  State<_WebReaderPage> createState() => _WebReaderPageState();
}

class _WebReaderPageState extends State<_WebReaderPage> {
  final _controller = PdfViewerController();
  final _searchInput = TextEditingController();
  PdfTextSearcher? _searcher;
  bool _remembered = false;
  int _pageCount = 0;
  int _currentPage = 1;
  bool _searching = false;
  bool _sharing = false;
  bool _printActive = false;
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
        [];
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
      _bookmarks.contains(_currentPage)
          ? trNow("책갈피를 저장했습니다.")
          : trNow("책갈피를 삭제했습니다."),
    );
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _showBookmarks() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 360,
          child: _bookmarks.isEmpty
              ? Center(child: Text(tr(context, "저장한 책갈피가 없습니다.")))
              : ListView(
                  children: [
                    ListTile(title: Text(tr(context, "책갈피 목록"))),
                    for (final page in _bookmarks)
                      ListTile(
                        leading: Icon(Icons.bookmark),
                        title: Text(tr(context, "{0} 페이지", [page])),
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
        title: Text(tr(context, "페이지로 이동")),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1~$_pageCount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, "취소")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(input.text)),
            child: Text(tr(context, "이동")),
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
    if (_printActive) return;
    if (!_controller.isReady || _pageCount < 1) {
      _message(tr(context, 'PDF 페이지를 불러오고 있습니다.'));
      return;
    }
    _printActive = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => InlinePrintDialog(
          document: _controller.document,
          current: _currentPage,
          openOriginal: () => openPrintPdf(widget.bytes),
        ),
      );
    } on Object catch (error) {
      _message(trNow("인쇄 창을 열 수 없습니다: {0}", [error]));
    } finally {
      _printActive = false;
    }
  }

  Future<void> _saveCopy() async {
    if (_sharing) return;
    _sharing = true;
    try {
      await Printing.sharePdf(
        bytes: widget.bytes,
        filename: widget.name,
      ).timeout(const Duration(seconds: 45));
      if (mounted) _message(tr(context, "공유 또는 파일 저장 화면을 열었습니다."));
    } on Object catch (error) {
      _message(trNow("PDF 복사본을 내보낼 수 없습니다: {0}", [error]));
    } finally {
      _sharing = false;
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
              const Align(
                alignment: Alignment.centerRight,
                child: CyLanguageButton(),
              ),
              ListTile(
                title: Text(tr(context, "문서 도구")),
                subtitle: Text(tr(context, "읽기와 저장 기능")),
              ),
              ListTile(
                leading: Icon(Icons.bookmarks_outlined),
                title: Text(tr(context, "책갈피 목록")),
                onTap: () => run(_showBookmarks),
              ),
              ListTile(
                leading: Icon(Icons.find_in_page_outlined),
                title: Text(tr(context, "페이지로 이동")),
                onTap: _pageCount == 0 ? null : () => run(_goToPage),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SegmentedButton<_ViewMode>(
                  segments: [
                    ButtonSegment(
                      value: _ViewMode.scroll,
                      icon: Icon(Icons.view_day_outlined),
                      label: Text(tr(context, "세로")),
                    ),
                    ButtonSegment(
                      value: _ViewMode.horizontal,
                      icon: Icon(Icons.view_carousel_outlined),
                      label: Text(tr(context, "가로")),
                    ),
                    ButtonSegment(
                      value: _ViewMode.facing,
                      icon: Icon(Icons.menu_book_outlined),
                      label: Text(tr(context, "두 쪽")),
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
                leading: Icon(Icons.zoom_in),
                title: Text(tr(context, "확대")),
                onTap: () => run(_controller.zoomUp),
              ),
              ListTile(
                leading: Icon(Icons.zoom_out),
                title: Text(tr(context, "축소")),
                onTap: () => run(_controller.zoomDown),
              ),
              Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: WebNativeButton(
                  label: tr(context, "인쇄"),
                  onPressed: () => run(_print),
                ),
              ),
              ListTile(
                leading: Icon(Icons.ios_share),
                title: Text(tr(context, "PDF 복사본 저장·공유")),
                onTap: () => run(_saveCopy),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.open_in_new),
                title: Text(tr(context, "브라우저로 PDF 열기")),
                onTap: () {
                  Navigator.pop(context);
                  openWebPdfInBrowser(widget.bytes);
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text(tr(context, "웹 버전 안내")),
                subtitle: Text(
                  tr(context, "OCR과 페이지 이미지 저장은 브라우저 제한으로 제공되지 않습니다."),
                ),
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
        title: _searching && _searcher != null
            ? TextField(
                controller: _searchInput,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: tr(context, "문서에서 검색"),
                  border: InputBorder.none,
                ),
                onChanged: (text) =>
                    _searcher?.startTextSearch(text, searchImmediately: true),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(context, "CY뷰어"), style: TextStyle(fontSize: 12)),
                  Text(widget.name, overflow: TextOverflow.ellipsis),
                ],
              ),
        actions: _searching && _searcher != null
            ? [
                IconButton(
                  tooltip: tr(context, "이전 결과"),
                  onPressed: _searcher!.goToPrevMatch,
                  icon: Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: tr(context, "다음 결과"),
                  onPressed: _searcher!.goToNextMatch,
                  icon: Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: tr(context, "검색 닫기"),
                  onPressed: _hideSearch,
                  icon: Icon(Icons.close),
                ),
              ]
            : [
                IconButton(
                  tooltip: tr(context, "검색"),
                  onPressed: _searcher == null ? null : _showSearch,
                  icon: Icon(Icons.search),
                ),
                IconButton(
                  tooltip: bookmarked
                      ? tr(context, "책갈피 삭제")
                      : tr(context, "이 페이지 책갈피"),
                  onPressed: _toggleBookmark,
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  ),
                ),
                IconButton(
                  tooltip: tr(context, "문서 도구"),
                  onPressed: _showTools,
                  icon: Icon(Icons.more_horiz),
                ),
              ],
      ),
      body: CyReaderWorkspace(
        onOpen: () => Navigator.of(context).pop(),
        onSearch: _searcher == null ? null : _showSearch,
        onPage: _pageCount == 0 ? null : _goToPage,
        onBookmark: _toggleBookmark,
        onTools: _showTools,
        onZoomIn: _controller.zoomUp,
        onZoomOut: _controller.zoomDown,
        onSave: _saveCopy,
        onPrint: _print,
        printAction: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: WebNativeButton(label: tr(context, "인쇄"), onPressed: _print),
        ),
        child: Stack(
          children: [
            WebPdfLoadGuard(
              initialize: pdfrxFlutterInitialize,
              onOpenInBrowser: () => openWebPdfInBrowser(widget.bytes),
              onChooseAnother: () => Navigator.of(context).pop(),
              viewerBuilder: (onReady) => PdfViewer.data(
                widget.bytes,
                sourceName: '${widget.name}:${widget.bytes.length}',
                key: ValueKey(_viewMode),
                controller: _controller,
                params: PdfViewerParams(
                  loadingBannerBuilder: (context, _, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(tr(context, "PDF 페이지를 불러오고 있습니다.")),
                      ],
                    ),
                  ),
                  onDocumentLoadFinished: (documentRef, succeeded) {
                    if (!succeeded) onReady();
                  },
                  errorBannerBuilder: (context, error, _, _) => Center(
                    child: Card(
                      margin: EdgeInsets.all(24),
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Color(0xffdc2626),
                            ),
                            SizedBox(height: 12),
                            Text(tr(context, "PDF를 표시할 수 없습니다.")),
                            SizedBox(height: 12),
                            FilledButton(
                              onPressed: () =>
                                  openWebPdfInBrowser(widget.bytes),
                              child: Text(tr(context, "브라우저로 PDF 열기")),
                            ),
                            SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(tr(context, "다른 PDF 선택")),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  onViewerReady: (document, _) {
                    if (!_remembered) {
                      _remembered = true;
                      widget.onOpened();
                    }
                    onReady();
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
                    if (_searcher != null)
                      _searcher!.pageTextMatchPaintCallback,
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
                            documentSize: Size(
                              width * 2 + params.margin * 3,
                              y,
                            ),
                          );
                        },
                ),
              ),
            ),
            if (_pageCount > 0)
              Positioned(
                right: 12,
                bottom: 12,
                child: Chip(label: Text('$_currentPage / $_pageCount')),
              ),
          ],
        ),
      ),
    );
  }
}
