import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart';

class PickedWebPdf {
  const PickedWebPdf({required this.name, required this.bytes});

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
  late final HTMLLabelElement _label;
  late final HTMLInputElement _input;
  late final HTMLSpanElement _caption;
  late final JSFunction _changeListener;
  late final JSFunction _focusListener;
  late final JSFunction _blurListener;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _label = HTMLLabelElement();
    _label.style
      ..display = 'flex'
      ..alignItems = 'center'
      ..justifyContent = 'center'
      ..position = 'relative'
      ..width = '100%'
      ..height = '100%'
      ..boxSizing = 'border-box'
      ..borderRadius = '10px'
      ..overflow = 'hidden'
      ..fontFamily = '-apple-system, BlinkMacSystemFont, sans-serif'
      ..fontWeight = '600';
    _caption = HTMLSpanElement()..textContent = 'PDF 열기';
    _caption.style.pointerEvents = 'none';
    _input = HTMLInputElement()
      ..type = 'file'
      ..accept = 'application/pdf,.pdf'
      ..multiple = false
      ..setAttribute('aria-label', 'PDF 열기');
    // 실제 입력이 전체 버튼의 터치를 직접 받는다. 레이아웃에서 숨기지 않는다.
    _input.style
      ..position = 'absolute'
      ..inset = '0'
      ..width = '100%'
      ..height = '100%'
      ..margin = '0'
      ..padding = '0'
      ..opacity = '0.01'
      ..fontSize = '16px'
      ..cursor = 'pointer';
    _label.append(_caption);
    _label.append(_input);
    _changeListener = ((Event _) => unawaited(_processSelection())).toJS;
    _focusListener = ((Event _) {
      _label.style.outline = '2px solid currentColor';
      _label.style.outlineOffset = '-4px';
    }).toJS;
    _blurListener = ((Event _) => _label.style.outline = 'none').toJS;
    _input.addEventListener('change', _changeListener);
    _input.addEventListener('focus', _focusListener);
    _input.addEventListener('blur', _blurListener);
  }

  void _updateAvailability() {
    _input.disabled = !widget.enabled || _reading;
    _caption.textContent = _reading ? 'PDF 읽는 중…' : 'PDF 열기';
    _label.setAttribute('aria-busy', '$_reading');
  }

  Future<void> _processSelection() async {
    if (_reading || !widget.enabled) return;
    final file = _input.files?.item(0);
    if (file == null) return;
    _reading = true;
    _updateAvailability();
    try {
      final bytes = await _readFile(file).timeout(const Duration(seconds: 60));
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
    _input.removeEventListener('focus', _focusListener);
    _input.removeEventListener('blur', _blurListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String cssColor(Color color) =>
        '#${color.toARGB32().toRadixString(16).substring(2)}';
    _label.style
      ..backgroundColor = cssColor(colors.primary)
      ..color = cssColor(colors.onPrimary)
      ..fontSize = '${MediaQuery.textScalerOf(context).scale(16)}px';
    _updateAvailability();
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (element) {
        final host = element as HTMLDivElement;
        host.style
          ..width = '100%'
          ..height = '100%'
          ..pointerEvents = 'auto';
        host.append(_label);
      },
    );
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
        completer.completeError(const FormatException('PDF 데이터를 읽지 못했습니다.'));
      } else {
        completer.complete(buffer.asUint8List());
      }
    }).toJS,
  );
  reader.addEventListener(
    'error',
    ((Event _) => completer.completeError(
      StateError('PDF 파일 읽기에 실패했습니다.'),
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
  Timer(const Duration(minutes: 10), () => URL.revokeObjectURL(url));
}
