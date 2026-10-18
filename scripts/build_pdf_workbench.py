"""PdfCraft 전체 엔진·UI를 고정 소스에서 빌드한다. 원본 로고는 바이너리에 넣지 않는다."""
from pathlib import Path
import argparse, hashlib, inspect, json, os, re, shutil, subprocess, sys, tarfile, tomllib, urllib.request
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')
ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / 'pdf_workbench/source.json').read_text(encoding='utf-8'))
BASE = ROOT / 'build/pdf-workbench'
SOURCE = BASE / 'source'

def download(url, path, digest):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        path.write_bytes(urllib.request.urlopen(url, timeout=120).read())
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f'다운로드 체크섬 불일치: {path.name}')

def replace(path, old, new):
    text = path.read_text(encoding='utf-8')
    if old not in text: raise RuntimeError(f'고정 소스 변경 감지: {path}')
    path.write_text(text.replace(old, new), encoding='utf-8')

def prepare():
    archive = BASE / 'upstream.tar.gz'
    download(f"https://codeload.github.com/storytold/pdfcraft/tar.gz/{CONFIG['revision']}", archive, CONFIG['archive_sha256'])
    inputs = [ROOT/'pdf_workbench/source.json', ROOT/'pdf_workbench/src/main.rs', ROOT/'pdf_workbench/src/macos_menu.rs', ROOT/'pdf_workbench/patches/ko.tsv', ROOT/'pdf_workbench/patches/ko_diagnostics.rs']
    stamp = hashlib.sha256(inspect.getsource(prepare).encode('utf-8') + b''.join(p.read_bytes() for p in inputs)).hexdigest()
    marker = SOURCE / '.cy-source-stamp'
    if marker.exists() and marker.read_text(encoding='utf-8') == stamp:
        return SOURCE
    # 소스나 패치가 바뀌면 원본에서 다시 적용한다.
    if SOURCE.exists(): shutil.rmtree(SOURCE)
    SOURCE.mkdir(parents=True)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            bits = Path(member.name).parts[1:]
            if not bits: continue
            member.name = str(Path(*bits))
            tar.extract(member, SOURCE, filter='data')
    font = SOURCE / 'assets/fonts/CY-NanumGothic.ttf'
    base = f"https://raw.githubusercontent.com/google/fonts/{CONFIG['font_revision']}/ofl/nanumgothic/"
    download(base+'NanumGothic-Regular.ttf', font, CONFIG['font_sha256'])
    download(base+'OFL.txt', font.with_suffix('.OFL.txt'), CONFIG['font_license_sha256'])
    shutil.copy2(ROOT/'pdf_workbench/src/main.rs', SOURCE/'apps/pdfcraft/src/main.rs')
    shutil.copy2(ROOT/'pdf_workbench/src/macos_menu.rs', SOURCE/'apps/pdfcraft/src/macos_menu.rs')
    # 기존 잠금 파일에 있는 muda만 직접 참조해 한국어 메뉴도 안전 종료를 유지한다.
    replace(SOURCE/'apps/pdfcraft/Cargo.toml', 'craft-quit = { workspace = true, features = ["menu"] }', 'craft-quit = { workspace = true, features = ["menu"] }\nmuda = { version = "0.21.2", default-features = false }')
    lock=SOURCE/'Cargo.lock'
    text=lock.read_text(encoding='utf-8');a=text.index('name = "pdfcraft"\n');b=text.index('\n[[package]]',a)
    block=text[a:b].replace(' "log",', ' "log",\n "muda",')
    lock.write_text(text[:a]+block+text[b:],encoding='utf-8')
    (SOURCE/'apps/pdfcraft/build.rs').write_text('fn main() {}\n',encoding='utf-8')
    widgets = SOURCE/'crates/ui-egui/src/widgets.rs'
    text = widgets.read_text(encoding='utf-8'); start = text.index('/// The ArtCraft wordmark'); end = text.index('/// Buttons for every community link', start)
    text = text[:start]+'''// 파생 작업실은 원본 상표 이미지를 포함하지 않는다.
pub fn artcraft_logo(ui: &mut egui::Ui, height: f32) -> Response {
    ui.label(egui::RichText::new("CY뷰어").size(height))
}
pub fn artcraft_mark(ui: &mut egui::Ui, size: f32) -> Response {
    ui.label(egui::RichText::new("CY").size(size * 0.6).strong())
}

'''+text[end:];widgets.write_text(text,encoding='utf-8')
    theme = SOURCE/'crates/ui-egui/src/theme.rs'
    replace(theme, '    let fallback: Vec<String> = fonts.families', '''    add(&mut fonts, "CY-Korean", include_bytes!("../../../assets/fonts/CY-NanumGothic.ttf"));
    for stack in fonts.families.values_mut() { stack.push("CY-Korean".to_owned()); }
    let fallback: Vec<String> = fonts.families''')
    i18n = SOURCE/'crates/ui-egui/src/i18n/mod.rs'
    replace(i18n, 'pub static LANGUAGES: [LangInfo; 23] = [', 'pub static LANGUAGES: [LangInfo; 24] = [\n    LangInfo { code: "ko", name: "한국어", source: include_str!("ko.tsv"), plural: plural_none, rtl: false, catalog: OnceLock::new() },')
    shutil.copy2(ROOT/'pdf_workbench/patches/ko.tsv', i18n.parent/'ko.tsv')
    replace(i18n, 'mod catalog;', 'mod catalog;\npub mod cy_korean;')
    shutil.copy2(ROOT/'pdf_workbench/patches/ko_diagnostics.rs',i18n.parent/'cy_korean.rs')
    wordings=set()
    for path in (SOURCE/'crates').glob('*/src/**/*.rs'):
        for match in re.finditer(r'#\[error\(\s*"((?:\\.|[^"\\])*)"',path.read_text(encoding='utf-8')):
            wordings.add(json.loads('"'+match[1]+'"'))
    (i18n.parent/'cy_error_templates.rs').write_text('&'+json.dumps(sorted(wordings),ensure_ascii=False),encoding='utf-8')
    lib=SOURCE/'crates/ui-egui/src/lib.rs'
    replace(lib, 'self.notify(error.to_string());', 'self.notify(i18n::cy_korean::diagnostic(&error.to_string()));')
    replace(lib, 'self.notify(i18n::fmt(tl!(template), args));', '''let failure = ["Couldn't", "failed", "could not", "not applied", "Can't", "cannot"].iter().any(|part| template.contains(part));
        let values: Vec<String> = args.iter().map(|(key, value)| {
            if failure && matches!(*key, "e" | "error" | "reason" | "why") { i18n::cy_korean::diagnostic(value) }
            else { (*value).to_owned() }
        }).collect();
        let localized: Vec<(&str, &str)> = args.iter().zip(values.iter()).map(|((key, _), value)| (*key, value.as_str())).collect();
        self.notify(i18n::fmt(tl!(template), &localized));''')
    for name,old,new in [
        ('word_count_ui.rs','ui.label(error.to_string());','ui.label(crate::i18n::cy_korean::diagnostic(&error.to_string()));'),
        ('word_count_ui.rs','ui.colored_label(ui.visuals().error_fg_color, error);','ui.colored_label(ui.visuals().error_fg_color, crate::i18n::cy_korean::diagnostic(&error.to_string()));'),
        ('measure_ui.rs','ui.colored_label(Color32::from_rgb(190, 50, 50), error);','ui.colored_label(Color32::from_rgb(190, 50, 50), crate::i18n::cy_korean::diagnostic(&error.to_string()));'),
        ('page_selection_ui.rs','ui.label(error);','ui.label(crate::i18n::cy_korean::diagnostic(&error.to_string()));'),
    ]:
        replace(SOURCE/'crates/ui-egui/src'/name,old,new)
    web = SOURCE/'apps/pdfcraft-web/src/main.rs'
    replace(web, 'let mut app = PdfCraftApp::new();', 'let mut app = PdfCraftApp::new();\n                    app.language = "ko".into();\n                    app.set_theme_preference(pdfcraft_ui_egui::theme::ThemePreference::System);')
    replace(web, '                    // `?file=<url>`', '                    app.language = "ko".into();\n                    // `?file=<url>`')
    replace(SOURCE/'apps/pdfcraft-web/index.html', '<title>PdfCraft</title>', '<title>CY뷰어 PDF 작업실 · PdfCraft</title>')
    home=SOURCE/'crates/ui-egui/src/home.rs'
    text=home.read_text(encoding='utf-8');a=text.index('            egui::Frame::NONE');b=text.index('            ui.add_space(22.0);',a)
    text=text[:a]+'''            ui.label("PdfCraft · ArtCraft Team 및 PdfCraft 기여자 · MIT");
            ui.hyperlink_to("원본 소스·라이선스", "https://github.com/storytold/pdfcraft");
'''+text[b:];home.write_text(text,encoding='utf-8')
    chrome=SOURCE/'crates/ui-egui/src/chrome.rs'
    text=chrome.read_text(encoding='utf-8');a=text.index('                    // One click to the community');b=text.index('                });',a)
    text=text[:a]+text[b:];chrome.write_text(text,encoding='utf-8')
    replace(SOURCE/'crates/ui-egui/src/updates.rs', 'https://github.com/storytold/pdfcraft/releases', 'https://github.com/Kimmacaroni/CY_Viewer/releases')
    text=chrome.read_text(encoding='utf-8');start=text.index('pub fn mode_bar(');needle='            ui.horizontal_centered(|ui| {';at=text.index(needle,start)
    text=text[:at]+'''            let compact = ui.available_width() < 700.0;
            let compact_id = egui::Id::new("cy_compact_workbench");
            let was_compact = ui.ctx().data(|d| d.get_temp::<bool>(compact_id).unwrap_or(false));
            if compact && !was_compact { app.left_open = false; app.choose_right_panel(None); }
            ui.ctx().data_mut(|d| d.insert_temp(compact_id, compact));
            if compact {
                ui.horizontal_centered(|ui| {
                    main_menu(app, ui);
                    if ui.add(egui::Button::new("도구 찾기").min_size(vec2(80.0, 44.0))).clicked() { app.palette_open = true; }
                    if ui.add(egui::Button::new("패널").min_size(vec2(44.0, 44.0))).clicked() {
                        if app.left_open || app.right.is_some() { app.left_open = false; app.choose_right_panel(None); }
                        else { app.left_open = true; }
                    }
                    if ui.add_enabled(app.active.is_some(), egui::Button::new(tl!("Save")).min_size(vec2(44.0, 44.0))).clicked() { app.run_command("file.save"); }
                });
                return;
            }
'''+text[at:];chrome.write_text(text,encoding='utf-8')
    replace(SOURCE/'crates/ui-egui/src/palette.rs', 'ui.set_width(560.0);', 'ui.set_width((screen.width() - 40.0).clamp(200.0, 560.0));')
    replace(SOURCE/'crates/ui-egui/src/palette.rs', 'vec2(ui.available_width(), 36.0)', 'vec2(ui.available_width(), if screen.width() < 700.0 { 44.0 } else { 36.0 })')
    replace(web, 'warn_before_unload(app.unsaved_flag.clone());', '''warn_before_unload(app.unsaved_flag.clone());
                    if web_sys::window().and_then(|w| w.inner_width().ok()).and_then(|w| w.as_f64()).is_some_and(|w| w < 700.0) {
                        app.left_open = false;
                        app.choose_right_panel(None);
                    }''')
    # 패키지에는 원본의 상표 이미지가 남지 않는다.
    shutil.rmtree(SOURCE/'docs/brand')
    replace(SOURCE/'crates/ui-egui/src/lib.rs', 'format!("{name} — PdfCraft")', 'format!("{name} — CY뷰어 PDF 작업실")')
    marker.write_text(stamp,encoding='utf-8')
    return SOURCE

