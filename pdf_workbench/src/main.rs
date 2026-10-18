//! 원본 전체 편집 화면을 CY뷰어의 독립 작업실 창으로 실행한다.
#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]
use pdfcraft_ui_egui::PdfCraftApp;
fn main() -> eframe::Result {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--version") {
        println!("CY뷰어 PDF 작업실 0.1.0 · PdfCraft 0.9.0 · ArtCraft Team");
        return Ok(());
    }
    let initial = args.first().map(std::path::PathBuf::from);
    let options = eframe::NativeOptions {
        renderer: eframe::Renderer::Glow,
        viewport: eframe::egui::ViewportBuilder::default().with_inner_size([1200.0, 850.0]).with_min_inner_size([760.0, 560.0]),
        ..Default::default()
    };
    eframe::run_native("CY뷰어 PDF 작업실", options, Box::new(move |cc| {
        let mut app = PdfCraftApp::new();
        app.language = "ko".into();
        app.set_theme_preference(pdfcraft_ui_egui::theme::ThemePreference::System);
        if let Some(path) = initial {
            match std::fs::read(&path) {
                Ok(bytes) => {
                    let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("document.pdf");
                    // 원본 경로를 편집기에 넘기지 않아 첫 저장은 새 파일 선택이다.
                    if let Err(error) = app.open_bytes(name, None, bytes) { app.notify_error(error); }

                }
                Err(error) => app.notify_error(error),
            }
        }
        app.enable_desktop_theme();
        cc.egui_ctx.request_repaint();
        Ok(Box::new(app))
    }))
}
