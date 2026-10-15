import 'package:flutter/material.dart';

import 'pdfcraft_models.dart';

class PdfcraftBrowserPicker extends StatelessWidget {
  const PdfcraftBrowserPicker({
    super.key,
    required this.onPicked,
    required this.onError,
    required this.enabled,
    required this.onBusyChanged,
  });
  final ValueChanged<List<PdfcraftSource>> onPicked;
  final ValueChanged<Object> onError;
  final bool enabled;
  final ValueChanged<bool> onBusyChanged;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class PdfcraftBrowserDownload extends StatelessWidget {
  const PdfcraftBrowserDownload({
    super.key,
    required this.result,
    required this.name,
  });
  final PdfcraftResult result;
  final String name;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
