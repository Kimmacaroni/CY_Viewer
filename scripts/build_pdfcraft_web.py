"""고정된 WASM 변환 도구와 PdfCraft 소스로 브라우저 모듈을 만든다."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
VERSION = '0.2.126'
NAME = f'wasm-bindgen-{VERSION}-x86_64-unknown-linux-musl'
SHA256 = '064948d58e2d6c0a745216477a639ba696216d6309aaa902939d1b865b1d869d'
tools = ROOT / 'build' / 'tools'
executable = tools / NAME / 'wasm-bindgen'
if not executable.exists():
    tools.mkdir(parents=True, exist_ok=True)
    archive = tools / (NAME + '.tar.gz')
    urllib.request.urlretrieve(f'https://github.com/wasm-bindgen/wasm-bindgen/releases/download/{VERSION}/{NAME}.tar.gz', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit('WASM 변환 도구의 체크섬이 일치하지 않습니다.')
    with tarfile.open(archive) as package:
        package.extractall(tools, filter='data')
subprocess.run(['rustup', 'target', 'add', 'wasm32-unknown-unknown'], check=True)
environment = dict(os.environ, CY_WASM_BINDGEN=str(executable))
subprocess.run(['python3', str(ROOT / 'scripts' / 'build_pdfcraft.py'), '--web'], env=environment, check=True)
