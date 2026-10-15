"""PdfCraft 페이지 엔진의 로컬 실행과 결과 검증."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import pymupdf


def helper_path() -> Path:
    root = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parent.parent))
    return root / 'pdfcraft' / 'cy-pdfcraft.exe' if getattr(sys, 'frozen', False) else root / 'build' / 'pdfcraft' / ('cy-pdfcraft.exe' if os.name == 'nt' else 'cy-pdfcraft')


def parse_pages(text: str, count: int) -> list[int]:
    """입력한 순서를 유지하며 중복·범위 밖 페이지를 거부한다."""
    pages: list[int] = []
    if not text.strip() or len(text) > 100_000:
        raise ValueError('페이지 범위를 입력하세요.')
    for part in text.split(','):
        ends = part.strip().split('-')
        if len(ends) not in (1, 2) or any(not e.strip().isascii() or not e.strip().isdigit() for e in ends):
            raise ValueError('페이지 범위는 1-3, 5 형식으로 입력하세요.')
        first, last = int(ends[0]), int(ends[-1])
        if not 1 <= first <= last <= count:
            raise ValueError(f'페이지는 1부터 {count}까지 선택하세요. 순서는 3, 1, 2처럼 지정하세요.')
        pages.extend(range(first, last + 1))
        if len(pages) > 100_000:
            raise ValueError('한 번에 선택할 수 있는 페이지가 너무 많습니다.')
    if len(set(pages)) != len(pages):
        raise ValueError('같은 페이지를 두 번 선택할 수 없습니다.')
    return pages


def compose_pdf(snapshot: bytes, title: str, pages: str, additions: list[Path], helper: Path | None = None) -> bytes:
    executable = helper or helper_path()
    if not executable.is_file():
        raise RuntimeError('페이지 처리 모듈이 없습니다. 최신 CY뷰어 설치 파일로 다시 설치하세요.')
    with tempfile.TemporaryDirectory(prefix='cy-pages-') as directory:
        root = Path(directory)
        source = root / 'source.pdf'
        source.write_bytes(snapshot)
        sources = [{'path': str(source), 'title': title, 'pages': pages}]
        # 원본 경로와 별개의 사본을 사용한다. 미저장 편집은 snapshot에 포함된다.
        for i, path in enumerate(additions):
            if path.stat().st_size > 256 * 1024 * 1024:
                raise ValueError('한 파일은 256MB까지 처리할 수 있습니다.')
            copy = root / f'added-{i}.pdf'
            copy.write_bytes(path.read_bytes())
            sources.append({'path': str(copy), 'title': path.name, 'pages': None})
        output = root / 'result.pdf'
        result = subprocess.run([str(executable)], input=json.dumps({'sources': sources, 'output': str(output)}, ensure_ascii=False).encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if result.returncode:
            raise RuntimeError(result.stderr.decode('utf-8', errors='replace').strip()[:2000] or 'PDF를 처리하지 못했습니다.')
        expected = json.loads(result.stdout)['pages']
        data = output.read_bytes()
        with pymupdf.open(stream=data, filetype='pdf') as document:
            if len(document) != expected or expected < 1:
                raise RuntimeError('결과 PDF의 페이지 수가 일치하지 않습니다.')
        return data


def save_copy(data: bytes, destination: Path, originals: list[Path]) -> None:
    """입력 원본을 보호하고 검증된 PDF를 같은 폴더에서 원자적으로 교체한다."""
    for source in originals:
        if destination.resolve() == source.resolve() or (destination.exists() and source.exists() and os.path.samefile(destination, source)):
            raise ValueError('원본과 다른 이름으로 저장하세요.')
    staging: str | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.cy-pages-', suffix='.pdf', delete=False) as file:
            staging = file.name
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.replace(staging, destination)
    finally:
        if staging and Path(staging).exists():
            Path(staging).unlink()


def tools_request(snapshot: bytes, title: str, options: dict, password: str = '', helper: Path | None = None) -> tuple[dict, bytes]:
    """문서 검사 또는 편집을 실행한다. 분할 결과는 ZIP으로 묶는다."""
    import zipfile
    import io
    executable = helper or helper_path()
    if not executable.is_file():
        raise RuntimeError('페이지 처리 모듈이 없습니다. 최신 CY뷰어 설치 파일로 다시 설치하세요.')
    with tempfile.TemporaryDirectory(prefix='cy-tools-') as directory:
        root = Path(directory)
        source = root / 'source.pdf'
        source.write_bytes(snapshot)
        request = dict(options)
        request.update({'sources': [{'path': str(source), 'title': title, 'password': password or None}], 'output': str(root / 'result.pdf')})
        result = subprocess.run([str(executable)], input=json.dumps(request, ensure_ascii=False).encode('utf-8'), capture_output=True, timeout=180, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if result.returncode:
            raise RuntimeError(result.stderr.decode('utf-8', errors='replace').strip()[:2000])
        report = json.loads(result.stdout)
        if options.get('inspect'):
            return report, b''
        outputs = []
        for info in report['files']:
            path = Path(info['path'])
            if path.parent.resolve() != root.resolve():
                raise RuntimeError('결과 파일 경로가 올바르지 않습니다.')
            data = path.read_bytes()
            with pymupdf.open(stream=data, filetype='pdf') as doc:
                if doc.needs_pass and not doc.authenticate(options.get('new_password', '')):
                    raise RuntimeError('결과 PDF의 암호를 확인할 수 없습니다.')
                if len(doc) != info['pages']:
                    raise RuntimeError('결과 PDF의 페이지 수가 일치하지 않습니다.')
            outputs.append(data)
        if options.get('split_every') is not None:
            archive = io.BytesIO()
            with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as output:
                for index, data in enumerate(outputs):
                    output.writestr(f'part-{index+1:03}.pdf', data)
            return report, archive.getvalue()
        return report, outputs[0]
