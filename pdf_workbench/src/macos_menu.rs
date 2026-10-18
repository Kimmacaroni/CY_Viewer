//! craft-quit의 안전 종료 경로를 사용하는 한국어 macOS 메뉴.
use eframe::egui::Context;
use muda::accelerator::{Accelerator, Code, Modifiers};
use muda::{Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use std::cell::RefCell;

thread_local! {
    static MENU: RefCell<Option<Menu>> = const { RefCell::new(None) };
}

pub fn install(ctx: &Context, name: &str) -> muda::Result<()> {
    if MENU.with_borrow(Option::is_some) {
        return Ok(());
    }
    let quit = MenuItem::with_id(
        craft_quit::QUIT_MENU_ID,
        format!("{name} 종료"),
        true,
        Some(Accelerator::new(Modifiers::META, Code::KeyQ)),
    );
    let app = Submenu::new(name, true);
    app.append_items(&[
        &PredefinedMenuItem::about(Some(&format!("{name} 정보")), None),
        &PredefinedMenuItem::separator(),
        &PredefinedMenuItem::services(Some("서비스")),
        &PredefinedMenuItem::separator(),
        &PredefinedMenuItem::hide(Some(&format!("{name} 가리기"))),
        &PredefinedMenuItem::hide_others(Some("다른 앱 가리기")),
        &PredefinedMenuItem::show_all(Some("모두 표시")),
        &PredefinedMenuItem::separator(),
        &quit,
    ])?;
    let menu = Menu::new();
    menu.append(&app)?;
    menu.init_for_nsapp();
    let ctx = ctx.clone();
    MenuEvent::set_event_handler(Some(move |event: MenuEvent| {
        craft_quit::on_menu_event(&ctx, event.id.as_ref());
    }));
    MENU.set(Some(menu));
    Ok(())
}
