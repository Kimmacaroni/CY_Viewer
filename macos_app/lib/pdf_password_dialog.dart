import 'package:flutter/material.dart';

import 'cy_localization.dart';

/// 암호는 현재 열기 작업의 메모리에서만 사용한다.
class PdfPasswordDialog extends StatefulWidget {
  const PdfPasswordDialog({super.key, required this.name, this.retry = false});
  final String name;
  final bool retry;
  @override
  State<PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<PdfPasswordDialog> {
  final _password = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _open() {
    if (_password.text.isNotEmpty) Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, 'PDF 암호 입력')),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (widget.retry)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    tr(context, '현재 암호가 올바르지 않습니다.'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(labelText: tr(context, '현재 PDF 암호')),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _open(),
            ),
            const SizedBox(height: 12),
            Text(
              tr(context, '암호는 이 문서를 여는 동안만 사용하며 저장하지 않습니다.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, '취소')),
      ),
      FilledButton(
        onPressed: _password.text.isEmpty ? null : _open,
        child: Text(tr(context, '문서 열기')),
      ),
    ],
  );
}
