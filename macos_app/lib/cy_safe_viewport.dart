import 'package:flutter/material.dart';

/// OS와 브라우저가 알려 준 안전 영역을 한 번만 적용한다.
class CySafeViewport extends StatelessWidget {
  const CySafeViewport({
    super.key,
    required this.child,
    this.insets = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsets insets;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      minimum: insets,
      child: LayoutBuilder(
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: constraints.biggest),
          child: child,
        ),
      ),
    ),
  );
}
