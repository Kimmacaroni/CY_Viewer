import 'dart:typed_data';

List<int> parsePdfcraftPages(String text, int count) {
  if (text.trim().isEmpty || text.length > 100000) {
    throw const FormatException('페이지 범위를 입력하세요.');
  }
  final pages = <int>[];
  for (final part in text.split(',')) {
    final ends = part.trim().split('-');
    if (ends.length > 2 ||
        ends.any((s) => !RegExp(r'^[0-9]+$').hasMatch(s.trim()))) {
      throw const FormatException('페이지 범위는 1-3, 5 형식으로 입력하세요.');
    }
    final first = int.tryParse(ends.first.trim()),
        last = int.tryParse(ends.last.trim());
    if (first == null ||
        last == null ||
        first < 1 ||
        last < first ||
        last > count) {
      throw FormatException('페이지는 1부터 $count까지 선택하세요. 순서는 3, 1, 2처럼 지정하세요.');
    }
    for (var n = first; n <= last; n++) {
      pages.add(n);
      if (pages.length > 100000) {
        throw const FormatException('한 번에 선택할 수 있는 페이지가 너무 많습니다.');
      }
    }
  }
  if (pages.toSet().length != pages.length) {
    throw const FormatException('같은 페이지를 두 번 선택할 수 없습니다.');
  }
  return pages;
}

class PdfcraftSource {
  const PdfcraftSource(
    this.name,
    this.bytes, {
    this.originalPath,
    this.password,
  });
  final String name;
  final Uint8List bytes;
  final String? originalPath, password;
}

class PdfcraftResult {
  const PdfcraftResult(this.bytes, this.extension, this.pages, this.files);
  final Uint8List bytes;
  final String extension;
  final int pages, files;
}

abstract class PdfcraftBackend {
  Future<Map<String, dynamic>> inspect(PdfcraftSource source, String password);
  Future<PdfcraftResult> edit(
    List<PdfcraftSource> sources,
    Map<String, Object?> options,
    String password,
  );
}