def wasm_tool():
    # 원본 Cargo.lock의 wasm-bindgen 0.2.129와 일치하는 Linux 변환 도구.
    name='wasm-bindgen-0.2.129-x86_64-unknown-linux-musl'
    folder=ROOT/'build/tools'
    archive=folder/(name+'.tar.gz')
    download('https://github.com/wasm-bindgen/wasm-bindgen/releases/download/0.2.129/'+name+'.tar.gz',archive,'82d12bb940e2d4e72e0d5605387fc1b8ca179044e012b620f0ce4e7440e8320e')
    with tarfile.open(archive) as tar: tar.extractall(folder,filter='data')
    return str(folder/name/'wasm-bindgen')

def models(src, out):
    entries=tomllib.loads((src/'ATTRIBUTION.toml').read_text(encoding='utf-8'))['fetched']
    dest=out/'models';dest.mkdir(parents=True,exist_ok=True)
    for item in entries:
        if item.get('file') not in ['text-detection.rten','text-recognition.rten']: continue
        download(item['url'],dest/item['file'],item['sha256'])
        licence=ROOT/'pdf_workbench/CC-BY-SA-4.0.txt'
        if hashlib.sha256(licence.read_bytes()).hexdigest() != item['licence_sha256']: raise RuntimeError('OCR 모델 라이선스 체크섬 불일치')
        shutil.copy2(licence,dest/'CC-BY-SA-4.0.txt')
    (dest/'NOTICE.txt').write_text('Ocrs models — Robert Knight (ocrs-models), CC-BY-SA-4.0.\nhttps://github.com/robertknight/ocrs-models\nEnglish text recognition; models are redistributed unmodified.\n',encoding='utf-8')

