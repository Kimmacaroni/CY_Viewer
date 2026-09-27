import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cy_viewer/web_control_geometry.dart';

void main() {
  testWidgets('기본 HTML 컨트롤의 터치 영역이 스크롤 뷰 밖으로 나오지 않는다', (tester) async {
    final anchor = GlobalKey();
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 100,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 80),
                    SizedBox(key: anchor, width: 200, height: 48),
                    const SizedBox(height: 200),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final box = anchor.currentContext!.findRenderObject()! as RenderBox;
    const viewport = Rect.fromLTWH(0, 0, 800, 600);
    var geometry = nativeControlGeometry(box, viewport);
    expect(geometry.bounds.height, 48);
    expect(geometry.clip.height, 20);
    expect(geometry.clip.bottom, 100);
    scroll.jumpTo(100);
    await tester.pump();
    geometry = nativeControlGeometry(box, viewport);
    expect(geometry.clip.top, 0);
    expect(geometry.clip.height, 28);
    scroll.jumpTo(160);
    await tester.pump();
    expect(nativeControlGeometry(box, viewport).clip.isEmpty, true);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
