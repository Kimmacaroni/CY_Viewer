import 'dart:js_interop';

import 'pdfcraft_models.dart';

@JS('cyOpenPdfWorkbench')
external JSPromise<JSAny?> _open(JSString name, JSUint8Array bytes);

extension type _SavedPdf(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
}

Future<PdfcraftResult?> openPdfWorkbench(PdfcraftSource source) async {
  final saved = await _open(source.name.toJS, source.bytes.toJS).toDart;
  if (saved == null) return null;
  return PdfcraftResult(_SavedPdf(saved as JSObject).bytes.toDart, 'pdf', 0, 1);
}
