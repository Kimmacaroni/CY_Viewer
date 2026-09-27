import 'package:flutter/material.dart';

import 'cy_localization.dart';

/// 파일명 중심의 최근 문서 목록. 보관 원본과 작업 중인 문서를 혼동하지 않는다.
class CyRecentFiles extends StatelessWidget {
  const CyRecentFiles({
    super.key,
    required this.files,
    required this.onOpen,
    required this.onRemove,
    this.enabled = true,
  });
  final List<Map<String, dynamic>> files;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<String> onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr(context, '최근 열어본 파일'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(tr(context, '최근 5개 · 이 브라우저에만 저장됨')),
      const SizedBox(height: 12),
      for (final row in files.take(5))
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(
              row['name'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: enabled ? () => onOpen(row) : null,
            trailing: IconButton(
              tooltip: tr(context, '최근 목록에서 제거'),
              onPressed: enabled ? () => onRemove(row['id'] as String) : null,
              icon: const Icon(Icons.close),
            ),
          ),
        ),
    ],
  );
}
