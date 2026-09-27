import 'dart:convert';
import 'dart:io';

import 'package:cy_viewer/app.dart';
import 'package:cy_viewer/cy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('최근 화면은 5개이며 전체 문서와 즐겨찾기는 보존한다', (tester) async {
    final directory = Directory.systemTemp.createTempSync('cy-recent-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final items = <SavedPdf>[];
    for (var i = 0; i < 8; i++) {
      final file = File('${directory.path}/document-$i.pdf')
        ..writeAsStringSync('%PDF-1.7');
      items.add(
        SavedPdf(
          path: file.path,
          name: 'document-$i.pdf',
          openedAt: DateTime(2026, 1, i + 1),
          favorite: i == 0,
          hasOpened: i != 7,
        ),
      );
    }
    SharedPreferences.setMockInitialValues({
      'personal_pdf_library_v1': jsonEncode(
        items.map((e) => e.toJson()).toList(),
      ),
    });
    await CyLanguage.instance.select('ko');
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PersonalPdfApp());
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(5));
    expect(find.text('document-6.pdf'), findsOneWidget);
    expect(find.text('document-0.pdf'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '전체 문서'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(8));
    await tester.tap(find.widgetWithText(ChoiceChip, '즐겨찾기'));
    await tester.pumpAndSettle();
    expect(find.text('document-0.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
