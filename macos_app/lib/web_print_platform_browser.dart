import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get useNativePdfPrint {
  final nav = web.window.navigator;
  final ua = nav.userAgent;
  return (ua.contains('Safari') && !ua.contains('Chrome')) ||
      RegExp(r'iPhone|iPad|iPod|Android').hasMatch(ua) ||
      (nav.platform == 'MacIntel' && nav.maxTouchPoints > 1);
}

/// PDF를 준비한 뒤 사용자가 누르는 별도 버튼에서 동기적으로 실행한다.
bool openPrintPdf(Uint8List bytes) {
  final url = web.URL.createObjectURL(
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf')),
  );
  final tab = web.window.open(url, '_blank');
  if (tab == null) {
    web.URL.revokeObjectURL(url);
    return false;
  }
  Timer(const Duration(minutes: 30), () => web.URL.revokeObjectURL(url));
  return true;
}

/// 같은 문서에 인쇄 전용 HTML을 유지한다. Safari의 PDF iframe을 사용하지 않는다.
class PrintSurface {
  final web.HTMLDivElement _root = web.HTMLDivElement();
  final web.HTMLStyleElement _style = web.HTMLStyleElement();
  final List<String> _urls = [];
  bool _disposed = false;
  PrintSurface() {
    _root.id = 'cy-print-pages';
    _root.style.display = 'none';
    _style.media = 'not all';
    _style.textContent = '''
@media print {
  @page { size: A4; margin: 10mm; }
  html, body { width: auto !important; height: auto !important; overflow: visible !important; position: static !important; margin: 0 !important; }
  body > :not(#cy-print-pages) { display: none !important; }
  #cy-print-pages { display: block !important; position: static !important; }
  #cy-print-pages section { width: 190mm; height: 276mm; margin: 0; padding: 0; break-inside: avoid; break-after: page; page-break-after: always; }
  #cy-print-pages section:last-child { break-after: auto; page-break-after: auto; }
  #cy-print-pages img { width: 100%; height: 100%; object-fit: contain; display: block; }
}
''';
    web.document.head!.appendChild(_style);
    web.document.body!.appendChild(_root);
  }
  Future<void> addPage(Uint8List png) async {
    if (_disposed) return;
    final url = web.URL.createObjectURL(
      web.Blob([png.toJS].toJS, web.BlobPropertyBag(type: 'image/png')),
    );
    _urls.add(url);
    final img = web.HTMLImageElement()..src = url;
    final section = web.document.createElement('section')..appendChild(img);
    _root.appendChild(section);
    await img.decode().toDart;
  }

  void print() {
    if (_disposed || _urls.isEmpty) {
      throw StateError('Print pages are not ready');
    }
    // 사용자 클릭에서 직접 호출. afterprint가 조기에 오는 Safari에서도 자료를 유지한다.
    _style.media = 'print';
    web.window.print();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _root.remove();
    _style.remove();
    for (final url in _urls) {
      web.URL.revokeObjectURL(url);
    }
    _urls.clear();
  }
}
