import 'package:cy_viewer/cy_recent_files.dart';
import 'package:cy_viewer/cy_localization.dart';
import 'package:cy_viewer/cy_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [320.0, 1024.0]) {
    for (final language in ['ko', 'en']) {
      testWidgets('최근 파일 $width $language 큰 글자와 긴 파일명', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await CyLanguage.instance.select(language);
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? opened, removed;
        await tester.pumpWidget(
          CyLanguageScope(
            child: MaterialApp(
              theme: CyDesign.theme(Brightness.light),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1400),
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: CyRecentFiles(
                        files: List.generate(
                          5,
                          (i) => {
                            'id': '$i',
                            'name':
                                '길고 긴 실제 문서 이름 long document filename $i.pdf',
                          },
                        ),
                        onOpen: (row) => opened = row['id'] as String,
                        onRemove: (id) => removed = id,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(ListTile).first);
        expect(opened, '0');
        await tester.tap(find.byIcon(Icons.close).first);
        expect(removed, '0');
      });
    }
  }
}
