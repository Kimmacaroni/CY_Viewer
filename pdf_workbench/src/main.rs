//! 원본 전체 편집 화면을 CY뷰어의 독립 작업실 창으로 실행한다.
#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]
use pdfcraft_ui_egui::PdfCraftApp;
use std::path::PathBuf;

fn main() -> eframe::Result {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--version") {
        println!("CY뷰어 PDF 작업실 0.1.0 · PdfCraft 0.9.0 · ArtCraft Team");
        return Ok(());
    }
    let initial = args.first().map(PathBuf::from);
    // 원본과 같이 현대 GPU 경로를 먼저 쓰고 OpenGL로 복구한다.
    launch(eframe::Renderer::Wgpu, initial.clone()).or_else(|error| {
        eprintln!("기본 그래픽 경로를 시작하지 못해 OpenGL로 다시 엽니다: {error}");
        launch(eframe::Renderer::Glow, initial)
    })
}

fn launch(renderer: eframe::Renderer, initial: Option<PathBuf>) -> eframe::Result {
    let options = eframe::NativeOptions {
        renderer,
        viewport: eframe::egui::ViewportBuilder::default()
            .with_inner_size([1200.0, 850.0])
            .with_min_inner_size([760.0, 560.0]),
        ..Default::default()
    };
    eframe::run_native(
        "CY뷰어 PDF 작업실",
        options,
        Box::new(move |cc| {
            let mut app = PdfCraftApp::new();
            app.language = "ko".into();
            app.set_theme_preference(pdfcraft_ui_egui::theme::ThemePreference::System);
            if let Some(saved) = cc.storage.and_then(|s| s.get_string("pdfcraft")) {
                app.restore(&saved);
            }
            if let Some(path) = initial {
                match std::fs::read(&path) {
                    Ok(bytes) => {
                        let name = path
                            .file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or("document.pdf");
                        // 원본 경로를 편집기에 넘기지 않아 첫 저장은 새 파일 선택이다.
                        if let Err(error) = app.open_bytes(name, None, bytes) {
                            app.notify_error(error);
                        }
                    }
                    Err(error) => app.notify_error(error),
                }
            }
            #[cfg(target_os = "linux")]
            app.enable_desktop_theme();
            #[cfg(target_os = "macos")]
            if let Err(error) = craft_quit::install_app_menu(&cc.egui_ctx, "CY뷰어 PDF 작업실")
            {
                app.notify_error(format!(
                    "종료 메뉴를 준비하지 못했습니다. 창의 닫기 버튼을 사용하세요: {error}"
                ));
            }
            cc.egui_ctx.request_repaint();
            Ok(Box::new(app))
        }),
    )
}
