import 'pdfcraft_models.dart';
import 'pdf_workbench_native.dart'
    if (dart.library.js_interop) 'pdf_workbench_browser.dart'
    as platform;

/// 전체 PdfCraft 엔진과 편집 화면을 별도의 문서 사본으로 연다.
Future<PdfcraftResult?> openPdfWorkbench(PdfcraftSource source) =>
    platform.openPdfWorkbench(source);
