import 'package:cy_viewer/web_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('웹앱 첫 화면이 한국어로 표시된다', (tester) async {
    await tester.pumpWidget(const CyViewerWebApp());
    await tester.pumpAndSettle();

    expect(find.text('CY뷰어'), findsOneWidget);
    expect(find.text('아이폰에서 PDF를 열어 보세요'), findsOneWidget);
    expect(find.text('PDF 선택'), findsOneWidget);
  });
}
