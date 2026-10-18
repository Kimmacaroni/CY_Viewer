"""PdfCraft 전체 엔진·UI를 고정 소스에서 빌드한다. 원본 로고는 바이너리에 넣지 않는다."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, sys, tarfile, tomllib, urllib.request
ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / 'pdf_workbench/source.json').read_text())
BASE = ROOT / 'build/pdf-workbench'
SOURCE = BASE / 'source'

def download(url, path, digest):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        path.write_bytes(urllib.request.urlopen(url, timeout=120).read())
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f'다운로드 체크섬 불일치: {path.name}')

def replace(path, old, new):
    text = path.read_text()
    if old not in text: raise RuntimeError(f'고정 소스 변경 감지: {path}')
    path.write_text(text.replace(old, new), encoding='utf-8')

def prepare():
    archive = BASE / 'upstream.tar.gz'
    download(f"https://codeload.github.com/storytold/pdfcraft/tar.gz/{CONFIG['revision']}", archive, CONFIG['archive_sha256'])
    stamp = hashlib.sha256(b''.join(p.read_bytes() for p in [Path(__file__), *(ROOT/'pdf_workbench').rglob('*')] if p.is_file())).hexdigest()
    marker = SOURCE / '.cy-source-stamp'
    if marker.exists() and marker.read_text() == stamp:
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
    (SOURCE/'apps/pdfcraft/build.rs').write_text('fn main() {}\n')
    widgets = SOURCE/'crates/ui-egui/src/widgets.rs'
    text = widgets.read_text(); start = text.index('/// The ArtCraft wordmark'); end = text.index('/// Buttons for every community link', start)
    text = text[:start]+'''// 파생 작업실은 원본 상표 이미지를 포함하지 않는다.
pub fn artcraft_logo(ui: &mut egui::Ui, height: f32) -> Response {
    ui.label(egui::RichText::new("CY뷰어").size(height))
}
pub fn artcraft_mark(ui: &mut egui::Ui, size: f32) -> Response {
    ui.label(egui::RichText::new("CY").size(size * 0.6).strong())
}

'''+text[end:];widgets.write_text(text)
    theme = SOURCE/'crates/ui-egui/src/theme.rs'
    replace(theme, '    let fallback: Vec<String> = fonts.families', '''    add(&mut fonts, "CY-Korean", include_bytes!("../../../assets/fonts/CY-NanumGothic.ttf"));
    for stack in fonts.families.values_mut() { stack.push("CY-Korean".to_owned()); }
    let fallback: Vec<String> = fonts.families''')
    i18n = SOURCE/'crates/ui-egui/src/i18n/mod.rs'
    replace(i18n, 'pub static LANGUAGES: [LangInfo; 23] = [', 'pub static LANGUAGES: [LangInfo; 24] = [\n    LangInfo { code: "ko", name: "한국어", source: include_str!("ko.tsv"), plural: plural_none, rtl: false, catalog: OnceLock::new() },')
    shutil.copy2(ROOT/'pdf_workbench/patches/ko.tsv', i18n.parent/'ko.tsv')
    web = SOURCE/'apps/pdfcraft-web/src/main.rs'
    replace(web, 'let mut app = PdfCraftApp::new();', 'let mut app = PdfCraftApp::new();\n                    app.language = "ko".into();\n                    app.set_theme_preference(pdfcraft_ui_egui::theme::ThemePreference::System);')
    replace(SOURCE/'apps/pdfcraft-web/index.html', '<title>PdfCraft</title>', '<title>CY뷰어 PDF 작업실 · PdfCraft</title>')
    # 패키지에는 원본의 상표 이미지가 남지 않는다.
    shutil.rmtree(SOURCE/'docs/brand')
    replace(SOURCE/'crates/ui-egui/src/lib.rs', 'format!("{name} — PdfCraft")', 'format!("{name} — CY뷰어 PDF 작업실")')
    marker.write_text(stamp)
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
    entries=tomllib.loads((src/'ATTRIBUTION.toml').read_text())['fetched']
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
        shutil.copy2(ROOT/'pdf_workbench/web.html',out/'index.html')
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
        notices.append((src/f).read_text())
    notices.append((src/'assets/fonts/CY-NanumGothic.OFL.txt').read_text())
    # 연결되는 Cargo 패키지와 내장 자산의 라이선스 원문도 함께 묶는다.
    meta=json.loads(subprocess.check_output(['cargo','metadata','--locked','--format-version','1','--manifest-path',str(src/'Cargo.toml')],env=env,text=True))
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
        if any(w in f.name.upper() for w in ['LICENSE','OFL','COPYING']): notices.append(f.read_text())
    (out/'THIRD_PARTY_NOTICES.txt').write_text('\n\n'.join(notices),encoding='utf-8')
    print(out)
if __name__=='__main__':main()
