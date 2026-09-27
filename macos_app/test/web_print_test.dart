import 'dart:io';

import 'package:cy_viewer/web_print.dart';
import 'package:cy_viewer/cy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('범위 파싱: 단일·여러 범위·중복 제거·원문 순서', () {
    expect(parsePrintPages('2-5, 8', 16), [2, 3, 4, 5, 8]);
    expect(parsePrintPages('8, 2–4, 3, 1', 16), [1, 2, 3, 4, 8]);
    for (final value in [
      '',
      '0',
      '17',
      '5-2',
      '1-',
      'a',
      '1,,2',
      '1.5',
      '-2',
    ]) {
      expect(() => parsePrintPages(value, 16), throwsFormatException);
    }
  });
  testWidgets('범위 대화상자: 16쪽 전체·현재·직접 범위와 오류', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await CyLanguage.instance.select('ko');
    List<int>? selected;
    await tester.pumpWidget(
      CyLanguageScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await choosePrintPages(context, 16, 2);
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> start() async {
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
    }

    await start();
    await tester.tap(find.text('인쇄용 PDF 준비'));
    await tester.pumpAndSettle();
    expect(selected, List.generate(16, (i) => i + 1));
    await start();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 페이지 (2)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('인쇄용 PDF 준비'));
    await tester.pumpAndSettle();
    expect(selected, [2]);
    await start();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('페이지 직접 지정').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '17');
    await tester.tap(find.text('인쇄용 PDF 준비'));
    await tester.pumpAndSettle();
    expect(find.text('1~16 사이의 페이지를 입력하세요. 예: 2-5, 8'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2-5, 8');
    await tester.tap(find.text('인쇄용 PDF 준비'));
    await tester.pumpAndSettle();
    expect(selected, [2, 3, 4, 5, 8]);
    expect(tester.takeException(), isNull);
  });
  test(
    '실제 PDF에서 페이지 추출·원문 유지·전체 페이지 수 보존',
    () async {
      Pdfrx.pdfiumModulePath = Platform.environment['CY_PDFIUM_TEST_LIBRARY'];
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
      await pdfrxFlutterInitialize();
      final source = await PdfDocument.openData(
        File('test/fixtures/print-pages.pdf').readAsBytesSync(),
        sourceName: 'print-source',
      );
      try {
        final bytes = await createPrintPdf(source, [2, 4]);
        final subset = await PdfDocument.openData(
          bytes,
          sourceName: 'print-subset',
        );
        try {
          expect(subset.pages.length, 2);
          expect(
            (await subset.pages[0].loadText())?.fullText,
            contains('Page 2'),
          );
          expect(
            (await subset.pages[1].loadText())?.fullText,
            contains('Page 4'),
          );
          expect(source.pages.length, 4);
        } finally {
          await subset.dispose();
        }
        final all = await PdfDocument.openData(
          await createPrintPdf(source, [1, 2, 3, 4]),
          sourceName: 'print-all',
        );
        try {
          expect(all.pages.length, 4);
        } finally {
          await all.dispose();
        }
      } finally {
        await source.dispose();
      }
    },
    skip: Platform.environment['CY_PDFIUM_TEST_LIBRARY'] == null
        ? '실제 PDF 검증은 CY_PDFIUM_TEST_LIBRARY에 PDFium 라이브러리 경로를 지정해 실행한다.'
        : false,
  );
}
