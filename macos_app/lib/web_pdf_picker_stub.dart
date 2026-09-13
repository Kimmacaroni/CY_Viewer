import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class PickedWebPdf {
  const PickedWebPdf({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<PickedWebPdf?> pickWebPdf() async => null;

class WebPdfPickRegion extends StatelessWidget {
  const WebPdfPickRegion({
    super.key,
    required this.onPicked,
    required this.onError,
  });

  final ValueChanged<PickedWebPdf> onPicked;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
