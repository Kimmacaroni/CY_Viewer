import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'pdfcraft_models.dart';
import 'cy_localization.dart';
import 'web_native_control_browser.dart';

class PdfcraftBrowserPicker extends StatefulWidget {
  const PdfcraftBrowserPicker({
    super.key,
    required this.onPicked,
    required this.onError,
    required this.enabled,
    required this.onBusyChanged,
  });
  final ValueChanged<List<PdfcraftSource>> onPicked;
  final ValueChanged<Object> onError;
  final bool enabled;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<PdfcraftBrowserPicker> createState() => _PickerState();
}

class _PickerState extends State<PdfcraftBrowserPicker> {
  late final web.HTMLInputElement _input;
  late final JSFunction _change;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.pdf,application/pdf'
      ..multiple = true
      ..className = 'cy-pdf-file-input';
    _change = ((web.Event _) => unawaited(_read())).toJS;
    _input.addEventListener('change', _change);
  }

  Future<void> _read() async {
    if (_busy || !widget.enabled) return;
    setState(() => _busy = true);
    widget.onBusyChanged(true);
    try {
      final files = _input.files;
      if (files == null || files.length == 0) return;
      if (files.length > 19) {
        throw const FormatException('PDF는 20개까지 합칠 수 있습니다.');
      }
      var total = 0;
      final result = <PdfcraftSource>[];
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i)!;
        total += file.size;
        if (file.size > 256 * 1024 * 1024 || total > 512 * 1024 * 1024) {
          throw const FormatException('한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.');
        }
        final buffer = await file.arrayBuffer().toDart.timeout(
          const Duration(seconds: 60),
        );
        result.add(PdfcraftSource(file.name, buffer.toDart.asUint8List()));
      }
      if (mounted) widget.onPicked(result);
    } catch (error) {
      if (mounted) widget.onError(error);
    } finally {
      _input.value = '';
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  void dispose() {
    _input.removeEventListener('change', _change);
    _input.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _input.disabled = !widget.enabled || _busy;
    _input.setAttribute('aria-label', tr(context, '합칠 PDF 추가'));
    return NativeControlHost(element: _input, height: 52);
  }
}

class PdfcraftBrowserDownload extends StatefulWidget {
  const PdfcraftBrowserDownload({
    super.key,
    required this.result,
    required this.name,
  });
  final PdfcraftResult result;
  final String name;
  @override
  State<PdfcraftBrowserDownload> createState() => _DownloadState();
}

class _DownloadState extends State<PdfcraftBrowserDownload> {
  late final String _url;
  late final web.HTMLAnchorElement _link;
  @override
  void initState() {
    super.initState();
    _url = web.URL.createObjectURL(
      web.Blob(
        [widget.result.bytes.toJS].toJS,
        web.BlobPropertyBag(
          type: widget.result.extension == 'zip'
              ? 'application/zip'
              : 'application/pdf',
        ),
      ),
    );
    _link = web.HTMLAnchorElement()
      ..href = _url
      ..download = widget.name;
  }

  @override
  void dispose() {
    _link.remove();
    web.URL.revokeObjectURL(_url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String css(Color c) => '#${c.toARGB32().toRadixString(16).substring(2)}';
    _link.textContent = tr(context, '다운로드');
    _link.style
      ..backgroundColor = css(colors.primary)
      ..color = css(colors.onPrimary)
      ..borderRadius = '10px'
      ..textAlign = 'center'
      ..textDecoration = 'none'
      ..padding = '12px'
      ..fontSize = '16px'
      ..fontFamily = '-apple-system,BlinkMacSystemFont,sans-serif';
    return NativeControlHost(element: _link, height: 48, width: 150);
  }
}
