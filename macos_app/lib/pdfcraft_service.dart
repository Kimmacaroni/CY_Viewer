import 'dart:typed_data';

import 'pdfcraft_models.dart';
import 'pdfcraft_service_native.dart'
    if (dart.library.js_interop) 'pdfcraft_service_browser.dart'
    as platform;
export 'pdfcraft_models.dart';

class PdfcraftService implements PdfcraftBackend {
  const PdfcraftService({this.executable});
  final String? executable;
  PdfcraftBackend get _backend => platform.createPdfcraftBackend(executable);
  @override
  Future<Map<String, dynamic>> inspect(
    PdfcraftSource source,
    String password,
  ) => _backend.inspect(source, password);
  @override
  Future<PdfcraftResult> edit(
    List<PdfcraftSource> sources,
    Map<String, Object?> options,
    String password,
  ) => _backend.edit(sources, options, password);
  static Future<Uint8List> compose(
    List<PdfcraftSource> sources,
    String pages, {
    String? executable,
  }) async => (await PdfcraftService(
    executable: executable,
  ).edit(sources, {'pages': pages}, '')).bytes;
}
