import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'web_control_geometry.dart';

import 'package:web/web.dart' as web;

/// Flutter는 자리와 크기만 잡고 실제 입력은 document.body의 기본 HTML이 받는다.
/// HtmlElementView/플랫폼 뷰의 합성 레이어를 사용하지 않는다.
class NativeControlHost extends StatefulWidget {
  const NativeControlHost({
    super.key,
    required this.element,
    this.height = 48,
    this.width,
  });
  final web.HTMLElement element;
  final double height;
  final double? width;
  @override
  State<NativeControlHost> createState() => _NativeControlHostState();
}

class _NativeControlHostState extends State<NativeControlHost> {
  final _anchor = GlobalKey();
  late final web.HTMLDivElement _host;
  Timer? _timer;
  bool _active = false;
  @override
  void initState() {
    super.initState();
    _host = web.HTMLDivElement()..className = 'cy-native-control';
    _host.style
      ..position = 'fixed'
      ..zIndex = '2147483000'
      ..overflow = 'hidden'
      ..display = 'none';
    _host.appendChild(widget.element);
    web.document.body!.appendChild(_host);
    _timer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _position(),
    );
  }

  void _position() {
    if (!mounted) return;
    final box = _anchor.currentContext?.findRenderObject();
    if (!_active || box is! RenderBox || !box.attached || !box.hasSize) {
      _host.style.display = 'none';
      return;
    }
    final geometry = nativeControlGeometry(
      box,
      Rect.fromLTWH(
        0,
        0,
        web.window.innerWidth.toDouble(),
        web.window.innerHeight.toDouble(),
      ),
    );
    final bounds = geometry.bounds;
    final clip = geometry.clip;
    if (clip.isEmpty || !bounds.isFinite) {
      _host.style.display = 'none';
      return;
    }
    _host.style
      ..display = 'block'
      ..left = '${clip.left}px'
      ..top = '${clip.top}px'
      ..width = '${clip.width}px'
      ..height = '${clip.height}px';
    widget.element.style
      ..position = 'absolute'
      ..boxSizing = 'border-box'
      ..left = '${bounds.left - clip.left}px'
      ..top = '${bounds.top - clip.top}px'
      ..width = '${bounds.width}px'
      ..height = '${bounds.height}px';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _host.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _active =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (!_active) _host.style.display = 'none';
    WidgetsBinding.instance.addPostFrameCallback((_) => _position());
    return SizedBox(key: _anchor, height: widget.height, width: widget.width);
  }
}

class WebNativeButton extends StatefulWidget {
  const WebNativeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.width,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final double? width;
  @override
  State<WebNativeButton> createState() => _WebNativeButtonState();
}

class _WebNativeButtonState extends State<WebNativeButton> {
  late final web.HTMLButtonElement _button;
  late final JSFunction _click;
  @override
  void initState() {
    super.initState();
    _button = web.HTMLButtonElement()..type = 'button';
    _click = ((web.Event _) => widget.onPressed?.call()).toJS;
    _button.addEventListener('click', _click);
  }

  @override
  void dispose() {
    _button.removeEventListener('click', _click);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String css(Color value) =>
        '#${value.toARGB32().toRadixString(16).substring(2)}';
    _button
      ..textContent = widget.label
      ..disabled = widget.onPressed == null;
    _button.style
      ..backgroundColor = css(widget.primary ? colors.primary : colors.surface)
      ..color = css(widget.primary ? colors.onPrimary : colors.onSurface)
      ..border = '1px solid ${css(colors.outlineVariant)}'
      ..borderRadius = '10px'
      ..fontFamily = '-apple-system,BlinkMacSystemFont,sans-serif'
      ..fontSize = '${MediaQuery.textScalerOf(context).scale(14)}px'
      ..padding = '8px 12px'
      ..cursor = 'pointer'
      ..opacity = widget.onPressed == null ? '0.5' : '1'
      ..touchAction = 'manipulation';
    return NativeControlHost(element: _button, width: widget.width);
  }
}
