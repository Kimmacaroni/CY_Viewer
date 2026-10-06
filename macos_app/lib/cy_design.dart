import 'cy_localization.dart';

import 'package:flutter/material.dart';

/// Apple 앱과 웹앱에서 함께 쓰는 문서 작업 공간의 색상·간격·타이포그래피.
abstract final class CyDesign {
  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Color(0xff245edb),
          brightness: brightness,
        ).copyWith(
          primary: dark ? Color(0xffa9c5ff) : Color(0xff245edb),
          onPrimary: dark ? Color(0xff132746) : Colors.white,
          primaryContainer: dark ? Color(0xff223754) : Color(0xffeaf1ff),
          onPrimaryContainer: dark ? Color(0xffcbdcff) : Color(0xff194da8),
          surface: dark ? Color(0xff191f2a) : Colors.white,
          onSurface: dark ? Color(0xffe8edf5) : Color(0xff182235),
          onSurfaceVariant: dark ? Color(0xffacb8ca) : Color(0xff526174),
          outlineVariant: dark ? Color(0xff354154) : Color(0xffdce2eb),
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? Color(0xff10141c) : Color(0xfff4f6f9),
      textTheme: base.textTheme.copyWith(
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(44, 48),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: Size(44, 44),
          shape: shape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: Size(44, 44), shape: shape),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: Size(44, 44)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(color: scheme.onSurface),
        checkmarkColor: scheme.onPrimaryContainer,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

class CyBrand extends StatelessWidget {
  const CyBrand({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/cy_viewer_icon.png',
          width: 30,
          height: 30,
          excludeFromSemantics: true,
        ),
      ),
      SizedBox(width: 10),
      Flexible(
        child: Text(tr(context, "CY뷰어"), overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// 처음 열 때도 문서함 안에서 바로 시작할 수 있는 간결한 빈 상태.
class CyDocumentWelcome extends StatelessWidget {
  const CyDocumentWelcome({super.key, required this.action, required this.web});
  final Widget action;
  final bool web;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.description_outlined,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, "문서를 열고,\n바로 읽으세요."),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                web ? "이 기기에 있는 PDF 파일을 선택하세요." : "PDF를 선택하거나 이 창에 끌어놓으세요.",
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: SizedBox(width: double.infinity, child: action),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              tr(
                context,
                web
                    ? "기본적으로 최근 PDF 5개의 사본을 이 브라우저에 저장합니다.\nDrive를 연결하면 이후 여는 PDF를 개인 Drive에도 저장합니다."
                    : "기본적으로 문서를 이 기기에서 관리합니다.\nDrive를 연결하면 이후 여는 PDF를 개인 Drive에도 저장합니다.",
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 보기 방식은 책갈피 목록과 분리해 직접 선택한다.
Future<int?> cyChooseView(BuildContext context, int selected) =>
    showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr(context, '보기 방식')),
        children: [
          for (final entry in [
            (Icons.view_day_outlined, '세로'),
            (Icons.view_carousel_outlined, '가로'),
            (Icons.menu_book_outlined, '두 쪽'),
          ].asMap().entries)
            ListTile(
              leading: Icon(entry.value.$1),
              title: Text(tr(context, entry.value.$2)),
              selected: entry.key == selected,
              trailing: entry.key == selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, entry.key),
            ),
        ],
      ),
    );

/// 데스크톱의 탐색·편집·저장 순서를 모든 Flutter 리더에서 공유한다.
class CyReaderWorkspace extends StatelessWidget {
  const CyReaderWorkspace({
    super.key,
    required this.child,
    required this.onOpen,
    required this.onSearch,
    required this.onPage,
    required this.onBookmark,
    required this.onTools,
    required this.onSave,
    required this.onPrint,
    required this.onZoomIn,
    required this.onZoomOut,
    this.editing,
    this.exports,
    this.printAction,
    this.onBookmarks,
    this.onView,
    this.onPrevious,
    this.onNext,
    this.pageLabel,
  });
  final Widget child;
  final VoidCallback onOpen,
      onBookmark,
      onTools,
      onSave,
      onPrint,
      onZoomIn,
      onZoomOut;
  final VoidCallback? onSearch, onPage, onBookmarks, onView, onPrevious, onNext;
  final String? pageLabel;
  final Widget? editing, exports, printAction;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1100 &&
      MediaQuery.textScalerOf(context).scale(14) <= 20;

  @override
  Widget build(BuildContext context) {
    if (!isWide(context)) return child;
    final theme = Theme.of(context);
    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 24),
        Text(title, style: theme.textTheme.labelLarge),
        SizedBox(height: 8),
        ...children,
      ],
    );
    Widget action(String label, IconData icon, VoidCallback? callback) =>
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: callback,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );
    return Row(
      children: [
        Container(
          width: 252,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              right: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: ListView(
            padding: EdgeInsets.all(16),
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: onOpen,
                icon: const Icon(Icons.arrow_back),
                label: Text(tr(context, "문서함")),
              ),
              section(tr(context, "01  문서 탐색"), [
                action(
                  tr(context, "이 페이지 책갈피"),
                  Icons.bookmark_border,
                  onBookmark,
                ),
                action(
                  tr(context, "책갈피 목록"),
                  Icons.bookmarks_outlined,
                  onBookmarks ?? onTools,
                ),
                action(
                  tr(context, "보기 방식"),
                  Icons.view_day_outlined,
                  onView ?? onTools,
                ),
              ]),
              section(tr(context, "02  선택·편집"), [
                editing ??
                    Text(
                      tr(context, "문구를 드래그해 선택하고 복사하세요."),
                      style: theme.textTheme.bodySmall,
                    ),
              ]),
              section(tr(context, "03  저장·내보내기"), [
                action(tr(context, "PDF로 저장"), Icons.save_alt, onSave),
                ?exports,
                printAction ??
                    action(tr(context, "인쇄"), Icons.print_outlined, onPrint),
              ]),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: onSearch,
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(tr(context, '문서 검색')),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: tr(context, '이전 페이지'),
                      onPressed: onPrevious,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    TextButton(
                      onPressed: onPage,
                      child: Text(pageLabel ?? tr(context, '페이지 이동')),
                    ),
                    IconButton(
                      tooltip: tr(context, '다음 페이지'),
                      onPressed: onNext,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: tr(context, '축소'),
                      onPressed: onZoomOut,
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: tr(context, '확대'),
                      onPressed: onZoomIn,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mac 문서함의 제목·보관 위치·필터를 웹에서도 동일하게 사용한다.
class CyLibraryToolbar extends StatelessWidget {
  const CyLibraryToolbar({
    super.key,
    required this.detail,
    required this.selected,
    required this.onSelected,
  });
  final String detail;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            tr(context, '문서함'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in const {
            'recent': '최근 열어본 파일',
            'all': '전체 문서',
            'favorites': '즐겨찾기',
          }.entries)
            ChoiceChip(
              avatar: entry.key == 'favorites'
                  ? const Icon(Icons.star_outline, size: 18)
                  : null,
              label: Text(tr(context, entry.value)),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
            ),
        ],
      ),
    ],
  );
}
