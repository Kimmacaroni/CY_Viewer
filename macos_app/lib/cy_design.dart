import 'package:flutter/material.dart';

/// Apple 앱과 웹앱에서 함께 쓰는 문서 작업 공간의 색상·간격·타이포그래피.
abstract final class CyDesign {
  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff245edb),
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xffa9c5ff) : const Color(0xff245edb),
          onPrimary: dark ? const Color(0xff132746) : Colors.white,
          primaryContainer: dark
              ? const Color(0xff223754)
              : const Color(0xffeaf1ff),
          onPrimaryContainer: dark
              ? const Color(0xffcbdcff)
              : const Color(0xff194da8),
          surface: dark ? const Color(0xff191f2a) : Colors.white,
          onSurface: dark ? const Color(0xffe8edf5) : const Color(0xff182235),
          onSurfaceVariant: dark
              ? const Color(0xffacb8ca)
              : const Color(0xff526174),
          outlineVariant: dark
              ? const Color(0xff354154)
              : const Color(0xffdce2eb),
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark
          ? const Color(0xff10141c)
          : const Color(0xfff4f6f9),
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
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(44, 44),
          shape: shape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: shape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
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
      const SizedBox(width: 10),
      const Text('CY뷰어'),
    ],
  );
}

/// 빈 문서함에서도 열기 → 탐색 → 저장 흐름을 알려 주는 공통 시작 화면.
class CyDocumentWelcome extends StatelessWidget {
  const CyDocumentWelcome({super.key, required this.action, required this.web});
  final Widget action;
  final bool web;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 760 &&
            MediaQuery.textScalerOf(context).scale(14) < 21;
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '문서 작업 공간',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text('문서를 열고,\n바로 읽으세요.', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(
              web
                  ? '설치 없이, 파일 하나로 시작하세요.\n필요한 문구를 찾고 중요한 페이지를 남겨 보세요.'
                  : '최근 문서와 읽던 페이지를 한곳에서.\nPDF를 선택하거나 이 창에 끌어놓으세요.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            _Feature(
              icon: Icons.search,
              title: '찾고 읽기',
              description: '문서 검색 · 확대 · 보기 방식 변경',
            ),
            const SizedBox(height: 16),
            _Feature(
              icon: Icons.bookmark_border,
              title: '중요한 페이지 남기기',
              description: '책갈피로 필요한 곳을 빠르게 찾기',
            ),
            const SizedBox(height: 16),
            _Feature(
              icon: Icons.ios_share_outlined,
              title: web ? '저장하고 공유하기' : '표시하고 저장하기',
              description: web
                  ? 'PDF 사본 저장 · 공유 · 인쇄'
                  : '텍스트 표시 · OCR · PDF와 이미지 저장',
            ),
          ],
        );
        final panel = Card(
          child: Padding(
            padding: EdgeInsets.all(wide ? 32 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      size: 36,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('어떤 문서를 읽을까요?', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(web ? '이 기기에 있는 PDF 파일을 선택하세요.' : '파일을 선택하면 문서함에 추가됩니다.'),
                const SizedBox(height: 24),
                action,
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        web
                            ? '문서는 서버로 전송되지 않습니다.\n웹앱을 닫으면 PDF 원본은 남지 않습니다.'
                            : '문서와 최근 열람 목록은\n이 기기에서만 관리합니다.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: intro),
                  const SizedBox(width: 56),
                  Expanded(child: panel),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [panel, const SizedBox(height: 32), intro],
              );
      },
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

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
  });
  final Widget child;
  final VoidCallback onOpen,
      onBookmark,
      onTools,
      onSave,
      onPrint,
      onZoomIn,
      onZoomOut;
  final VoidCallback? onSearch, onPage;
  final Widget? editing, exports;

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
        const SizedBox(height: 24),
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        ...children,
      ],
    );
    Widget action(String label, IconData icon, VoidCallback? callback) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
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
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.add),
                label: const Text('PDF 열기'),
              ),
              section('01  문서 탐색', [
                action('문서 검색', Icons.search, onSearch),
                action('페이지 이동', Icons.find_in_page_outlined, onPage),
                action('이 페이지 책갈피', Icons.bookmark_border, onBookmark),
                Row(
                  children: [
                    Expanded(child: action('축소', Icons.remove, onZoomOut)),
                    const SizedBox(width: 8),
                    Expanded(child: action('확대', Icons.add, onZoomIn)),
                  ],
                ),
                action('보기 방식 · 책갈피 목록', Icons.tune, onTools),
              ]),
              section('02  선택·편집', [
                editing ??
                    Text(
                      '문구를 드래그해 선택하고 복사하세요.',
                      style: theme.textTheme.bodySmall,
                    ),
              ]),
              section('03  저장·내보내기', [
                action('PDF로 저장', Icons.save_alt, onSave),
                ?exports,
                action('인쇄', Icons.print_outlined, onPrint),
              ]),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
