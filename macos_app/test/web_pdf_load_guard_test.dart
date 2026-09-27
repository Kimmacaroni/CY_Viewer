import 'dart:async';

import 'package:cy_viewer/web_pdf_load_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({
    required Future<void> Function() initialize,
    required Widget Function(VoidCallback) viewer,
    VoidCallback? open,
  }) => MaterialApp(
    home: Scaffold(
      body: WebPdfLoadGuard(
        initialize: initialize,
        viewerBuilder: viewer,
        onOpenInBrowser: open ?? () {},
        onChooseAnother: () {},
        timeout: const Duration(seconds: 2),
      ),
    ),
  );

  testWidgets('초기화가 멈춰도 제한 시간 후 기본 뷰어로 열 수 있다', (tester) async {
    final pending = Completer<void>();
    var opened = false;
    await tester.pumpWidget(
      app(
        initialize: () => pending.future,
        viewer: (_) => const Text('문서'),
        open: () => opened = true,
      ),
    );
    expect(find.text('PDF를 준비하고 있습니다.'), findsOneWidget);
    expect(find.text('문서'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('PDF 읽기를 완료하지 못했습니다.'), findsOneWidget);
    await tester.tap(find.text('브라우저로 PDF 열기'));
    expect(opened, isTrue);
    pending.complete();
    await tester.pump();
    expect(find.text('문서'), findsNothing);
  });

  testWidgets('초기화 예외를 잡고 빈 화면 대신 복구 방법을 표시한다', (tester) async {
    await tester.pumpWidget(
      app(
        initialize: () async => throw StateError('worker failed'),
        viewer: (_) => const Text('문서'),
      ),
    );
    await tester.pump();
    expect(find.text('PDF 읽기를 완료하지 못했습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('초기화 후 문서 오류나 암호 입력 화면을 가리지 않는다', (tester) async {
    late VoidCallback ready;
    await tester.pumpWidget(
      app(
        initialize: () async {},
        viewer: (callback) {
          ready = callback;
          return const Text('PDF 암호 입력');
        },
      ),
    );
    await tester.pump();
    expect(find.text('PDF 암호 입력'), findsOneWidget);
    expect(find.text('PDF를 준비하고 있습니다.'), findsNothing);
    ready();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('PDF 읽기를 완료하지 못했습니다.'), findsNothing);
  });

  testWidgets('문서 열기가 응답하지 않을 때도 제한 시간을 적용한다', (tester) async {
    await tester.pumpWidget(
      app(initialize: () async {}, viewer: (_) => const Text('페이지 준비 중')),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('PDF 읽기를 완료하지 못했습니다.'), findsOneWidget);
    expect(find.text('페이지 준비 중'), findsNothing);
  });

  testWidgets('화면을 닫은 뒤 늦게 끝난 초기화는 상태를 변경하지 않는다', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      app(initialize: () => pending.future, viewer: (_) => const Text('문서')),
    );
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('late failure'));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
