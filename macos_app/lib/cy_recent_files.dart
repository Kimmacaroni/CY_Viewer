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
    this.favorites = const {},
    this.onFavorite,
    this.showHeading = true,
    this.showResume = true,
  });
  final List<Map<String, dynamic>> files;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<String> onRemove;
  final bool enabled;
  final Set<String> favorites;
  final ValueChanged<String>? onFavorite;
  final bool showHeading, showResume;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showHeading)
        Text(
          tr(context, '최근 열어본 파일'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      if (showHeading) const SizedBox(height: 8),
      if (showHeading) Text(tr(context, '최근 5개 · 이 브라우저에만 저장됨')),
      const SizedBox(height: 12),
      for (final entry in files.take(5).toList().asMap().entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            shape: showResume && entry.key == 0
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showResume && entry.key == 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      tr(context, '이어서 읽기'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    entry.value['name'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: entry.value['openedAt'] is num
                      ? Text(
                          tr(context, '최근 열람 · {0}', [
                            DateTime.fromMillisecondsSinceEpoch(
                              (entry.value['openedAt'] as num).toInt(),
                            ).toLocal().toString().split(' ').first,
                          ]),
                        )
                      : null,
                  onTap: enabled ? () => onOpen(entry.value) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onFavorite != null)
                        IconButton(
                          tooltip: tr(
                            context,
                            favorites.contains(entry.value['id'])
                                ? '즐겨찾기 해제'
                                : '즐겨찾기에 추가',
                          ),
                          onPressed: enabled
                              ? () => onFavorite!(entry.value['id'] as String)
                              : null,
                          icon: Icon(
                            favorites.contains(entry.value['id'])
                                ? Icons.star
                                : Icons.star_border,
                          ),
                        ),
                      IconButton(
                        tooltip: tr(context, '최근 목록에서 제거'),
                        onPressed: enabled
                            ? () => onRemove(entry.value['id'] as String)
                            : null,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
