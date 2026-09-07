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
}
