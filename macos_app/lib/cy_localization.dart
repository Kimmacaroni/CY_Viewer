import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cy_browser_locale.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'cy_translations.dart';

class CyLanguage extends ChangeNotifier with WidgetsBindingObserver {
  bool _observing = false;
  CyLanguage._();
  static final instance = CyLanguage._();
  String _mode = 'ko';
  String get mode => _mode;
  Locale get locale {
    final code = _mode == 'system'
        ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
        : _mode;
    return Locale(code == 'ko' ? 'ko' : 'en');
  }

  Future<void> load() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    try {
      final value = (await SharedPreferences.getInstance()).getString(
        'cy_language',
      );
      _mode = ['ko', 'en', 'system'].contains(value) ? value! : 'system';
    } on Object {
      _mode = 'system';
    }
    final requested = Uri.base.queryParameters['lang'];
    // 사용자가 직접 저장한 언어가 공유 링크의 기본 언어보다 우선한다.
    if (kIsWeb && _mode == 'system' && ['ko', 'en'].contains(requested)) {
      _mode = requested!;
    }
    await _sync();
  }

  Future<void> _sync() async {
    setBrowserLanguage(locale.languageCode);
    notifyListeners();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        await const MethodChannel('com.kimmacaroni.cyviewer/language')
            .invokeMethod<void>('set', _mode);
      } on MissingPluginException {
        // 위젯 테스트에는 기본 메뉴 채널이 없다.
      } on PlatformException {
        // 기본 메뉴 오류가 앱 화면의 언어 전환을 막지 않도록 한다.
      }
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_mode == 'system') _sync();
  }

  Future<void> select(String value) async {
    if (!['ko', 'en', 'system'].contains(value)) return;
    _mode = value;
    await _sync();
    await (await SharedPreferences.getInstance()).setString(
      'cy_language',
      value,
    );
  }
}

class CyLanguageScope extends InheritedNotifier<CyLanguage> {
  CyLanguageScope({super.key, required super.child})
    : super(notifier: CyLanguage.instance);
}

String tr(
  BuildContext context,
  String source, [
  List<Object?> args = const [],
]) {
  context.dependOnInheritedWidgetOfExactType<CyLanguageScope>();
  return trNow(source, args);
}

String trNow(String source, [List<Object?> args = const []]) {
  final text = CyLanguage.instance.locale.languageCode == 'ko'
      ? source
      : cyEnglish[source] ?? source;
  return text.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
    final index = int.parse(match[1]!);
    return index < args.length ? '${args[index]}' : match[0]!;
  });
}

class CyLanguageButton extends StatelessWidget {
  const CyLanguageButton({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '언어 / Language',
    icon: const Icon(Icons.language),
    initialValue: CyLanguage.instance.mode,
    onSelected: CyLanguage.instance.select,
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'system', child: Text('기기 언어 / System')),
      PopupMenuItem(value: 'ko', child: Text('한국어')),
      PopupMenuItem(value: 'en', child: Text('English')),
    ],
  );
}
