import 'package:flutter/material.dart';

class WebNativeButton extends StatelessWidget {
  const WebNativeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.width,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final double? width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 48,
    child: primary
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label)),
  );
}
