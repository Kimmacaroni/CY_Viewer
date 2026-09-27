import 'dart:async';
import 'dart:typed_data';

import 'package:cy_viewer/cy_localization.dart';
import 'package:cy_viewer/web_inline_print.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Document extends Fake implements PdfDocument {
  @override
  List<PdfPage> get pages => List.generate(16, (_) => _Page());
}

class _Page extends Fake implements PdfPage {}

void main() {
  testWidgets('기본 전체 16쪽 준비, 현재 쪽 변경, 다시 열면 전체, 외부 열기 자동 호출 없음', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await CyLanguage.instance.select('ko');
    final jobs = <List<int>>[];
    var external = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('start'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => InlinePrintDialog(
                  document: _Document(),
                  current: 3,
                  openOriginal: () {
                    external++;
                    return true;
                  },
                  preparePages:
                      (document, pages, surface, active, progress) async {
                        jobs.add(List.of(pages));
                        await surface.addPage(Uint8List(1));
                        progress(pages.length);
                      },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(jobs.single, List.generate(16, (i) => i + 1));
    expect(find.text('전체 16페이지'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '인쇄'));
    await tester.pumpAndSettle();
    expect(external, 0);
    await tester.tap(find.text('범위 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 페이지 (3)'));
    await tester.tap(find.text('인쇄용 PDF 준비'));
    await tester.pumpAndSettle();
    expect(jobs.last, [3]);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(jobs.last.length, 16);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('준비 중 닫은 뒤 늦은 결과는 화면을 변경하지 않는다', (tester) async {
    final pending = Completer<void>();
    bool Function()? activeJob;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('start'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => InlinePrintDialog(
                  document: _Document(),
                  current: 1,
                  openOriginal: () => true,
                  preparePages:
                      (document, pages, surface, active, progress) async {
                        activeJob = active;
                        await pending.future;
                      },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(activeJob!(), false);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('start'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
