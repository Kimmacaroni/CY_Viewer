import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cy_viewer/advanced_reader.dart';
import 'package:cy_viewer/cy_localization.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets('Mac 기본 800×600 창에서 페이지 구성 진입점이 보인다 ($scale)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              textScaler: TextScaler.linear(scale),
            ),
            child: const AdvancedPdfReaderPage(
              path: '/tmp/cy-missing-visibility-fixture.pdf',
              name: '문서.pdf',
              initialPage: 1,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final entry = find.widgetWithIcon(
        TextButton,
        Icons.library_books_outlined,
      );
      expect(entry, findsOneWidget);
      expect(tester.getRect(entry).bottom, lessThan(100));
      expect(find.text(trNow('페이지 구성')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final menuEntry = find.widgetWithText(ListTile, trNow('페이지 구성·병합'));
      expect(menuEntry, findsOneWidget);
      final rect = tester.getRect(menuEntry);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(600));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, skip: !Platform.isMacOS);
  }
}
