import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_commands.dart';

enum _ReaderAction {
  bookmark,
  bookmarks,
  zoomOut,
  zoomIn,
  goToPage,
  clearMarks,
  help,
}

enum _MarkType { highlight, underline, strike, bold }

enum _ViewMode { scroll, horizontal, facing }

enum _ExportFormat { pdf, png, jpg }

class _TextMark {
  const _TextMark(this.range, this.type);

  final PdfPageTextRange range;
  final _MarkType type;
}

class AdvancedPdfReaderPage extends StatefulWidget {
  const AdvancedPdfReaderPage({
    super.key,
    required this.path,
    required this.name,
    required this.initialPage,
  });

  final String path;
  final String name;
  final int initialPage;

  @override
  State<AdvancedPdfReaderPage> createState() => _AdvancedPdfReaderPageState();
}

class _AdvancedPdfReaderPageState extends State<AdvancedPdfReaderPage> {
  static const _ocrChannel = MethodChannel('com.kimmacaroni.cyviewer/ocr');
  final _controller = PdfViewerController();
  final _searchInput = TextEditingController();
  PdfTextSearcher? _searcher;
  int _pageCount = 0;
  int _currentPage = 1;
  List<int> _bookmarks = [];
  bool _searching = false;
  final List<_TextMark> _marks = [];
  bool _hasSelectedText = false;
  bool _busy = false;
  String _busyMessage = '';
  _ViewMode _viewMode = _ViewMode.scroll;
  Uint8List? _pdfData;
  Object? _pdfLoadError;
  late final Map<String, AppCommandCallback> _commandHandlers;

  String get _bookmarkKey =>
      'pdf_bookmarks_${base64Url.encode(utf8.encode(widget.path))}';

  @override
  void initState() {
    super.initState();
    _commandHandlers = AppCommandDispatcher.register({
      'find': _showSearch,
      'findNext': () => _searcher?.goToNextMatch(),
      'findPrevious': () => _searcher?.goToPrevMatch(),
      'zoomIn': _controller.zoomUp,
      'zoomOut': _controller.zoomDown,
      'actualSize': _showActualSize,
      'print': _printDocument,
      'saveCopy': () => _export(_ExportFormat.pdf),
      'bookmark': _toggleBookmark,
      'goToPage': _goToPage,
    });
    _currentPage = widget.initialPage;
    _loadBookmarks();
    _loadPdfData();
  }

