import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:archive/archive.dart';
import 'package:cy_viewer/pdfcraft_service.dart';

void main() {
  test(
    '실제 Dart 서비스에서 PdfCraft 암호 PDF·ZIP을 재열기한다',
    () async {
      Pdfrx.pdfiumModulePath = Platform.environment['CY_PDFIUM_TEST_LIBRARY'];
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
      await pdfrxFlutterInitialize();
      final service = PdfcraftService(
        executable:
            '${Directory.current.parent.path}/build/pdfcraft/cy-pdfcraft${Platform.isWindows ? '.exe' : ''}',
      );
      final source = PdfcraftSource(
        'fixture.pdf',
        await File('test/fixtures/print-pages.pdf').readAsBytes(),
      );
      final info = await service.inspect(source, '');
      expect(info['pages'], 4);
      final edited = await service.edit(
        [source],
        {
          'page_plan': [
            {'index': 3, 'rotation': 90},
            {'index': null},
            {'index': 0},
          ],
          'metadata': {'Title': '한글 제목'},
          'bookmarks': [
            {'action': 'add', 'title': '첫 페이지', 'page': 1},
          ],
          'new_password': '암호-123',
        },
        '',
      );
      expect(edited.pages, 3);
      final protected = PdfcraftSource('protected.pdf', edited.bytes);
      expect((await service.inspect(protected, '암호-123'))['encrypted'], true);
      final split = await service.edit(
        [protected],
        {'split_every': 2, 'remove_password': true},
        '암호-123',
      );
      expect(split.extension, 'zip');
      final archive = ZipDecoder().decodeBytes(split.bytes);
      expect(archive.files.length, 2);
      for (final file in archive.files) {
        final doc = await PdfDocument.openData(file.content);
        expect(doc.pages.isNotEmpty, true);
        await doc.dispose();
      }
    },
    skip: Platform.environment['CY_PDFIUM_TEST_LIBRARY'] == null
        ? '실제 PDFium 라이브러리 경로와 빌드된 cy-pdfcraft가 필요합니다.'
        : false,
  );
}
