import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'cy_localization.dart';
import 'web_print.dart';
import 'web_print_platform.dart';

/// 화면 캡처가 아닌 PDF 원본 페이지를 인쇄 해상도로 렌더링한다.
Future<void> renderPrintPages(
  PdfDocument document,
  List<int> pages,
  PrintSurface surface,
  bool Function() active,
  void Function(int) progress,
) async {
  final area = pages.fold<double>(
    0,
    (sum, n) =>
        sum + document.pages[n - 1].width * document.pages[n - 1].height,
  );
  final scale = math.min(150 / 72, math.sqrt(64000000 / area));
  if (scale < 1) {
    throw StateError(trNow('문서가 너무 큽니다. 인쇄 범위를 줄이거나 원본 PDF를 사용해 주세요.'));
  }
  for (var i = 0; i < pages.length && active(); i++) {
    final page = document.pages[pages[i] - 1];
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
      backgroundColor: 0xffffffff,
    );
    if (image == null) throw StateError('PDF page render failed');
    try {
      if (!active()) return;
      final decoded = await image.createImage();
      try {
        final data = await decoded.toByteData(format: ui.ImageByteFormat.png);
        if (!active()) return;
        if (data == null) throw StateError('PDF image encoding failed');
        await surface.addPage(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        decoded.dispose();
      }
    } finally {
      image.dispose();
    }
    if (active()) progress(i + 1);
  }
}

class InlinePrintDialog extends StatefulWidget {
  const InlinePrintDialog({
    super.key,
    required this.document,
    required this.current,
    required this.openOriginal,
    this.preparePages = renderPrintPages,
  });
  final PdfDocument document;
  final int current;
  final bool Function() openOriginal;
  final Future<void> Function(
    PdfDocument,
    List<int>,
    PrintSurface,
    bool Function(),
    void Function(int),
  )
  preparePages;
  @override
  State<InlinePrintDialog> createState() => _InlinePrintDialogState();
}

class _InlinePrintDialogState extends State<InlinePrintDialog> {
  late List<int> _pages;
  PrintSurface? _surface;
  Timer? _timer;
  int _generation = 0;
  int _completed = 0;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _pages = List.generate(widget.document.pages.length, (i) => i + 1);
    _prepare();
  }

  void _stop() {
    _generation++;
    _timer?.cancel();
    _surface?.dispose();
    _surface = null;
  }

  Future<void> _prepare() async {
    _stop();
    final generation = _generation;
    final surface = PrintSurface();
    _surface = surface;
    _ready = false;
    _error = null;
    _completed = 0;
    bool active() => mounted && generation == _generation;
    _timer = Timer(const Duration(minutes: 2), () {
      if (!active()) return;
      _stop();
      setState(
        () => _error = TimeoutException(
          tr(context, '인쇄 준비 시간이 초과되었습니다. 범위를 줄여 다시 시도해 주세요.'),
        ),
      );
    });
    try {
      await widget.preparePages(widget.document, _pages, surface, active, (
        count,
      ) {
        if (active()) setState(() => _completed = count);
      });
      if (!active()) return;
      _timer?.cancel();
      setState(() => _ready = true);
    } on Object catch (error) {
      if (!active()) return;
      _stop();
      setState(() => _error = error);
    }
  }

  Future<void> _changeRange() async {
    final pages = await choosePrintPages(
      context,
      widget.document.pages.length,
      widget.current,
    );
    if (pages == null || !mounted) return;
    setState(() => _pages = pages);
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, '인쇄')),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _pages.length == widget.document.pages.length
                  ? tr(context, '전체 {0}페이지', [_pages.length])
                  : tr(context, '선택한 {0}페이지', [_pages.length]),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(tr(context, '인쇄 창을 열 수 없습니다: {0}', [_error!]))
            else if (!_ready) ...[
              LinearProgressIndicator(value: _completed / _pages.length),
              const SizedBox(height: 12),
              Text(tr(context, '인쇄 준비 중 {0}/{1}', [_completed, _pages.length])),
            ] else
              Text(tr(context, '전체 페이지가 기본입니다. 인쇄를 누르면 시스템 인쇄 창이 열립니다.')),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _changeRange,
              child: Text(tr(context, '범위 변경')),
            ),
            if (_ready || _error != null)
              TextButton(
                onPressed: () {
                  if (!widget.openOriginal()) {
                    setState(
                      () => _error = StateError(
                        tr(context, 'PDF 창이 차단되었습니다. 팝업을 허용한 뒤 다시 눌러 주세요.'),
                      ),
                    );
                  }
                },
                child: Text(tr(context, '인쇄가 안 되면 원본 PDF 열기')),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          _stop();
          Navigator.pop(context);
        },
        child: Text(tr(context, '닫기')),
      ),
      FilledButton(
        onPressed: !_ready
            ? null
            : () {
                try {
                  _surface!.print();
                } on Object catch (error) {
                  setState(() => _error = error);
                }
              },
        child: Text(tr(context, '인쇄')),
      ),
    ],
  );
}
