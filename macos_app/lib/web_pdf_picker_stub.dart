import 'dart:typed_data';

class PickedWebPdf {
  const PickedWebPdf({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<PickedWebPdf?> pickWebPdf() async => null;
