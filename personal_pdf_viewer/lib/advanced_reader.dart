import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _ReaderAction { bookmark, bookmarks, zoomOut, zoomIn, goToPage, help }

enum _MarkType { highlight, underline, strike, bold }

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
  final _controller = PdfViewerController();
  final _searchInput = TextEditingController();
  late final PdfTextSearcher _searcher = PdfTextSearcher(_controller);
  int _pageCount = 0;
  int _currentPage = 1;
  List<int> _bookmarks = [];
  bool _searching = false;
  final List<_TextMark> _marks = [];

  String get _bookmarkKey =>
      'pdf_bookmarks_${base64Url.encode(utf8.encode(widget.path))}';

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final values =
        (await SharedPreferences.getInstance()).getStringList(_bookmarkKey) ??
        [];
    if (mounted) {
      setState(
        () =>
            _bookmarks = values.map(int.tryParse).whereType<int>().toList()
              ..sort(),
      );
    }
  }

  Future<void> _saveBookmarks() async => (await SharedPreferences.getInstance())
      .setStringList(_bookmarkKey, _bookmarks.map((e) => '$e').toList());

  Future<void> _toggleBookmark() async {
    setState(() {
      if (_bookmarks.contains(_currentPage)) {
        _bookmarks.remove(_currentPage);
      } else {
        _bookmarks.add(_currentPage);
        _bookmarks.sort();
      }
    });
    await _saveBookmarks();
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
    if (page != null && page >= 1 && page <= _pageCount) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  void _startSearch(String text) {
    _searcher.startTextSearch(text, searchImmediately: true);
    setState(() {});
  }

  Future<void> _applyMark(
    PdfViewerContextMenuBuilderParams params,
    _MarkType type,
  ) async {
    final ranges = await params.textSelectionDelegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    setState(
      () => _marks.addAll(ranges.map((range) => _TextMark(range, type))),
    );
    await params.textSelectionDelegate.clearTextSelection();
    params.dismissContextMenu();
    _controller.invalidate();
  }

  Widget _markButton(String label, Color color, VoidCallback onPressed) =>
      TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: color),
        child: Text(label),
      );

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
      case _ReaderAction.help:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('CY뷰어 사용 방법'),
            content: const Text(
              '• 돋보기: 문서 텍스트 검색\n• 기능 메뉴: 책갈피, 확대/축소, 페이지 이동\n• 마우스 휠: 문서 스크롤\n• Ctrl + 마우스 휠: 확대/축소\n• 우클릭 또는 길게 누르기: 텍스트 선택과 복사',
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

  @override
  void dispose() {
    _searchInput.dispose();
    _searcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_currentPage);
    },
    child: Scaffold(
      appBar: AppBar(
        title: _searching
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  Text(widget.name, overflow: TextOverflow.ellipsis),
                ],
              ),
        actions: _searching
            ? [
                AnimatedBuilder(
                  animation: _searcher,
                  builder: (context, child) => Text(
                    '${_searcher.currentIndex == null ? 0 : _searcher.currentIndex! + 1}/${_searcher.matches.length}',
                  ),
                ),
                IconButton(
                  tooltip: '이전 결과',
                  onPressed: _searcher.goToPrevMatch,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: '다음 결과',
                  onPressed: _searcher.goToNextMatch,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: '검색 닫기',
                  onPressed: () {
                    _searcher.resetTextSearch();
                    _searchInput.clear();
                    setState(() => _searching = false);
                  },
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                IconButton(
                  tooltip: '검색',
                  onPressed: () => setState(() => _searching = true),
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
          PdfViewer.file(
            widget.path,
            controller: _controller,
            params: PdfViewerParams(
              buildContextMenu: (context, params) {
                final canCopy =
                    params.isTextSelectionEnabled &&
                    params.textSelectionDelegate.isCopyAllowed &&
                    params.textSelectionDelegate.hasSelectedText;
                final canSelectAll =
                    params.isTextSelectionEnabled &&
                    !params.textSelectionDelegate.isSelectingAllText;
                if (!canCopy && !canSelectAll) return null;
                return Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canCopy)
                          TextButton.icon(
                            onPressed: () {
                              params.textSelectionDelegate.copyTextSelection();
                              params.dismissContextMenu();
                            },
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('복사'),
                          ),
                        _markButton(
                          '형광펜',
                          Colors.amber,
                          () => _applyMark(params, _MarkType.highlight),
                        ),
                        _markButton(
                          '밑줄',
                          Colors.blue,
                          () => _applyMark(params, _MarkType.underline),
                        ),
                        _markButton(
                          '취소선',
                          Colors.red,
                          () => _applyMark(params, _MarkType.strike),
                        ),
                        _markButton(
                          '굵게',
                          Colors.black,
                          () => _applyMark(params, _MarkType.bold),
                        ),
                        if (canSelectAll)
                          TextButton(
                            onPressed: () =>
                                params.textSelectionDelegate.selectAllText(),
                            child: const Text('전체 선택'),
                          ),
                      ],
                    ),
                  ),
                );
              },
              onViewerReady: (document, _) async {
                setState(() => _pageCount = document.pages.length);
                final initial = widget.initialPage.clamp(
                  1,
                  document.pages.length,
                );
                if (initial > 1) {
                  await _controller.goToPage(pageNumber: initial);
                }
              },
              onPageChanged: (page) {
                if (page != null) {
                  setState(() => _currentPage = page);
                }
              },
              pagePaintCallbacks: [
                _paintMarks,
                _searcher.pageTextMatchPaintCallback,
              ],
            ),
          ),
          if (_pageCount > 0)
            Positioned(
              right: 16,
              bottom: 16,
              child: Chip(label: Text('$_currentPage / $_pageCount')),
            ),
        ],
      ),
    ),
  );
}