  Future<void> _loadPdfData() async {
    if (mounted) {
      setState(() {
        _pdfData = null;
        _pdfLoadError = null;
      });
    }
    try {
      final data = await File(widget.path).readAsBytes();
      if (data.isEmpty) throw const FormatException('빈 PDF 파일입니다.');
      if (!mounted) return;
      setState(() => _pdfData = data);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _pdfLoadError = error);
    }
  }

  Widget _buildPdfLoadingState() {
    final error = _pdfLoadError;
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'PDF를 읽을 수 없습니다',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                '파일 접근 권한이 만료되었을 수 있습니다. 다시 시도하거나 문서함에서 PDF를 다시 선택해 주세요.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadPdfData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_currentPage),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('문서함으로 돌아가기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadBookmarks() async {
    try {
      final values =
          (await SharedPreferences.getInstance()).getStringList(_bookmarkKey) ??
          [];
      if (!mounted) return;
      setState(
        () => _bookmarks =
            values
                .map(int.tryParse)
                .whereType<int>()
                .where((page) => page > 0)
                .toSet()
                .toList()
              ..sort(),
      );
    } on Object catch (error) {
      _showMessage('책갈피를 불러오지 못했습니다: $error');
    }
  }

  Future<void> _saveBookmarks() async => (await SharedPreferences.getInstance())
      .setStringList(_bookmarkKey, _bookmarks.map((e) => '$e').toList());

  Future<void> _toggleBookmark() async {
    if (_pageCount == 0 || !mounted) return;
    setState(() {
      if (_bookmarks.contains(_currentPage)) {
        _bookmarks.remove(_currentPage);
      } else {
        _bookmarks.add(_currentPage);
        _bookmarks.sort();
      }
    });
    try {
      await _saveBookmarks();
    } on Object catch (error) {
      _showMessage('책갈피를 저장하지 못했습니다: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showBookmarks() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: 360,
        child: _bookmarks.isEmpty
            ? const Center(child: Text('저장한 책갈피가 없습니다.'))
            : ListView.builder(
                itemCount: _bookmarks.length,
                itemBuilder: (context, index) {
                  final page = _bookmarks[index];
                  return ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text('$page 페이지'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _controller.goToPage(pageNumber: page);
                    },
                    trailing: IconButton(
                      tooltip: '삭제',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        setState(() => _bookmarks.remove(page));
                        await _saveBookmarks();
                        if (context.mounted) Navigator.pop(context);
                        _showBookmarks();
                      },
                    ),
                  );
                },
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

  void _startSearch(String text) {
    _searcher?.startTextSearch(text, searchImmediately: true);
    if (mounted) setState(() {});
  }

  void _showSearch() {
    if (!mounted || _searcher == null) return;
    setState(() => _searching = true);
  }

  void _hideSearch() {
    _searcher?.resetTextSearch();
    _searchInput.clear();
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _showActualSize() async {
    if (_pageCount == 0) return;
    await _controller.setZoom(_controller.centerPosition, 1);
  }

  Future<void> _applyMark(_MarkType type) async {
    final selection = _controller.textSelectionDelegate;
    final ranges = await selection.getSelectedTextRanges();
    if (!mounted) return;
    if (ranges.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('먼저 문서의 텍스트를 드래그해 선택해 주세요.')),
        );
      }
      return;
    }
    setState(
      () => _marks.addAll(ranges.map((range) => _TextMark(range, type))),
    );
    await selection.clearTextSelection();
    if (mounted) setState(() => _hasSelectedText = false);
    _controller.invalidate();
  }

  void _clearMarks() {
    if (_marks.isEmpty) return;
    setState(_marks.clear);
    _controller.invalidate();
  }

  Future<void> _printDocument() async {
    if (_busy) return;
    try {
      setState(() {
        _busy = true;
        _busyMessage = '인쇄할 문서를 준비하고 있습니다…';
      });
      final bytes = await File(widget.path).readAsBytes();
      await Printing.layoutPdf(
        name: widget.name,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      _showMessage('인쇄 창을 열 수 없습니다: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(_ExportFormat format) async {
    if (_busy) return;
    try {
      setState(() {
        _busy = true;
        _busyMessage = '파일을 준비하고 있습니다…';
      });
      final bytes = await File(widget.path).readAsBytes();
      final baseName = widget.name.toLowerCase().endsWith('.pdf')
          ? widget.name.substring(0, widget.name.length - 4)
          : widget.name;
      if (format == _ExportFormat.pdf) {
        final savedPath = await FilePicker.saveFile(
          dialogTitle: 'PDF로 저장',
          fileName: '$baseName-복사본.pdf',
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (savedPath != null) _showMessage('PDF 복사본을 저장했습니다.');
      } else {
        final directory = await FilePicker.getDirectoryPath(
          dialogTitle: format == _ExportFormat.png
              ? 'PNG 저장 폴더 선택'
              : 'JPG 저장 폴더 선택',
        );
        if (directory == null) return;
        var pageNumber = 0;
        await for (final page in Printing.raster(bytes, dpi: 180)) {
          pageNumber++;
          if (mounted) {
            setState(
              () => _busyMessage = '페이지 $pageNumber / $_pageCount 저장 중…',
            );
          }
          final extension = format == _ExportFormat.png ? 'png' : 'jpg';
          final output = File(
            '$directory${Platform.pathSeparator}$baseName-${pageNumber.toString().padLeft(3, '0')}.$extension',
          );
          if (format == _ExportFormat.png) {
            await output.writeAsBytes(await page.toPng(), flush: true);
          } else {
            final decoded = image_lib.decodePng(await page.toPng());
            if (decoded == null) {
              throw StateError('페이지 이미지를 변환할 수 없습니다.');
            }
            await output.writeAsBytes(
              image_lib.encodeJpg(decoded, quality: 92),
              flush: true,
            );
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$pageNumber개 페이지를 저장했습니다.')));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장할 수 없습니다: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runOcr() async {
    if (_busy) return;
    try {
      setState(() {
        _busy = true;
        _busyMessage = '문서 전체의 글자를 인식하고 있습니다…';
      });
      final text = await _ocrChannel.invokeMethod<String>('recognizePdf', {
        'path': widget.path,
      });
      if (!mounted) return;
      final result = text?.trim() ?? '';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OCR 결과'),
          content: SizedBox(
            width: 680,
            height: 460,
            child: result.isEmpty
                ? const Center(child: Text('인식된 텍스트가 없습니다.'))
                : SingleChildScrollView(child: SelectableText(result)),
          ),
          actions: [
            if (result.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: result));
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('전체 복사'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'OCR을 실행할 수 없습니다.');
    } on Object catch (error) {
      _showMessage('OCR을 실행할 수 없습니다: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _paintMarks(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final mark in _marks.where(
      (item) => item.range.pageNumber == page.pageNumber,
    )) {
      final rect = mark.range.bounds
          .toRect(page: page, scaledPageSize: pageRect.size)
          .translate(pageRect.left, pageRect.top);
      switch (mark.type) {
        case _MarkType.highlight:
          canvas.drawRect(rect, Paint()..color = Colors.yellow.withAlpha(130));
        case _MarkType.underline:
          canvas.drawLine(
            Offset(rect.left, rect.bottom - 2),
            Offset(rect.right, rect.bottom - 2),
            Paint()
              ..color = Colors.blueAccent
              ..strokeWidth = 3,
          );
        case _MarkType.strike:
          canvas.drawLine(
            Offset(rect.left, rect.center.dy),
            Offset(rect.right, rect.center.dy),
            Paint()
              ..color = Colors.redAccent
              ..strokeWidth = 3,
          );
        case _MarkType.bold:
          canvas.drawRect(rect, Paint()..color = Colors.black.withAlpha(32));
          canvas.drawLine(
            Offset(rect.left, rect.bottom - 2),
            Offset(rect.right, rect.bottom - 2),
            Paint()
              ..color = Colors.black87
              ..strokeWidth = 2,
          );
      }
    }
  }

  Future<void> _selectAction(_ReaderAction action) async {
    switch (action) {
      case _ReaderAction.bookmark:
        await _toggleBookmark();
      case _ReaderAction.bookmarks:
        await _showBookmarks();
      case _ReaderAction.zoomOut:
        await _controller.zoomDown();
      case _ReaderAction.zoomIn:
        await _controller.zoomUp();
      case _ReaderAction.goToPage:
        await _goToPage();
      case _ReaderAction.clearMarks:
        _clearMarks();
      case _ReaderAction.help:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('CY뷰어 사용 방법'),
            content: Text(
              Platform.isMacOS
                  ? '• ⌘O: PDF 열기\n• ⌘F: 문서 검색\n• ⌘G / ⇧⌘G: 다음·이전 검색 결과\n• ⌘+ / ⌘- / ⌘0: 확대·축소·실제 크기\n• ⌘S: PDF 복사본 저장\n• ⌘P: 인쇄\n• 텍스트 드래그 후 하단 도구막대: 복사·형광펜·밑줄·취소선·강조'
                  : '• 돋보기: 문서 텍스트 검색\n• 문서 도구: 책갈피, 확대·축소, 페이지 이동, 인쇄, OCR, 저장\n• 화면을 두 손가락으로 확대·축소\n• 텍스트를 길게 누르거나 드래그한 뒤 하단 도구막대에서 복사·형광펜·밑줄·취소선·강조',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _showMobileTools() async {
    Future<void> run(FutureOr<void> Function() action) async {
      Navigator.pop(context);
      await action();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              const ListTile(
                title: Text('문서 도구'),
                subtitle: Text('macOS와 동일한 기능을 사용할 수 있습니다.'),
              ),
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
              const Divider(),
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
                    Navigator.pop(sheetContext);
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
              ListTile(
                leading: const Icon(Icons.center_focus_strong),
                title: const Text('실제 크기'),
                onTap: () => run(_showActualSize),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('인쇄'),
                onTap: () => run(_printDocument),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('문서 전체 OCR'),
                onTap: _busy ? null : () => run(_runOcr),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('PDF 복사본 저장'),
                onTap: () => run(() => _export(_ExportFormat.pdf)),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('PNG로 저장'),
                onTap: () => run(() => _export(_ExportFormat.png)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('JPG로 저장'),
                onTap: () => run(() => _export(_ExportFormat.jpg)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.layers_clear_outlined),
                title: const Text('이 문서의 표시 지우기'),
                onTap: () => run(_clearMarks),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('사용 방법'),
                onTap: () => run(() => _selectAction(_ReaderAction.help)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    AppCommandDispatcher.unregister(_commandHandlers);
    _searchInput.dispose();
    _searcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_currentPage);
      },
      child: Scaffold(
        appBar: AppBar(
          title: _searching && _searcher != null
              ? TextField(
                  controller: _searchInput,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '문서에서 검색',
                    border: InputBorder.none,
                  ),
                  onChanged: _startSearch,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'CY뷰어',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(widget.name, overflow: TextOverflow.ellipsis),
                  ],
                ),
          actions: _searching && _searcher != null
              ? [
                  if (!compact)
                    AnimatedBuilder(
                      animation: _searcher!,
                      builder: (context, child) => Text(
                        '${_searcher!.currentIndex == null ? 0 : _searcher!.currentIndex! + 1}/${_searcher!.matches.length}',
                      ),
                    ),
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
              : compact
              ? [
                  IconButton(
                    tooltip: '검색',
                    onPressed: _searcher == null ? null : _showSearch,
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: _bookmarks.contains(_currentPage)
                        ? '책갈피 삭제'
                        : '이 페이지 책갈피',
                    onPressed: _toggleBookmark,
                    icon: Icon(
                      _bookmarks.contains(_currentPage)
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                  ),
                  IconButton(
                    tooltip: '문서 도구',
                    onPressed: _showMobileTools,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: '검색',
                    onPressed: _searcher == null ? null : _showSearch,
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: _bookmarks.contains(_currentPage)
                        ? '책갈피 삭제'
                        : '이 페이지 책갈피',
                    onPressed: _toggleBookmark,
                    icon: Icon(
                      _bookmarks.contains(_currentPage)
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                  ),
                  IconButton(
                    tooltip: '책갈피 목록',
                    onPressed: _showBookmarks,
                    icon: const Icon(Icons.bookmarks_outlined),
                  ),
                  IconButton(
                    tooltip: '축소',
                    onPressed: _controller.zoomDown,
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: '확대',
                    onPressed: _controller.zoomUp,
                    icon: const Icon(Icons.zoom_in),
                  ),
                  IconButton(
                    tooltip: '페이지 이동',
                    onPressed: _pageCount == 0 ? null : _goToPage,
                    icon: const Icon(Icons.find_in_page_outlined),
                  ),
                  IconButton(
                    tooltip: '인쇄',
                    onPressed: _printDocument,
                    icon: const Icon(Icons.print_outlined),
                  ),
                  PopupMenuButton<_ViewMode>(
                    tooltip: '보기 방식',
                    initialValue: _viewMode,
                    onSelected: (mode) => setState(() => _viewMode = mode),
                    icon: const Icon(Icons.view_carousel_outlined),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ViewMode.scroll,
                        child: Text('세로 스크롤'),
                      ),
                      PopupMenuItem(
                        value: _ViewMode.horizontal,
                        child: Text('가로 스크롤'),
                      ),
                      PopupMenuItem(
                        value: _ViewMode.facing,
                        child: Text('두 페이지 보기'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: '문서 전체 OCR',
                    onPressed: _busy ? null : _runOcr,
                    icon: const Icon(Icons.document_scanner_outlined),
                  ),
                  PopupMenuButton<_ExportFormat>(
                    tooltip: '다른 형식으로 저장',
                    onSelected: _export,
                    icon: const Icon(Icons.save_alt_outlined),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ExportFormat.pdf,
                        child: Text('PDF로 저장'),
                      ),
                      PopupMenuItem(
                        value: _ExportFormat.png,
                        child: Text('PNG로 저장'),
                      ),
                      PopupMenuItem(
                        value: _ExportFormat.jpg,
                        child: Text('JPG로 저장'),
                      ),
                    ],
                  ),
                  PopupMenuButton<_ReaderAction>(
                    tooltip: '기능 메뉴',
                    onSelected: _selectAction,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ReaderAction.bookmark,
                        child: ListTile(
                          leading: Icon(Icons.bookmark_border),
                          title: Text('이 페이지 책갈피'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ReaderAction.bookmarks,
                        child: ListTile(
                          leading: Icon(Icons.bookmarks_outlined),
                          title: Text('책갈피 목록'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ReaderAction.zoomIn,
                        child: ListTile(
                          leading: Icon(Icons.zoom_in),
                          title: Text('확대'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ReaderAction.zoomOut,
                        child: ListTile(
                          leading: Icon(Icons.zoom_out),
                          title: Text('축소'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ReaderAction.goToPage,
                        child: ListTile(
                          leading: Icon(Icons.find_in_page_outlined),
                          title: Text('페이지 이동'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ReaderAction.clearMarks,
                        child: ListTile(
                          leading: Icon(Icons.layers_clear_outlined),
                          title: Text('이 문서의 표시 지우기'),
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: _ReaderAction.help,
                        child: ListTile(
                          leading: Icon(Icons.help_outline),
                          title: Text('사용 방법'),
                        ),
                      ),
                    ],
                  ),
                ],
        ),
        body: Stack(
          children: [
            if (_pdfData == null)
              _buildPdfLoadingState()
            else
              PdfViewer.data(
                _pdfData!,
                sourceName: '${widget.path}:${_pdfData!.length}',
                key: ValueKey(_viewMode),
                controller: _controller,
                params: PdfViewerParams(
                  errorBannerBuilder: (context, error, _, _) {
                    debugPrint('PDF 열기 실패: $error');
                    return Center(
                      child: Card(
                        margin: const EdgeInsets.all(32),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'PDF를 열 수 없습니다',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '파일이 이동되었거나 접근 권한이 변경되었을 수 있습니다. '
                                '문서함으로 돌아가 PDF를 다시 선택해 주세요.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: () =>
                                    Navigator.of(context).pop(_currentPage),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('문서함으로 돌아가기'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  // pdfrx의 데스크톱 컨텍스트 메뉴는 일부 환경에서 선택 좌표가
                  // 비어 있을 때 예외를 냈다. 동작이 확실한 화면 하단 도구막대를 사용한다.
                  buildContextMenu: (_, _) => null,
                  textSelectionParams: PdfTextSelectionParams(
                    showContextMenuAutomatically: false,
                    onTextSelectionChange: (selection) {
                      if (mounted &&
                          _hasSelectedText != selection.hasSelectedText) {
                        setState(
                          () => _hasSelectedText = selection.hasSelectedText,
                        );
                      }
                    },
                  ),
                  onViewerReady: (document, _) async {
                    if (!mounted) return;
                    final pageCount = document.pages.length;
                    _searcher?.dispose();
                    final searcher = PdfTextSearcher(_controller);
                    setState(() {
                      _searcher = searcher;
                      _searching = false;
                      _pageCount = pageCount;
                      _bookmarks.removeWhere((page) => page > pageCount);
                    });
                    if (pageCount == 0) {
                      _showMessage('페이지가 없는 PDF 문서입니다.');
                      return;
                    }
                    final initial = widget.initialPage.clamp(1, pageCount);
                    if (initial > 1) {
                      await _controller.goToPage(pageNumber: initial);
                    }
                  },
                  onPageChanged: (page) {
                    if (mounted && page != null) {
                      setState(() => _currentPage = page);
                    }
                  },
                  pagePaintCallbacks: [
                    _paintMarks,
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
                            final layouts = <Rect>[];
                            var x = params.margin;
                            for (final page in pages) {
                              layouts.add(
                                Rect.fromLTWH(
                                  x,
                                  params.margin + (height - page.height) / 2,
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
                          final layouts = <Rect>[];
                          var y = params.margin;
                          for (var index = 0; index < pages.length; index++) {
                            final page = pages[index];
                            final position = index + 1;
                            final isLeft = position.isEven;
                            final otherIndex = isLeft ? index - 1 : index + 1;
                            final rowHeight =
                                otherIndex >= 0 && otherIndex < pages.length
                                ? math.max(
                                    page.height,
                                    pages[otherIndex].height,
                                  )
                                : page.height;
                            layouts.add(
                              Rect.fromLTWH(
                                isLeft
                                    ? params.margin * 2 + width
                                    : params.margin + width - page.width,
                                y + (rowHeight - page.height) / 2,
                                page.width,
                                page.height,
                              ),
                            );
                            if (isLeft || index == pages.length - 1) {
                              y += rowHeight + params.margin;
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
            if (_pageCount > 0)
              Positioned(
                right: 16,
                bottom: 16,
                child: Chip(label: Text('$_currentPage / $_pageCount')),
              ),
            if (_hasSelectedText)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await _controller.textSelectionDelegate
                                  .copyTextSelection();
                              await _controller.textSelectionDelegate
                                  .clearTextSelection();
                              if (mounted) {
                                setState(() => _hasSelectedText = false);
                              }
                            },
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('복사'),
                          ),
                          TextButton(
                            onPressed: () => _applyMark(_MarkType.highlight),
                            child: const Text('형광펜'),
                          ),
                          TextButton(
                            onPressed: () => _applyMark(_MarkType.underline),
                            child: const Text('밑줄'),
                          ),
                          TextButton(
                            onPressed: () => _applyMark(_MarkType.strike),
                            child: const Text('취소선'),
                          ),
                          TextButton(
                            onPressed: () => _applyMark(_MarkType.bold),
                            child: const Text('강조'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withAlpha(55),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(_busyMessage),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
