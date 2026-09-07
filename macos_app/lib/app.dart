import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_reader.dart';

class PersonalPdfApp extends StatelessWidget {
  const PersonalPdfApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CY뷰어',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('ko'), Locale('en')],
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff60a5fa),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    themeMode: ThemeMode.system,
    home: const LibraryPage(),
  );
}

class SavedPdf {
  const SavedPdf({
    required this.path,
    required this.name,
    required this.openedAt,
    this.favorite = false,
    this.lastPage = 1,
  });
  final String path;
  final String name;
  final DateTime openedAt;
  final bool favorite;
  final int lastPage;
  SavedPdf copyWith({DateTime? openedAt, bool? favorite, int? lastPage}) =>
      SavedPdf(
        path: path,
        name: name,
        openedAt: openedAt ?? this.openedAt,
        favorite: favorite ?? this.favorite,
        lastPage: lastPage ?? this.lastPage,
      );
  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'openedAt': openedAt.toIso8601String(),
    'favorite': favorite,
    'lastPage': lastPage,
  };
  factory SavedPdf.fromJson(Map<String, dynamic> map) => SavedPdf(
    path: map['path'] as String,
    name: map['name'] as String,
    openedAt: DateTime.parse(map['openedAt'] as String),
    favorite: map['favorite'] as bool? ?? false,
    lastPage: map['lastPage'] as int? ?? 1,
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _key = 'personal_pdf_library_v1';
  List<SavedPdf> _items = [];
  bool _loading = true;
  bool _favoritesOnly = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw != null) {
      _items = (jsonDecode(raw) as List)
          .map((e) => SavedPdf.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    _items.removeWhere((item) => !File(item.path).existsSync());
    _items.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    await _save();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async => (await SharedPreferences.getInstance())
      .setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final file = files.isEmpty ? null : files.single;
    if (file?.path == null) return;
    await _addAndOpen(file!.path!, file.name);
  }

  Future<void> _addAndOpen(String path, String name) async {
    if (!path.toLowerCase().endsWith('.pdf')) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PDF 파일만 열 수 있습니다.')));
      }
      return;
    }
    if (!File(path).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('파일을 찾을 수 없습니다.')));
      }
      return;
    }
    final oldIndex = _items.indexWhere((e) => e.path == path);
    final favorite = oldIndex < 0 ? false : _items[oldIndex].favorite;
    final lastPage = oldIndex < 0 ? 1 : _items[oldIndex].lastPage;
    _items.removeWhere((e) => e.path == path);
    final item = SavedPdf(
      path: path,
      name: name,
      openedAt: DateTime.now(),
      favorite: favorite,
      lastPage: lastPage,
    );
    _items.insert(0, item);
    await _save();
    if (mounted) {
      setState(() {});
      await _open(item);
    }
  }

  Future<void> _open(SavedPdf item) async {
    if (!File(item.path).existsSync()) {
      _items.removeWhere((e) => e.path == item.path);
      await _save();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('파일이 이동되었거나 삭제되었습니다.')));
      }
      return;
    }
    _items.removeWhere((e) => e.path == item.path);
    final refreshed = item.copyWith(openedAt: DateTime.now());
    _items.insert(0, refreshed);
    await _save();
    if (!mounted) return;
    final lastPage = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AdvancedPdfReaderPage(
          path: refreshed.path,
          name: refreshed.name,
          initialPage: refreshed.lastPage,
        ),
      ),
    );
    if (lastPage != null) {
      final index = _items.indexWhere((e) => e.path == refreshed.path);
      if (index >= 0) {
        _items[index] = _items[index].copyWith(lastPage: lastPage);
      }
      await _save();
    }
    if (mounted) setState(() {});
  }

  Future<void> _favorite(SavedPdf item) async {
    final index = _items.indexWhere((e) => e.path == item.path);
    _items[index] = item.copyWith(favorite: !item.favorite);
    await _save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final shown = _favoritesOnly
        ? _items.where((e) => e.favorite).toList()
        : _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CY뷰어'),
        actions: [
          IconButton(
            tooltip: '즐겨찾기',
            onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
            icon: Icon(_favoritesOnly ? Icons.star : Icons.star_border),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pick,
        icon: const Icon(Icons.folder_open),
        label: const Text('PDF 열기'),
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) async {
          setState(() => _dragging = false);
          final pdfs = detail.files
              .where((file) => file.path.toLowerCase().endsWith('.pdf'))
              .toList();
          if (pdfs.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PDF 파일을 끌어놓아 주세요.')),
              );
            }
            return;
          }
          final file = pdfs.first;
          await _addAndOpen(file.path, file.name);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _favoritesOnly
                              ? Icons.star_outline
                              : Icons.picture_as_pdf_outlined,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _favoritesOnly ? '즐겨찾는 문서가 없습니다' : '첫 PDF를 열어 보세요',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text('문서 목록은 이 기기에만 저장됩니다.'),
                        if (!_favoritesOnly)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: FilledButton(
                              onPressed: _pick,
                              child: const Text('PDF 선택'),
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final item = shown[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.picture_as_pdf_outlined),
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('최근 열람: ${_date(item.openedAt)}'),
                          onTap: () => _open(item),
                          trailing: IconButton(
                            onPressed: () => _favorite(item),
                            icon: Icon(
                              item.favorite ? Icons.star : Icons.star_border,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            if (_dragging)
              ColoredBox(
                color: Theme.of(context).colorScheme.primary.withAlpha(28),
                child: Center(
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 28,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_download_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text('여기에 PDF를 놓아 열기'),
                        ],
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

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key, required this.item});
  final SavedPdf item;
  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  final _controller = PdfViewerController();
  int _pages = 0;
  Future<void> _pageDialog() async {
    final input = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('페이지로 이동'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1~$_pages'),
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
    if (page != null && page >= 1 && page <= _pages) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.item.name, overflow: TextOverflow.ellipsis),
      actions: [
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
          onPressed: _pages == 0 ? null : _pageDialog,
          icon: const Icon(Icons.find_in_page_outlined),
        ),
      ],
    ),
    body: PdfViewer.file(
      widget.item.path,
      controller: _controller,
      params: PdfViewerParams(
        onViewerReady: (document, _) =>
            setState(() => _pages = document.pages.length),
      ),
    ),
  );
}

String _date(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
