import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cy_viewer/pdfcraft_dialog.dart';
import 'package:cy_viewer/cy_design.dart';
import 'package:cy_viewer/pdfcraft_service.dart';

class TestBackend implements PdfcraftBackend {
  Map<String, Object?>? options;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> inspect(
    PdfcraftSource source,
    String password,
  ) async => {
    'pages': 4,
    'encrypted': false,
    'signed': false,
    'owner': true,
    'metadata': {
      'Title': '기존 제목',
      'Author': 'CY',
      'Subject': '',
      'Keywords': '',
    },
    'bookmarks': [
      {
        'path': [0],
        'title': '첫 장',
        'page': 1,
      },
    ],
  };
  @override
  Future<PdfcraftResult> edit(
    List<PdfcraftSource> sources,
    Map<String, Object?> options,
    String password,
  ) async {
    this.options = options;
    if (fail) throw const FormatException('검증용 저장 오류');
    return PdfcraftResult(
      Uint8List.fromList([1, 2]),
      options.containsKey('split_every') ? 'zip' : 'pdf',
      (options['page_plan'] as List?)?.length ?? 4,
      1,
    );
  }
}

void main() {
  test('페이지 순서와 범위 밖·중복 보호', () {
    expect(parsePdfcraftPages('3, 1-2', 4), [3, 1, 2]);
    for (final value in ['', '0', '5', '1,1', '3-1', '1-2-3', '1,', 'x', '９']) {
      expect(() => parsePdfcraftPages(value, 4), throwsFormatException);
    }
  });
  testWidgets('좁은 화면과 큰 글자에서 페이지 구성·저장 경로를 유지한다', (tester) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: PdfcraftDialog(
            source: PdfcraftSource('실제 파일 이름.pdf', Uint8List(0)),
            pageCount: 4,
            backend: TestBackend(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Mac 기본 창에서 스크롤 없이 회전·삭제·빈 페이지 도구를 쓴다', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = TestBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: CyDesign.theme(Brightness.light),
        home: PdfcraftDialog(
          source: PdfcraftSource('test.pdf', Uint8List(0)),
          pageCount: 4,
          backend: backend,
          saveResult: (_) async => '/tmp/result.pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    for (final label in ['오른쪽 회전', '선택 페이지 삭제', '빈 페이지 삽입']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.text('오른쪽 회전'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect((backend.options!['page_plan'] as List).first['rotation'], 90);
    expect(tester.takeException(), isNull);
  });
  testWidgets('회전·빈 페이지·되돌리기를 실제 저장 요청에 반영한다', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = TestBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfcraftDialog(
          source: PdfcraftSource('test.pdf', Uint8List(0)),
          pageCount: 4,
          backend: backend,
          saveResult: (_) async => '/tmp/result.pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.ensureVisible(find.text('오른쪽 회전'));
    await tester.tap(find.text('오른쪽 회전'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect((backend.options!['page_plan'] as List).first['rotation'], 90);
    expect(find.text('결과 열기'), findsOneWidget);
    await tester.ensureVisible(find.text('빈 페이지 삽입'));
    await tester.tap(find.text('빈 페이지 삽입'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    final plan = backend.options!['page_plan'] as List;
    expect(plan.length, 5);
    expect(plan[1]['index'], isNull);
    await tester.tap(find.byTooltip('페이지 편집 되돌리기'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect((backend.options!['page_plan'] as List).length, 4);
    expect(tester.takeException(), isNull);
  });
  testWidgets('문서 정보와 새 책갈피를 저장하고 오류 후 재시도한다', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = TestBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfcraftDialog(
          source: PdfcraftSource('test.pdf', Uint8List(0)),
          pageCount: 4,
          backend: backend,
          saveResult: (_) async => '/tmp/result.pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('정보·책갈피'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('제목')), '새 제목');
    await tester.ensureVisible(find.text('책갈피 추가'));
    await tester.tap(find.text('책갈피 추가'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('bookmark-name-1')));
    await tester.enterText(
      find.byKey(const ValueKey('bookmark-name-1')),
      '둘째 장',
    );
    await tester.enterText(find.byKey(const ValueKey('bookmark-page-1')), '2');
    backend.fail = true;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('검증용 저장 오류'), findsOneWidget);
    backend.fail = false;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect((backend.options!['metadata'] as Map)['Title'], '새 제목');
    expect((backend.options!['bookmarks'] as List).single['page'], 2);
    expect(find.text('결과 열기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('문서 마무리에서 워터마크와 쪽 번호를 저장 요청에 넣는다', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = TestBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfcraftDialog(
          source: PdfcraftSource('test.pdf', Uint8List(0)),
          pageCount: 4,
          backend: backend,
          saveResult: (_) async => '/tmp/result.pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('문서 마무리'));
    await tester.tap(find.text('문서 마무리'));
    await tester.pumpAndSettle();
    final watermark = find.widgetWithText(SwitchListTile, '텍스트 워터마크');
    await tester.ensureVisible(watermark);
    await tester.tap(watermark);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('워터마크 문구 (영문·숫자)')));
    await tester.enterText(
      find.byKey(const ValueKey('워터마크 문구 (영문·숫자)')),
      'DRAFT',
    );
    final numbers = find.widgetWithText(SwitchListTile, '페이지 번호 넣기');
    await tester.ensureVisible(numbers);
    await tester.tap(numbers);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(backend.options!['finishing'], {
      'watermark': 'DRAFT',
      'page_numbers': true,
    });
    expect(find.text('결과 열기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
