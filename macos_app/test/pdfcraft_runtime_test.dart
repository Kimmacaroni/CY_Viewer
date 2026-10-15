import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:archive/archive.dart';
import 'package:cy_viewer/pdfcraft_service.dart';
import 'package:cy_viewer/advanced_reader.dart';
import 'package:cy_viewer/pdf_password_dialog.dart';
import 'package:cy_viewer/pdfcraft_dialog.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final protected = PdfcraftSource(
        'protected.pdf',
        edited.bytes,
        password: '암호-123',
      );
      expect((await service.inspect(protected, ''))['owner'], true);
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
  testWidgets('암호 PDF를 실제 리더에서 잘못된 암호 후 다시 입력해 연다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late Directory directory;
    late File file;
    await tester.runAsync(() async {
      Pdfrx.pdfiumModulePath = Platform.environment['CY_PDFIUM_TEST_LIBRARY'];
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
      await pdfrxFlutterInitialize();
      final service = PdfcraftService(
        executable:
            '${Directory.current.parent.path}/build/pdfcraft/cy-pdfcraft${Platform.isWindows ? '.exe' : ''}',
      );
      final result = await service.edit(
        [
          PdfcraftSource(
            'fixture.pdf',
            await File('test/fixtures/print-pages.pdf').readAsBytes(),
          ),
        ],
        {'new_password': 'reader-pass'},
        '',
      );
      directory = await Directory.systemTemp.createTemp('cy-reader-password-');
      file = await File('${directory.path}/encrypted.pdf')
          .writeAsBytes(result.bytes);
    });
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AdvancedPdfReaderPage(
          path: file.path,
          name: '잠긴 문서.pdf',
          initialPage: 1,
          onOpened: () => opened = true,
        ),
      ),
    );
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(condition(), true);
    }

    await waitFor(() => find.byType(PdfPasswordDialog).evaluate().isNotEmpty);
    await tester.enterText(
      find.descendant(
        of: find.byType(PdfPasswordDialog),
        matching: find.byType(TextField),
      ),
      'wrong',
    );
    await tester.pump();
    await tester.tap(find.text('문서 열기'));
    await waitFor(
      () => find
          .byType(PdfPasswordDialog)
          .evaluate()
          .any((e) => (e.widget as PdfPasswordDialog).retry),
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(PdfPasswordDialog),
        matching: find.byType(TextField),
      ),
      'reader-pass',
    );
    await tester.pump();
    await tester.tap(find.text('문서 열기'));
    await waitFor(() => opened);
    expect(find.byType(PdfPasswordDialog), findsNothing);
    if (Platform.isMacOS) {
      await tester.tap(
        find.widgetWithIcon(TextButton, Icons.library_books_outlined),
      );
      await tester.pumpAndSettle();
      // 실제 리더가 연 암호를 도구의 입력 사본에도 연결한다.
      final dialog = tester.widget<PdfcraftDialog>(find.byType(PdfcraftDialog));
      expect(dialog.source.password, 'reader-pass');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() => directory.delete(recursive: true));
    expect(tester.takeException(), isNull);
  }, skip: Platform.environment['CY_PDFIUM_TEST_LIBRARY'] == null);
}
