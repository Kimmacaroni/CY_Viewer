import 'package:cy_viewer/drive_panel.dart';
import 'package:cy_viewer/drive_sync.dart';
import 'package:cy_viewer/cy_localization.dart';
import 'package:cy_viewer/cy_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final language in ['ko', 'en']) {
    testWidgets('Drive 연결 창 320px 큰 글자 $language', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await CyLanguage.instance.select(language);
      DriveSync.instance.disconnect();
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        CyLanguageScope(
          child: MaterialApp(
            theme: CyDesign.theme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: DriveButton(onOpen: (_, _) async {})),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(language == 'ko' ? '닫기' : 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}
