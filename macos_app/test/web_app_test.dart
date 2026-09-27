import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cy_viewer/web_pdf_picker.dart';
import 'package:cy_viewer/web_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('웹앱 첫 화면이 한국어로 표시된다', (tester) async {
    await tester.pumpWidget(const CyViewerWebApp());
    await tester.pumpAndSettle();

    expect(find.text('CY뷰어'), findsOneWidget);
    expect(find.text('어떤 문서를 읽을까요?'), findsOneWidget);
    expect(find.text('PDF 열기'), findsOneWidget);
  });
  testWidgets('최근 사본 저장이 멈춰도 문서에서 돌아오면 파일 입력이 새로 활성화된다', (tester) async {
    final pendingSave = Completer<void>();
    await tester.pumpWidget(
      CyViewerWebApp(saveRecent: (_, _) => pendingSave.future),
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<WebPdfPickRegion>(
      find.byType(WebPdfPickRegion),
    );
    picker.onPicked(
      PickedWebPdf(
        name: 'test.pdf',
        bytes: Uint8List.fromList([37, 80, 68, 70]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    // 문서를 읽는 동안 이전 HTML 파일 입력은 트리에서 제거된다.
    expect(find.byType(WebPdfPickRegion, skipOffstage: false), findsNothing);
    final reader = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_WebReaderPage',
    );
    final dynamic page = tester.widget(reader);
    page.onOpened();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final restored = tester.widget<WebPdfPickRegion>(
      find.byType(WebPdfPickRegion),
    );
    expect(restored.enabled, isTrue);
    expect(identical(restored, picker), isFalse);
    expect(pendingSave.isCompleted, isFalse);
    pendingSave.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
