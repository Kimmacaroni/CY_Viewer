import 'dart:js_interop';

@JS('cyDriveAuthorize')
external JSPromise<JSString> _authorize();
Future<String> driveAuthorize() async => (await _authorize().toDart).toDart;
