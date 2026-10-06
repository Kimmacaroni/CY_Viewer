"""Windows 배포 전 시작 화면과 실제 PDF 열기·탐색을 검증한다."""
from pathlib import Path
import sys
import tempfile
import shutil
import tkinter as tk
from types import SimpleNamespace
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
        app.next_page()
        app.show_library()
        app.update()
        assert app.welcome.winfo_ismapped()
        assert not app.workspace.winfo_ismapped()
        current = str(app.document_path.resolve())
        app.toggle_favorite(current)
        assert app.library_state[current]['favorite']
        app.select_library_filter('favorites')
        assert app.library_tabs['favorites'].variant == 'selected'
        app.load_pdf(Path(current))
        app.update()
        assert app.page_number == 1
        app.geometry("900x700")
        app.update()
        assert not app.rail.winfo_ismapped()
        assert app.tools_button.winfo_ismapped()
        app.toggle_tools()
        app.update()
        assert app.rail.winfo_ismapped()
        # 좁은 창에서 패널을 펼쳐도 상단 도구가 모두 창 안에 배치된다.
        for control in app.reading_tools.winfo_children():
            assert control.winfo_ismapped()
            assert control.winfo_x() + control.winfo_width() <= app.reading_tools.winfo_width()
        app.toggle_tools()
        app.geometry("1200x800")
        app.update()
        # CI 가상 화면은 요청한 1200px 창을 더 작게 제한할 수 있다.
        # 실제 크기를 기록하고 넓은 화면의 Configure 처리도 직접 검증한다.
        print(f"Windows 반응형 검사: 화면 {app.winfo_screenwidth()}px, 창 {app.winfo_width()}px")
        if app.winfo_width() < 1100:
            app.reader_layout(SimpleNamespace(widget=app, width=1200))
            app.update_idletasks()
        assert app.rail.winfo_ismapped()
        assert not app.tools_button.winfo_ismapped()
        app.show_library()
        app.select_library_filter('all')
        app.geometry("780x560")
        app.update()
        def buttons(widget):
            return ([widget] if isinstance(widget, tk.Button) else []) + [item for child in widget.winfo_children() for item in buttons(child)]
        recent_buttons = buttons(app.welcome)
        assert len(recent_buttons) == 5
        assert all(button.winfo_width() > 100 for button in recent_buttons)
        # 작은 창은 문서를 제거하지 않고 스크롤한다.
        app.recent_files = []
        app.refresh_drive_home()
        app.update()
        assert app.welcome.winfo_ismapped()
        app.document.close()
        app.document = None
finally:
    app.destroy()
print("Windows 시작 화면, PDF 렌더링, 페이지 이동, 책갈피 검사 통과")
