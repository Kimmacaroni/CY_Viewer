import 'dart:typed_data';

bool get useNativePdfPrint => false;
bool openPrintPdf(Uint8List bytes) => false;

class PrintSurface {
  final List<Uint8List> pages = [];
  Future<void> addPage(Uint8List png) async {
    pages.add(png);
  }

  void print() {}
  void dispose() {
    pages.clear();
  }
}
