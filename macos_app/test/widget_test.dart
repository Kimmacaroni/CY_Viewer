import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_viewer/app.dart';

void main() {
  testWidgets('CY뷰어 문서함이 표시된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PersonalPdfApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CY뷰어'), findsOneWidget);
    expect(find.text('PDF 열기'), findsOneWidget);
  });

  testWidgets('손상된 최근 문서 데이터가 있어도 문서함이 열린다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'personal_pdf_library_v1': '{올바르지 않은 JSON',
    });

    await tester.pumpWidget(const PersonalPdfApp());
    await tester.pumpAndSettle();

    expect(find.text('CY뷰어'), findsOneWidget);
    expect(find.text('첫 PDF를 열어 보세요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('잘못된 마지막 페이지는 첫 페이지로 보정한다', () {
    final item = SavedPdf.fromJson({
      'path': '/tmp/example.pdf',
      'name': 'example.pdf',
      'openedAt': '2026-09-07T00:00:00.000',
      'lastPage': -10,
    });

    expect(item.lastPage, 1);
  });
}
