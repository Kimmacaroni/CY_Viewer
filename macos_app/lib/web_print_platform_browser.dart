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
