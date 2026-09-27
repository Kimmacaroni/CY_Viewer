import 'cy_localization.dart';

import 'dart:async';

import 'package:flutter/material.dart';

/// 엔진 초기화가 실패하거나 응답하지 않아도 빈 리더에 갇히지 않도록 한다.
class WebPdfLoadGuard extends StatefulWidget {
  const WebPdfLoadGuard({
    super.key,
    required this.initialize,
    required this.viewerBuilder,
    required this.onOpenInBrowser,
    required this.onChooseAnother,
    this.timeout = const Duration(seconds: 45),
  });

  final Future<void> Function() initialize;
  final Widget Function(VoidCallback onReady) viewerBuilder;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onChooseAnother;
  final Duration timeout;

  @override
  State<WebPdfLoadGuard> createState() => _WebPdfLoadGuardState();
}

class _WebPdfLoadGuardState extends State<WebPdfLoadGuard> {
  Timer? _timer;
  bool _initialized = false;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.timeout, _fail);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize();
      if (mounted && !_failed) setState(() => _initialized = true);
    } on Object {
      _fail();
    }
  }

  void _fail() {
    if (!mounted || _ready) return;
    _timer?.cancel();
    setState(() => _failed = true);
  }

  void _onReady() {
    if (!mounted || _failed) return;
    _timer?.cancel();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_initialized && !_failed) widget.viewerBuilder(_onReady),
      if (!_initialized || _failed)
        ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_failed)
                      Icon(Icons.error_outline, size: 40)
                    else
                      CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text(
                      _failed
                          ? tr(context, "PDF 읽기를 완료하지 못했습니다.")
                          : tr(context, "PDF를 준비하고 있습니다."),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _failed
                          ? tr(context, "브라우저 기본 뷰어로 열거나 다른 PDF를 선택해 주세요.")
                          : tr(context, "처음에는 읽기 도구를 내려받는 데 시간이 걸릴 수 있습니다."),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: widget.onOpenInBrowser,
                      icon: Icon(Icons.open_in_new),
                      label: Text(tr(context, "브라우저로 PDF 열기")),
                    ),
                    TextButton(
                      onPressed: widget.onChooseAnother,
                      child: Text(tr(context, "다른 PDF 선택")),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
