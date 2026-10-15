"""고정된 PdfCraft 소스로 실행 모듈과 의존성 라이선스 묶음을 만든다."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'pdfcraft_bridge' / 'Cargo.toml'
WEB = '--web' in sys.argv
OUT = ROOT / 'macos_app' / 'web' / 'pdfcraft' if WEB else ROOT / 'build' / 'pdfcraft'
OUT.mkdir(parents=True, exist_ok=True)

def cargo(command, *args):
    subprocess.run(['cargo', command, '--manifest-path', str(MANIFEST), *args], check=True)

host = next(line.split(': ', 1)[1] for line in subprocess.check_output(['rustc', '-vV'], text=True).splitlines() if line.startswith('host: '))
notice_targets = ['wasm32-unknown-unknown'] if WEB else (['aarch64-apple-darwin', 'x86_64-apple-darwin'] if sys.platform == 'darwin' else [host])
cargo('test', '--locked')
if WEB:
    cargo('build', '--locked', '--release', '--lib', '--target', 'wasm32-unknown-unknown')
    subprocess.run([os.environ.get('CY_WASM_BINDGEN', 'wasm-bindgen'), str(ROOT / 'pdfcraft_bridge' / 'target' / 'wasm32-unknown-unknown' / 'release' / 'cy_pdfcraft.wasm'), '--target', 'no-modules', '--no-typescript', '--out-dir', str(OUT)], check=True)
elif sys.platform == 'darwin':
    targets = ['aarch64-apple-darwin', 'x86_64-apple-darwin']
    subprocess.run(['rustup', 'target', 'add', *targets], check=True)
    for target in targets:
        cargo('build', '--locked', '--release', '--target', target)
    subprocess.run(['lipo', '-create', *(str(ROOT / 'pdfcraft_bridge' / 'target' / t / 'release' / 'cy-pdfcraft') for t in targets), '-output', str(OUT / 'cy-pdfcraft')], check=True)
else:
    cargo('build', '--locked', '--release')
    suffix = '.exe' if os.name == 'nt' else ''
    shutil.copy2(ROOT / 'pdfcraft_bridge' / 'target' / 'release' / f'cy-pdfcraft{suffix}', OUT)

# 배포 대상에 실제 연결되는 의존성만 고지한다. UEFI 등 미사용 대상은 제외한다.
metadatas = [json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--format-version', '1', '--filter-platform', target, '--manifest-path', str(MANIFEST)], text=True, encoding='utf-8')) for target in notice_targets]
metadata = metadatas[0]
resolved = {n['id'] for data in metadatas for n in data['resolve']['nodes']}
sections = ['CY뷰어 페이지 처리 모듈 — 제3자 라이선스\nPdfCraft: https://github.com/storytold/pdfcraft\n고정 커밋: d9607ec3befcda3e78062ceb5e54b97563aedad1\nPdfCraft 코드는 MIT 조건으로 사용하며 ArtCraft 브랜드·자산은 포함하지 않습니다.\n']
for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
    if package['id'] not in resolved or package['source'] is None:
        continue
    directory = Path(package['manifest_path']).parent
    # PdfCraft의 각 crate 라이선스는 저장소 최상단에 있다.
    candidates = [directory]
    if package['name'].startswith('pdfcraft-'):
        candidates.append(directory.parent.parent)
    files = []
    for folder in candidates:
        files.extend(p for p in folder.iterdir() if p.is_file() and p.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE', 'COPYRIGHT')))
    if not files:
        raise SystemExit(f"라이선스 파일이 없습니다: {package['name']}")
    sections.append(f"\n{'=' * 70}\n{package['name']} {package['version']}\n{package.get('license')}\n{package.get('repository')}\n")
    for file in sorted(set(files)):
        sections.append(f'\n--- {file.name} ---\n' + file.read_text(encoding='utf-8'))
(OUT / 'THIRD_PARTY_NOTICES.txt').write_text('\n'.join(sections), encoding='utf-8')
print(f'실행 모듈과 라이선스: {OUT}')
