import 'package:flutter/material.dart';

import 'cy_safe_viewport.dart';

class WebSafeViewport extends StatelessWidget {
  const WebSafeViewport({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => CySafeViewport(child: child);
}
