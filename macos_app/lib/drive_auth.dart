export 'drive_auth_stub.dart'
    if (dart.library.io) 'drive_auth_native.dart'
    if (dart.library.js_interop) 'drive_auth_browser.dart';
