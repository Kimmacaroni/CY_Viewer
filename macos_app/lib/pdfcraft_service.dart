import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:archive/archive.dart';

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

class PdfcraftService implements PdfcraftBackend {
  const PdfcraftService({this.executable});
  final String? executable;
  static Future<Uint8List> compose(
    List<PdfcraftSource> sources,
    String pages, {
    String? executable,
  }) async => (await PdfcraftService(
    executable: executable,
  ).edit(sources, {'pages': pages}, '')).bytes;
  @override
  Future<Map<String, dynamic>> inspect(
    PdfcraftSource source,
    String password,
  ) async => (await _invoke([source], {'inspect': true}, password)).$1;
  @override
  Future<PdfcraftResult> edit(
    List<PdfcraftSource> sources,
    Map<String, Object?> options,
    String password,
  ) async {
    final (report, outputs) = await _invoke(sources, options, password);
    if (outputs.isEmpty) throw const FormatException('결과 PDF가 없습니다.');
    if (options['split_every'] != null) {
      final archive = Archive();
      for (var i = 0; i < outputs.length; i++) {
        final bytes = outputs[i];
        archive.addFile(
          ArchiveFile(
            'part-${(i + 1).toString().padLeft(3, '0')}.pdf',
            bytes.length,
            bytes,
          ),
        );
      }
      return PdfcraftResult(
        Uint8List.fromList(ZipEncoder().encode(archive)),
        'zip',
        report['pages'] as int,
        outputs.length,
      );
    }
    return PdfcraftResult(outputs.single, 'pdf', report['pages'] as int, 1);
  }

  Future<(Map<String, dynamic>, List<Uint8List>)> _invoke(
    List<PdfcraftSource> sources,
    Map<String, Object?> options,
    String password,
  ) async {
    if (sources.isEmpty || sources.length > 20) {
      throw const FormatException('PDF는 1개부터 20개까지 선택하세요.');
    }
    var total = 0;
    for (final source in sources) {
      total += source.bytes.length;
      if (source.bytes.length > 256 * 1024 * 1024 || total > 512 * 1024 * 1024) {
        throw const FormatException('한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.');
      }
    }
    final helper =
        executable ??
        '${File(Platform.resolvedExecutable).parent.path}/cy-pdfcraft';
    if (!await File(helper).exists()) {
      throw const FormatException('페이지 처리 모듈이 없습니다. 최신 CY뷰어 설치 파일로 다시 설치하세요.');
    }
    final directory = await Directory.systemTemp.createTemp('cy-tools-');
    try {
      final request = Map<String, Object?>.from(options);
      final pages = request.remove('pages');
      final inputs = <Map<String, Object?>>[];
      for (var i = 0; i < sources.length; i++) {
        final path = '${directory.path}/source-$i.pdf';
        await File(path).writeAsBytes(sources[i].bytes, flush: true);
        inputs.add({
          'path': path,
          'title': sources[i].name,
          'pages': i == 0 ? pages : null,
          'password': i == 0 && password.isNotEmpty
              ? password
              : sources[i].password,
        });
      }
      request.addAll({
        'sources': inputs,
        'output': '${directory.path}/result.pdf',
      });
      final process = await Process.start(helper, const []);
      final stdout = process.stdout.transform(utf8.decoder).join(),
          stderr = process.stderr.transform(utf8.decoder).join();
      process.stdin.write(jsonEncode(request));
      await process.stdin.close();
      int code;
      try {
        code = await process.exitCode.timeout(const Duration(seconds: 180));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        throw const FormatException('PDF 처리 시간이 초과됐습니다. 원본은 변경하지 않았습니다.');
      }
      final error = await stderr, reportText = await stdout;
      if (code != 0) throw FormatException(error.trim());
      final report = jsonDecode(reportText) as Map<String, dynamic>;
      final outputs = <Uint8List>[];
      for (final info in (report['files'] as List? ?? const [])) {
        final file = File(info['path'] as String);
        if (await file.parent.resolveSymbolicLinks() !=
            await directory.resolveSymbolicLinks()) {
          throw const FormatException('결과 파일 경로가 올바르지 않습니다.');
        }
        final bytes = await file.readAsBytes();
        var supplied = false;
        final document = await PdfDocument.openData(
          bytes,
          passwordProvider: () {
            if (supplied) return null;
            supplied = true;
            return options['new_password'] as String?;
          },
        );
        try {
          if (document.pages.length != info['pages'] || document.pages.isEmpty) {
            throw const FormatException('결과 PDF의 페이지 수가 일치하지 않습니다.');
          }
        } finally {
          await document.dispose();
        }
        outputs.add(bytes);
      }
      return (report, outputs);
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
