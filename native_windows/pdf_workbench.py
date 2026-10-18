"""원본 경로를 노출하지 않고 PdfCraft 전체 작업실을 문서 사본으로 실행한다."""
from pathlib import Path
import subprocess, sys, tempfile, threading

def launch_workbench(snapshot: bytes, title: str) -> None:
    root = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parent.parent))
    helper = root / 'pdfcraft' / 'cy-pdf-workbench.exe'
    if not helper.is_file():
        helper = root / 'build/pdf-workbench/bin/cy-pdf-workbench.exe'
    if not helper.is_file():
        raise RuntimeError('PDF 작업실 모듈이 없습니다. 최신 CY뷰어를 설치해 주세요.')
    folder = tempfile.TemporaryDirectory(prefix='cy-workbench-')
    try:
        source = Path(folder.name) / Path(title).name
        source.write_bytes(snapshot)
        process = subprocess.Popen([str(helper), str(source)], creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    except Exception:
        folder.cleanup()
        raise
    def cleanup():
        process.wait()
        folder.cleanup()
    threading.Thread(target=cleanup, daemon=True).start()
