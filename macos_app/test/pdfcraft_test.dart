import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cy_viewer/pdfcraft_dialog.dart';
import 'package:cy_viewer/pdfcraft_service.dart';

void main() {
  test('페이지 순서와 범위 밖·중복 보호', () {
    expect(parsePdfcraftPages('3, 1-2', 4), [3, 1, 2]);
    for (final value in ['', '0', '5', '1,1', '3-1', '1-2-3', '1,', 'x', '９']) {
      expect(() => parsePdfcraftPages(value, 4), throwsFormatException);
    }
  });
  testWidgets('좁은 화면과 큰 글자에서 페이지 구성·저장 경로를 유지한다', (tester) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: PdfcraftDialog(
            source: PdfcraftSource('실제 파일 이름.pdf', Uint8List(0)),
            pageCount: 4,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
