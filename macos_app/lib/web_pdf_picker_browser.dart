import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

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