def main():
    p=argparse.ArgumentParser();p.add_argument('--prepare', action='store_true');p.add_argument('--web', action='store_true');a=p.parse_args()
    src=prepare()
    if a.prepare: print(src);return
    env=dict(os.environ, CARGO_TARGET_DIR=str(BASE/'target'))
    if a.web:
        # 잠긴 의존성에서 변환 도구 버전도 결정한다.
        subprocess.run(['cargo','build','--release','--locked','-p','pdfcraft-web','--target','wasm32-unknown-unknown'],cwd=src,env=env,check=True)
        out=ROOT/'macos_app/web/pdf-workbench';out.mkdir(parents=True,exist_ok=True)
        subprocess.run([wasm_tool(),str(BASE/'target/wasm32-unknown-unknown/release/pdfcraft-web.wasm'),'--target','web','--out-dir',str(out),'--out-name','workbench','--no-typescript'],check=True)
        html=(ROOT/'pdf_workbench/web.html').read_text(encoding='utf-8').replace('__CY_WORKBENCH_BUILD__',(src/'.cy-source-stamp').read_text(encoding='utf-8'))
        (out/'index.html').write_text(html,encoding='utf-8')
        shutil.copy2(src/'assets/fonts/CY-NanumGothic.ttf',out/'CY-NanumGothic.ttf')
    else:
        out=BASE/'bin';out.mkdir(parents=True,exist_ok=True)
        name='cy-pdf-workbench'+('.exe' if os.name=='nt' else '')
        if sys.platform=='darwin':
            targets=['aarch64-apple-darwin','x86_64-apple-darwin']
            subprocess.run(['rustup','target','add',*targets],check=True)
            for target in targets:
                subprocess.run(['cargo','build','--release','--locked','-p','pdfcraft','--target',target],cwd=src,env=env,check=True)
            subprocess.run(['lipo','-create',*[str(BASE/'target'/t/'release/pdfcraft') for t in targets],'-output',str(out/name)],check=True)
        else:
            subprocess.run(['cargo','build','--release','--locked','-p','pdfcraft'],cwd=src,env=env,check=True)
            shutil.copy2(BASE/'target/release'/('pdfcraft'+('.exe' if os.name=='nt' else '')),out/name)
    if not a.web: models(src,out)
    notices=[CONFIG['copyright'], 'PdfCraft 전체 소스: '+CONFIG['repository']+'\nrevision: '+CONFIG['revision']]
    for f in ['LICENSE-MIT','LICENSE-APACHE','NOTICE','ATTRIBUTION.md']:
        notices.append((src/f).read_text(encoding='utf-8'))
    notices.append((src/'assets/fonts/CY-NanumGothic.OFL.txt').read_text(encoding='utf-8'))
    # 연결되는 Cargo 패키지와 내장 자산의 라이선스 원문도 함께 묶는다.
    meta=json.loads(subprocess.check_output(['cargo','metadata','--locked','--format-version','1','--manifest-path',str(src/'Cargo.toml')],env=env,text=True,encoding='utf-8'))
    seen=set()
    for package in meta['packages']:
        directory=Path(package['manifest_path']).parent
        for f in sorted(directory.rglob('*')):
            if f.is_file() and f.name.upper().startswith(('LICENSE','LICENCE','COPYING','NOTICE','OFL','UFL')) and 'target' not in f.parts:
                digest=hashlib.sha256(f.read_bytes()).hexdigest()
                if digest in seen: continue
                seen.add(digest)
                try: text=f.read_text(encoding='utf-8')
                except UnicodeDecodeError: continue
                notices.append(package['name']+' '+package['version']+' / '+str(f.relative_to(directory))+'\n'+text)
    for f in (src/'assets').rglob('*.txt'):
        if any(w in f.name.upper() for w in ['LICENSE','OFL','COPYING']): notices.append(f.read_text(encoding='utf-8'))
    (out/'THIRD_PARTY_NOTICES.txt').write_text('\n\n'.join(notices),encoding='utf-8')
    print(out)
if __name__=='__main__':main()
