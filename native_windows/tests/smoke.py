"""Windows 배포 전 시작 화면과 실제 PDF 열기·탐색을 검증한다."""
from pathlib import Path
import sys
import tempfile
import shutil
import tkinter as tk
from tkinter import messagebox

sys.stdout.reconfigure(encoding="utf-8")
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
        for number in range(6):
            another = Path(directory) / f"recent-{number}.pdf"
            shutil.copyfile(path, another)
            app.load_pdf(another)
        assert len(app.recent_files) == 5
        assert Path(app.recent_files[0]).name == "recent-5.pdf"
        app.load_pdf(Path(app.recent_files[2]))
        assert Path(app.recent_files[0]).name == "recent-3.pdf"
        assert len(app.recent_files) == 5
        previous = app.document_path
        app.is_dirty = True
        ask = messagebox.askyesno
        messagebox.askyesno = lambda *args, **kwargs: False
        try:
            app.load_pdf(path)
            assert app.document_path == previous
        finally:
            messagebox.askyesno = ask
            app.is_dirty = False
        app.geometry("780x560")
        app.welcome.destroy()
        app._make_welcome()
        app.update()
        def buttons(widget):
            return ([widget] if isinstance(widget, tk.Button) else []) + [item for child in widget.winfo_children() for item in buttons(child)]
        recent_buttons = buttons(app.welcome)
        assert len(recent_buttons) == 5
        for button in recent_buttons:
            assert button.winfo_ismapped()
            assert button.winfo_rooty() >= app.winfo_rooty()
            assert button.winfo_rooty() + button.winfo_height() <= app.winfo_rooty() + app.winfo_height()
        app.document.close()
        app.document = None
finally:
    app.destroy()
print("Windows 시작 화면, PDF 렌더링, 페이지 이동, 책갈피 검사 통과")
