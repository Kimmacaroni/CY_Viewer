import 'dart:async';

import 'package:flutter/services.dart';

typedef AppCommandCallback = FutureOr<void> Function();

/// macOS 메뉴와 현재 화면의 기능을 연결한다.
///
/// 화면이 겹쳐 있을 때는 가장 나중에 등록된 화면부터 명령을 처리한다.
class AppCommandDispatcher {
  AppCommandDispatcher._();

  static const _channel = MethodChannel('com.kimmacaroni.cyviewer/commands');
  static final List<Map<String, AppCommandCallback>> _handlers = [];
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      for (final handlers in _handlers.reversed) {
        final callback = handlers[call.method];
        if (callback != null) {
          await callback();
          return true;
        }
      }
      return false;
    });
  }

  static Map<String, AppCommandCallback> register(
    Map<String, AppCommandCallback> handlers,
  ) {
    _handlers.add(handlers);
    return handlers;
  }

  static void unregister(Map<String, AppCommandCallback> handlers) {
    _handlers.remove(handlers);
  }
}
