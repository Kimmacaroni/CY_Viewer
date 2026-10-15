import 'package:cy_viewer/pdf_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('암호를 가리고 잘못된 암호 재입력·확인·취소를 지원한다', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      const PdfPasswordDialog(name: '잠긴 문서.pdf', retry: true),
                );
              },
              child: const Text('시작'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    expect(find.text('현재 암호가 올바르지 않습니다.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '비밀');
    await tester.pump();
    await tester.tap(find.text('문서 열기'));
    await tester.pumpAndSettle();
    expect(result, '비밀');
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
