import 'cy_localization.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

class PickedWebPdf {
  PickedWebPdf({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class WebPdfPickRegion extends StatelessWidget {
  const WebPdfPickRegion({
    super.key,
    required this.onPicked,
    required this.onError,
    this.enabled = true,
  });

  final ValueChanged<PickedWebPdf> onPicked;
  final ValueChanged<Object> onError;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: enabled ? () {} : null,
    icon: Icon(Icons.folder_open_outlined),
    label: Text(tr(context, "PDF 열기")),
  );
}

void openWebPdfInBrowser(Uint8List bytes) {}
