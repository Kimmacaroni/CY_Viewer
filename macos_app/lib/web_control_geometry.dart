import 'package:flutter/rendering.dart';

/// 네이티브 컨트롤이 Flutter의 스크롤/클립 영역을 넘어 터치를 받지 않게 한다.
({Rect bounds, Rect clip}) nativeControlGeometry(RenderBox box, Rect viewport) {
  final bounds = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  var clip = bounds.intersect(viewport);
  RenderObject child = box;
  while (child.parent != null) {
    final parent = child.parent!;
    final paintClip = parent.describeApproximatePaintClip(child);
    if (paintClip != null) {
      clip = clip.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), paintClip),
      );
    }
    child = parent;
  }
  return (bounds: bounds, clip: clip);
}
