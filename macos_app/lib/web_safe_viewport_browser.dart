import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'cy_safe_viewport.dart';

/// Flutter 웹의 0인 여백을 Safari의 CSS 안전 영역과 연결한다.
class WebSafeViewport extends StatefulWidget {
  const WebSafeViewport({super.key, required this.child});
  final Widget child;
  @override
  State<WebSafeViewport> createState() => _WebSafeViewportState();
}

class _WebSafeViewportState extends State<WebSafeViewport>
    with WidgetsBindingObserver {
  late final web.HTMLDivElement _probe;
  Timer? _timer;
  EdgeInsets _insets = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    _probe = web.HTMLDivElement()..className = 'cy-safe-area-probe';
    _probe.setAttribute('aria-hidden', 'true');
    web.document.body!.appendChild(_probe);
    _insets = _read();
    WidgetsBinding.instance.addObserver(this);
    // 홈 화면 첫 실행에서 환경 값이 첫 프레임 뒤에 정해지는 경우도 반영한다.
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refresh(),
    );
  }

  EdgeInsets _read() {
    final css = web.window.getComputedStyle(_probe);
    double value(String text) =>
        (double.tryParse(text.replaceAll('px', '')) ?? 0).clamp(
          0,
          double.infinity,
        );
    return EdgeInsets.fromLTRB(
      value(css.paddingLeft),
      value(css.paddingTop),
      value(css.paddingRight),
      value(css.paddingBottom),
    );
  }

  void _refresh() {
    if (!mounted) return;
    final insets = _read();
    if (insets != _insets) setState(() => _insets = insets);
  }

  @override
  void didChangeMetrics() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _probe.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CySafeViewport(insets: _insets, child: widget.child);
}
