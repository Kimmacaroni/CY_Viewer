import 'package:cy_viewer/app.dart';
import 'package:cy_viewer/cy_design.dart';
import 'package:cy_viewer/web_main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final web in [false, true]) {
    for (final size in [const Size(320, 640), const Size(1024, 768)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${web ? "웹" : "앱"} 문서함 ${size.width} 너비 / 글자 $scale 배율', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          SharedPreferences.setMockInitialValues({});
          await tester.pumpWidget(
            web ? const CyViewerWebApp() : const PersonalPdfApp(),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // 첫 행동이 스크롤로 접근 가능하고 터치 영역이 유지되어야 한다.
          final button = find.widgetWithText(FilledButton, 'PDF 열기');
          await tester.ensureVisible(button);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final scenario in [
    (1200.0, 1.0, true),
    (390.0, 1.0, false),
    (1200.0, 2.0, false),
  ]) {
    testWidgets('공통 리더 도구 배치 ${scenario.$1} / ${scenario.$2}', (tester) async {
      tester.view.physicalSize = Size(scenario.$1, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: CyDesign.theme(Brightness.light),
          home: Scaffold(
            body: CyReaderWorkspace(
              onOpen: () {},
              onSearch: null,
              onPage: null,
              onBookmark: () {},
              onTools: () {},
              onSave: () => saves++,
              onPrint: () {},
              onZoomIn: () {},
              onZoomOut: () {},
              child: const Center(child: Text('문서 영역')),
            ),
          ),
        ),
      );
      expect(find.text('문서 영역'), findsOneWidget);
      expect(
        find.text('01  문서 탐색'),
        scenario.$3 ? findsOneWidget : findsNothing,
      );
      if (scenario.$3) {
        final save = find.widgetWithText(OutlinedButton, 'PDF로 저장');
        await tester.ensureVisible(save);
        await tester.tap(save);
        expect(saves, 1);
        expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('즐겨찾기 빈 상태에서 전체 문서로 돌아갈 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PersonalPdfApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('즐겨찾기'));
    await tester.pumpAndSettle();
    expect(find.text('즐겨찾는 문서가 없습니다'), findsOneWidget);
    await tester.tap(find.text('전체 문서 보기'));
    await tester.pumpAndSettle();
    expect(find.text('문서를 열고,\n바로 읽으세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
