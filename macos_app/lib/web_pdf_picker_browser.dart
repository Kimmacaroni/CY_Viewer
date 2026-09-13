import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart';

class PickedWebPdf {
  const PickedWebPdf({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// iPhone Safari에서 파일 선택이 끝나기 전에 input이 제거되지 않도록 직접 관리한다.
Future<PickedWebPdf?> pickWebPdf() async {
  final completer = Completer<PickedWebPdf?>();
  final input = HTMLInputElement()
    ..type = 'file'
    ..accept = 'application/pdf,.pdf'
    ..multiple = false
    ..setAttribute('aria-hidden', 'true');
  input.style
    ..position = 'fixed'
    ..left = '-10000px'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0';

  late final JSFunction changeListener;
  late final JSFunction cancelListener;

  void cleanup() {
    input.removeEventListener('change', changeListener);
    input.removeEventListener('cancel', cancelListener);
    input.remove();
  }

  Future<void> processChange(Event _) async {
    try {
      final file = input.files?.item(0);
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final bytes = await _readFile(file);
      if (!completer.isCompleted) {
        completer.complete(PickedWebPdf(name: file.name, bytes: bytes));
      }
    } on Object catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    } finally {
      cleanup();
    }
  }

  void handleChange(Event event) {
    unawaited(processChange(event));
  }

  void handleCancel(Event _) {
    if (!completer.isCompleted) completer.complete(null);
    cleanup();
  }

  changeListener = handleChange.toJS;
  cancelListener = handleCancel.toJS;
  input.addEventListener('change', changeListener);
  input.addEventListener('cancel', cancelListener);
  document.body!.append(input);

  // 반드시 사용자의 탭 이벤트 안에서 동기적으로 호출해야 Safari가 허용한다.
  input.click();
  return completer.future;
}

/// 투명한 실제 HTML 파일 입력을 Flutter 버튼 위에 올려 Safari의 직접 탭을 받는다.
class WebPdfPickRegion extends StatefulWidget {
  const WebPdfPickRegion({
    super.key,
    required this.onPicked,
    required this.onError,
  });

  final ValueChanged<PickedWebPdf> onPicked;
  final ValueChanged<Object> onError;

  @override
  State<WebPdfPickRegion> createState() => _WebPdfPickRegionState();
}

class _WebPdfPickRegionState extends State<WebPdfPickRegion> {
  static int _nextId = 0;
  late final String _viewType;
  late final HTMLInputElement _input;
  late final JSFunction _changeListener;

  @override
  void initState() {
    super.initState();
    _viewType = 'cy-pdf-input-${_nextId++}';
    _input = HTMLInputElement()
      ..type = 'file'
      ..accept = 'application/pdf,.pdf'
      ..multiple = false
      ..setAttribute('aria-label', 'PDF 선택');
    _input.style
      ..width = '100%'
      ..height = '100%'
      ..opacity = '0'
      ..cursor = 'pointer';
    _changeListener = _handleChange.toJS;
    _input.addEventListener('change', _changeListener);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _input);
  }

  void _handleChange(Event _) {
    unawaited(_processSelection());
  }

  Future<void> _processSelection() async {
    try {
      final file = _input.files?.item(0);
      if (file == null) return;
      final bytes = await _readFile(file);
      widget.onPicked(PickedWebPdf(name: file.name, bytes: bytes));
    } on Object catch (error) {
      widget.onError(error);
    } finally {
      _input.value = '';
    }
  }

  @override
  void dispose() {
    _input.removeEventListener('change', _changeListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
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
