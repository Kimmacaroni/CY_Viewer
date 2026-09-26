"""Windows 배포 전 시작 화면과 실제 PDF 열기·탐색을 검증한다."""
from pathlib import Path
import sys
import tempfile
from tkinter import messagebox

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pymupdf
from cy_viewer import CyViewer


def fail_dialog(title, message, **kwargs):
    raise AssertionError(f"{title}: {message}")


messagebox.showerror = fail_dialog
app = CyViewer()
try:
    app.update()
    assert app.welcome.winfo_ismapped()
    assert not app.workspace.winfo_ismapped()
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "smoke.pdf"
        with pymupdf.open() as pdf:
            for number in range(2):
                pdf.new_page().insert_text((72, 72), f"CYViewer page {number + 1}")
            pdf.save(path)
        app.load_pdf(path)
        app.update()
        assert app.workspace.winfo_ismapped()
        assert not app.welcome.winfo_ismapped()
        assert len(app.document) == 2
        assert app.page_images
        app.next_page()
        assert app.page_number == 1
        app.toggle_bookmark()
        assert 1 in app.bookmarks
        app.document.close()
        app.document = None
finally:
    app.destroy()
print("Windows 시작 화면, PDF 렌더링, 페이지 이동, 책갈피 검사 통과")
