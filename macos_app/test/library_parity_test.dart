import 'package:cy_viewer/cy_design.dart';
import 'package:cy_viewer/cy_recent_files.dart';
import 'package:cy_viewer/web_main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('웹 문서함의 즐겨찾기 빈 상태에서 전체 문서로 돌아간다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CyViewerWebApp());
    await tester.pumpAndSettle();
    expect(find.text('문서함'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '즐겨찾기'));
    await tester.pumpAndSettle();
    expect(find.text('즐겨찾는 문서가 없습니다'), findsOneWidget);
    await tester.ensureVisible(find.text('전체 문서 보기'));
    await tester.tap(find.text('전체 문서 보기'));
    await tester.pumpAndSettle();
    expect(find.text('즐겨찾는 문서가 없습니다'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('좁은 화면의 긴 파일명·큰 글자·즐겨찾기와 제거 버튼', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    String? favorite;
    await tester.pumpWidget(
      MaterialApp(
        theme: CyDesign.theme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CyRecentFiles(
              files: [
                {
                  'id': 'one',
                  'name': '매우 긴 이름을 가진 문서 이름입니다.pdf',
                  'openedAt': 1,
                },
              ],
              onOpen: (_) {},
              onRemove: (_) {},
              onFavorite: (id) => favorite = id,
              showHeading: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.star_border));
    expect(favorite, 'one');
    expect(tester.takeException(), isNull);
  });
}
