import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdfcraft_models.dart';

@JS('cyPdfcraftRun')
external JSPromise<JSObject> _run(
  JSString request,
  JSArray<JSUint8Array> sources,
);

class BrowserPdfcraftService implements PdfcraftBackend {
  const BrowserPdfcraftService();
  Future<Map<String, dynamic>> _invoke(
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
      if (source.bytes.length > 256 * 1024 * 1024 ||
          total > 512 * 1024 * 1024) {
        throw const FormatException('한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.');
      }
    }
    final request = Map<String, Object?>.from(options);
    final pages = request.remove('pages');
    request.addAll({
      'sources': [
        for (var i = 0; i < sources.length; i++)
          {
            'path': 'source-$i.pdf',
            'title': sources[i].name,
            'pages': i == 0 ? pages : null,
            'password': i == 0 && password.isNotEmpty
                ? password
                : sources[i].password,
          },
      ],
      'output': 'result.pdf',
    });
    try {
      final result = await _run(
        jsonEncode(request).toJS,
        sources.map((s) => s.bytes.toJS).toList().toJS,
      ).toDart;
      final value = (result.dartify() as Map).cast<String, dynamic>();
      if (value['error'] != null) {
        throw FormatException(value['error'] as String);
      }
      return value;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException(error.toString());
    }
  }

  @override
  Future<Map<String, dynamic>> inspect(
    PdfcraftSource source,
    String password,
  ) async =>
      ((await _invoke([source], {'inspect': true}, password))['report'] as Map)
          .cast<String, dynamic>();
  @override
  Future<PdfcraftResult> edit(
    List<PdfcraftSource> sources,
    Map<String, Object?> options,
    String password,
  ) async {
    final result = await _invoke(sources, options, password);
    final report = (result['report'] as Map).cast<String, dynamic>();
    final outputs = (result['files'] as List)
        .map(
          (f) =>
              f is Uint8List ? f : Uint8List.fromList((f as List).cast<int>()),
        )
        .toList();
    if (outputs.isEmpty) throw const FormatException('결과 PDF가 없습니다.');
    final descriptions = report['files'] as List;
    if (descriptions.length != outputs.length) {
      throw const FormatException('결과 PDF의 페이지 수가 일치하지 않습니다.');
    }
    for (var i = 0; i < outputs.length; i++) {
      var supplied = false;
      final document = await PdfDocument.openData(
        outputs[i],
        passwordProvider: () {
          if (supplied) return null;
          supplied = true;
          return options['new_password'] as String?;
        },
      );
      try {
        if (document.pages.isEmpty ||
            document.pages.length != descriptions[i]['pages']) {
          throw const FormatException('결과 PDF의 페이지 수가 일치하지 않습니다.');
        }
      } finally {
        await document.dispose();
      }
    }
    if (options['split_every'] != null) {
      final archive = Archive();
      for (var i = 0; i < outputs.length; i++) {
        archive.addFile(
          ArchiveFile(
            'part-${(i + 1).toString().padLeft(3, '0')}.pdf',
            outputs[i].length,
            outputs[i],
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
}

PdfcraftBackend createPdfcraftBackend(String? executable) =>
    const BrowserPdfcraftService();
