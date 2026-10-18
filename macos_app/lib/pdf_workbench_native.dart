import 'dart:async';
import 'dart:io';

import 'pdfcraft_models.dart';

Future<PdfcraftResult?> openPdfWorkbench(PdfcraftSource source) async {
  final helper = File(
    '${File(Platform.resolvedExecutable).parent.path}/cy-pdf-workbench',
  );
  if (!await helper.exists()) {
    throw const FormatException('PDF 작업실 모듈이 없습니다. 최신 CY뷰어를 설치해 주세요.');
  }
  final directory = await Directory.systemTemp.createTemp('cy-workbench-');
  try {
    // 암호나 원본 경로는 명령행에 전달하지 않는다. 보호 문서는 작업실에서 다시 묻는다.
    final name = source.name.replaceAll(RegExp(r'[^a-zA-Z0-9가-힣._ -]'), '_');
    final path = '${directory.path}/${name.isEmpty ? 'document.pdf' : name}';
    await File(path).writeAsBytes(source.bytes, flush: true);
    final process = await Process.start(helper.path, [path]);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((_) async {
        await directory.delete(recursive: true);
      }),
    );
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
  return null;
}
