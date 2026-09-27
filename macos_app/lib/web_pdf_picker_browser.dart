import 'cy_localization.dart';
import 'web_native_control_browser.dart';

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart';

class PickedWebPdf {
  PickedWebPdf({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 표시와 파일 선택을 하나의 HTML 컨트롤로 처리한다.
/// Flutter 버튼과 투명 입력을 겹치거나 합성 click으로 선택기를 열지 않는다.
class WebPdfPickRegion extends StatefulWidget {
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
  State<WebPdfPickRegion> createState() => _WebPdfPickRegionState();
}

class _WebPdfPickRegionState extends State<WebPdfPickRegion> {
  late final HTMLInputElement _input;
  late final JSFunction _changeListener;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _input = HTMLInputElement()
      ..type = 'file'
      ..accept = 'application/pdf,.pdf'
      ..multiple = false
      ..className = 'cy-pdf-file-input'
      ..setAttribute('aria-label', trNow("PDF 열기"));
    // 기본 파일 선택 버튼 자체를 표시한다. 투명 입력이나 대체 문구를 겹치지 않는다.
    _changeListener = ((Event _) => unawaited(_processSelection())).toJS;
    _input.addEventListener('change', _changeListener);
  }

  void _updateAvailability() {
    _input.disabled = !widget.enabled || _reading;
    _input.setAttribute('aria-busy', '$_reading');
    _input.setAttribute(
      'aria-label',
      _reading ? trNow("PDF 읽는 중") : trNow("PDF 열기"),
    );
  }

  Future<void> _processSelection() async {
    if (_reading || !widget.enabled) return;
    final file = _input.files?.item(0);
    if (file == null) return;
    _reading = true;
    _updateAvailability();
    try {
      final bytes = await _readFile(file).timeout(Duration(seconds: 60));
      if (mounted) widget.onPicked(PickedWebPdf(name: file.name, bytes: bytes));
    } on Object catch (error) {
      if (mounted) widget.onError(error);
    } finally {
      _reading = false;
      _input.value = '';
      if (mounted) _updateAvailability();
    }
  }

  @override
  void dispose() {
    _input.removeEventListener('change', _changeListener);
    _input.disabled = true;
    _input.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String cssColor(Color color) =>
        '#${color.toARGB32().toRadixString(16).substring(2)}';
    _input.style
      ..backgroundColor = cssColor(colors.primary)
      ..color = cssColor(colors.onPrimary)
      ..fontSize = '${MediaQuery.textScalerOf(context).scale(16)}px';
    _updateAvailability();
    return NativeControlHost(element: _input, height: 52);
  }
}

Future<Uint8List> _readFile(File file) {
  final completer = Completer<Uint8List>();
  final reader = FileReader();

  reader.addEventListener(
    'load',
    ((Event _) {
      final buffer = (reader.result as JSArrayBuffer?)?.toDart;
      if (buffer == null) {
        completer.completeError(FormatException(trNow("PDF 데이터를 읽지 못했습니다.")));
      } else {
        completer.complete(buffer.asUint8List());
      }
    }).toJS,
  );
  reader.addEventListener(
    'error',
    ((Event _) => completer.completeError(
      StateError(trNow("PDF 파일 읽기에 실패했습니다.")),
    )).toJS,
  );
  reader.readAsArrayBuffer(file);
  return completer.future;
}

/// 탭 이벤트 안에서 바로 열어 Safari 팝업 차단을 피한다. 파일은 업로드하지 않는다.
void openWebPdfInBrowser(Uint8List bytes) {
  final blob = Blob(
    [bytes.toJS].toJS,
    BlobPropertyBag(type: 'application/pdf'),
  );
  final url = URL.createObjectURL(blob);
  window.open(url, '_blank');
  // 새 탭이 데이터를 읽기 전에 해제하지 않고, 임시 URL의 수명은 제한한다.
  Timer(Duration(minutes: 10), () => URL.revokeObjectURL(url));
}
