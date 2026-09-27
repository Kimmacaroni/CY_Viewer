import 'package:cy_viewer/cy_localization.dart';
import 'package:cy_viewer/cy_translations.dart';
import 'package:cy_viewer/web_main.dart';
import 'package:cy_viewer/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CyLanguage.instance.select('ko');
  });

  testWidgets('언어 변경을 저장하고 웹 문구를 즉시 바꾼다', (tester) async {
    await tester.pumpWidget(const CyViewerWebApp());
    await tester.pumpAndSettle();
    expect(find.text('어떤 문서를 읽을까요?'), findsOneWidget);
    await CyLanguage.instance.select('en');
    await tester.pumpAndSettle();
    expect(find.text('What would you like to read?'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('cy_language'),
      'en',
    );
    await CyLanguage.instance.select('ko');
    await tester.pumpAndSettle();
    expect(find.text('어떤 문서를 읽을까요?'), findsOneWidget);
  });

  testWidgets('열려 있는 경로를 언어 변경으로 닫지 않는다', (tester) async {
    await tester.pumpWidget(const CyViewerWebApp());
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('open-document')),
      ),
    );
    await tester.pumpAndSettle();
    await CyLanguage.instance.select('en');
    await tester.pumpAndSettle();
    expect(find.text('open-document'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)),
      same(navigator),
    );
  });

  testWidgets('저장된 언어와 지원하지 않는 기기 언어의 영어 대체', (tester) async {
    SharedPreferences.setMockInitialValues({'cy_language': 'en'});
    await CyLanguage.instance.load();
    expect(CyLanguage.instance.locale.languageCode, 'en');
    tester.binding.platformDispatcher.localeTestValue = const Locale('fr');
    await CyLanguage.instance.select('system');
    expect(CyLanguage.instance.locale.languageCode, 'en');
    tester.binding.platformDispatcher.localeTestValue = const Locale('ko');
    expect(CyLanguage.instance.locale.languageCode, 'ko');
    tester.binding.platformDispatcher.clearLocaleTestValue();
  });

  for (final width in [320.0, 1024.0]) {
    for (final web in [true, false]) {
      testWidgets('영어 ${web ? "웹" : "Mac"} 시작 화면 $width', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await CyLanguage.instance.select('en');
        await tester.pumpWidget(
          web ? const CyViewerWebApp() : const PersonalPdfApp(),
        );
        await tester.pumpAndSettle();
        expect(find.text('What would you like to read?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('번역의 동적 인수와 줄바꿈을 보존한다', () {
    final pattern = RegExp(r'\{\d+\}');
    for (final entry in cyEnglish.entries) {
      final source = pattern.allMatches(entry.key).map((m) => m[0]).toList()
        ..sort();
      final target = pattern.allMatches(entry.value).map((m) => m[0]).toList()
        ..sort();
      expect(target, source, reason: entry.key);
      expect(entry.value, isNotEmpty);
    }
  });
}
