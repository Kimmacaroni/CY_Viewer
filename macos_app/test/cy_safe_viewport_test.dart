import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cy_viewer/cy_safe_viewport.dart';

void main() {
  testWidgets('상태 영역을 제외하고 내부 화면 크기도 줄이며 기존 OS 여백은 중복하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final anchor = GlobalKey();
    Size? reported;
    Widget app(EdgeInsets insets) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(1280, 900),
          padding: EdgeInsets.only(top: 20),
          viewPadding: EdgeInsets.only(top: 20),
        ),
        child: CySafeViewport(
          insets: insets,
          child: Builder(
            builder: (context) {
              reported = MediaQuery.sizeOf(context);
              return SizedBox.expand(key: anchor);
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(const EdgeInsets.fromLTRB(24, 30, 112, 20)));
    expect(
      tester.getRect(find.byKey(anchor)),
      const Rect.fromLTWH(24, 30, 1144, 850),
    );
    expect(reported, const Size(1144, 850));
    await tester.pumpWidget(app(const EdgeInsets.only(top: 10)));
    expect(
      tester.getRect(find.byKey(anchor)),
      const Rect.fromLTWH(0, 20, 1280, 880),
    );
    expect(reported, const Size(1280, 880));
  });
}
