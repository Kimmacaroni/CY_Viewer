import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('cyRecentList')
external JSPromise<JSString> _list();
@JS('cyRecentSave')
external JSPromise<JSAny?> _save(JSString name, JSUint8Array bytes);
@JS('cyRecentRead')
external JSPromise<JSUint8Array?> _read(JSString id);
@JS('cyRecentRemove')
external JSPromise<JSAny?> _remove(JSString id);

Future<List<Map<String, dynamic>>> recentWebList() async =>
    (jsonDecode((await _list().toDart).toDart) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
Future<void> recentWebSave(String name, Uint8List bytes) async {
  await _save(name.toJS, bytes.toJS).toDart;
}

Future<Uint8List?> recentWebRead(String id) async =>
    (await _read(id.toJS).toDart)?.toDart;
Future<void> recentWebRemove(String id) async {
  await _remove(id.toJS).toDart;
}
