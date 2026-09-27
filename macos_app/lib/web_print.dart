import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'cy_localization.dart';

/// 1부터 시작하는 페이지 번호. 중복은 제거하고 원문 순서를 유지한다.
List<int> parsePrintPages(String value, int count) {
  if (count < 1 || value.trim().isEmpty) throw const FormatException();
  final pages = <int>{};
  for (final part
      in value.replaceAll('–', '-').replaceAll('—', '-').split(',')) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(part);
    if (match == null) throw const FormatException();
    final start = int.tryParse(match[1]!);
    final end = int.tryParse(match[2] ?? match[1]!);
    if (start == null ||
        end == null ||
        start < 1 ||
        end < start ||
        end > count) {
      throw const FormatException();
    }
    pages.addAll(List.generate(end - start + 1, (i) => start + i));
  }
  return pages.toList()..sort();
}

/// 원문을 수정하지 않고 선택한 페이지를 벡터 PDF로 복사한다.
Future<Uint8List> createPrintPdf(PdfDocument source, List<int> pages) async {
  if (pages.isEmpty ||
      pages.any((page) => page < 1 || page > source.pages.length)) {
    throw const FormatException('Invalid print pages');
  }
  final copy = await PdfDocument.createNew(sourceName: 'cyviewer-print.pdf');
  try {
    copy.pages = pages.map((page) => source.pages[page - 1]).toList();
    return await copy.encodePdf();
  } finally {
    await copy.dispose();
  }
}

Future<List<int>?> choosePrintPages(
  BuildContext context,
  int count,
  int current,
) => showDialog<List<int>>(
  context: context,
  builder: (_) => PrintRangeDialog(count: count, current: current),
);

class PrintRangeDialog extends StatefulWidget {
  const PrintRangeDialog({
    super.key,
    required this.count,
    required this.current,
  });
  final int count;
  final int current;
  @override
  State<PrintRangeDialog> createState() => _PrintRangeDialogState();
}

class _PrintRangeDialogState extends State<PrintRangeDialog> {
  String _mode = 'all';
  final _range = TextEditingController();
  String? _error;
  bool _submitted = false;
  @override
  void dispose() {
    _range.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    try {
      final pages = switch (_mode) {
        'all' => List.generate(widget.count, (i) => i + 1),
        'current' => [widget.current.clamp(1, widget.count)],
        _ => parsePrintPages(_range.text, widget.count),
      };
      _submitted = true;
      Navigator.pop(context, pages);
    } on FormatException {
      setState(
        () => _error = tr(context, '1~{0} 사이의 페이지를 입력하세요. 예: 2-5, 8', [
          widget.count,
        ]),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, '인쇄 범위')),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(context, '전체 {0}페이지', [widget.count])),
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: _mode,
              onChanged: (value) => setState(() {
                _mode = value!;
                _error = null;
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'all',
                    title: Text(tr(context, '전체 페이지')),
                  ),
                  RadioListTile<String>(
                    value: 'current',
                    title: Text(tr(context, '현재 페이지 ({0})', [widget.current])),
                  ),
                  RadioListTile<String>(
                    value: 'range',
                    title: Text(tr(context, '페이지 직접 지정')),
                  ),
                ],
              ),
            ),
            if (_mode == 'range') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _range,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr(context, '페이지 범위'),
                  hintText: '2-5, 8',
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          if (_submitted) return;
          _submitted = true;
          Navigator.pop(context);
        },
        child: Text(tr(context, '취소')),
      ),
      FilledButton(onPressed: _submit, child: Text(tr(context, '인쇄용 PDF 준비'))),
    ],
  );
}

/// 준비 실패·취소 후 늦게 도착한 결과가 다른 화면을 닫지 않도록
/// 준비 대화상자 자체가 작업의 수명을 소유한다.
Future<Uint8List?> preparePrintPdf(
  BuildContext context,
  Future<Uint8List> Function() prepare, {
  Duration timeout = const Duration(seconds: 45),
}) => showDialog<Uint8List>(
  context: context,
  builder: (_) => _PrintPreparation(prepare: prepare, timeout: timeout),
);

class _PrintPreparation extends StatefulWidget {
  const _PrintPreparation({required this.prepare, required this.timeout});
  final Future<Uint8List> Function() prepare;
  final Duration timeout;
  @override
  State<_PrintPreparation> createState() => _PrintPreparationState();
}

class _PrintPreparationState extends State<_PrintPreparation> {
  Object? _error;
  bool _closed = false;
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final bytes = await Future.sync(widget.prepare).timeout(widget.timeout);
      if (mounted && !_closed && ModalRoute.of(context)?.isCurrent == true) {
        _closed = true;
        Navigator.pop(context, bytes);
      }
    } on Object catch (error) {
      if (mounted && !_closed) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, '인쇄용 PDF 준비')),
    content: _error == null
        ? const SizedBox(
            height: 64,
            child: Center(child: CircularProgressIndicator()),
          )
        : Text(tr(context, '인쇄 창을 열 수 없습니다: {0}', [_error!])),
    actions: [
      TextButton(
        onPressed: () {
          _closed = true;
          Navigator.pop(context);
        },
        child: Text(tr(context, '취소')),
      ),
    ],
  );
}
