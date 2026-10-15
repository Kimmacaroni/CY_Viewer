"""Windows 배포 전 시작 화면과 실제 PDF 열기·탐색을 검증한다."""
from pathlib import Path
import sys
import tempfile
import shutil
import tkinter as tk
from types import SimpleNamespace
from tkinter import messagebox, filedialog, ttk, simpledialog
import time

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
        # 실제 페이지 구성 대화상자에서 별도 파일 저장까지 실행한다.
        output = Path(directory) / 'composed.pdf'
        old_save = filedialog.asksaveasfilename
        filedialog.asksaveasfilename = lambda **kwargs: str(output)
        try:
            app.organize_pages()
            app.update()
            dialog = next(w for w in app.winfo_children() if isinstance(w, tk.Toplevel))
            def widgets(parent):
                return [parent] + [w for child in parent.winfo_children() for w in widgets(child)]
            entry = next(w for w in widgets(dialog) if isinstance(w, ttk.Entry))
            entry.delete(0, 'end')
            entry.insert(0, '2,1')
            button = next(w for w in widgets(dialog) if isinstance(w, ttk.Button) and w.cget('style') == 'Primary.TButton')
            button.invoke()
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline and not output.exists():
                app.update()
                time.sleep(0.05)
            assert output.exists(), '페이지 구성 결과가 저장되지 않았습니다.'
            with pymupdf.open(output) as result:
                assert len(result) == 2
                assert 'page 2' in result[0].get_text()
                assert 'page 1' in result[1].get_text()
            assert app.document_path == path
            time.sleep(0.2)
            app.update()
            dialog.destroy()
        finally:
            filedialog.asksaveasfilename = old_save
        # 실제 새 PDF 도구 화면에서 회전과 ZIP 분할을 저장한다.
        from pdf_tools_ui import PdfToolsDialog
        import zipfile
        output = Path(directory) / 'rotated.pdf'
        old_save = filedialog.asksaveasfilename
        filedialog.asksaveasfilename = lambda **kwargs: str(output)
        try:
            dialog = PdfToolsDialog(app, {})
            def wait_tools():
                deadline = time.monotonic() + 30
                while dialog.busy and time.monotonic() < deadline:
                    app.update()
                    time.sleep(0.05)
                assert not dialog.busy, 'PDF 도구 처리 시간 초과'
                app.update()
            wait_tools()
            assert dialog.info['pages'] == 2
            dialog.fields['대상 페이지'].delete(0, 'end')
            dialog.fields['대상 페이지'].insert(0, '1')
            dialog.save_button.invoke()
            wait_tools()
            with pymupdf.open(output) as result:
                assert result[0].rotation == 90
                assert result[1].rotation == 0
            output = Path(directory) / 'split.zip'
            dialog.task.current(3)
            dialog.render()
            dialog.save_button.invoke()
            wait_tools()
            with zipfile.ZipFile(output) as archive:
                assert len(archive.namelist()) == 2
                for index, name in enumerate(archive.namelist()):
                    with pymupdf.open(stream=archive.read(name), filetype='pdf') as part:
                        assert len(part) == 1
                        assert f'page {index + 1}' in part[0].get_text()
            for task in range(8, 14):
                output = Path(directory) / f'finishing-{task}.pdf'
                dialog.task.current(task)
                dialog.render()
                dialog.save_button.invoke()
                wait_tools()
                assert output.is_file(), dialog.status.cget('text')
                with pymupdf.open(output) as result:
                    assert len(result) == 2
                    if task == 8: assert 'CONFIDENTIAL' in result[0].get_text()
                    if task == 9: assert '1/2' in result[0].get_text()
                    if task == 10: assert result[0].rect.width < app.document[0].rect.width
            assert app.document[0].rotation == 0
            dialog.destroy()
        finally:
            filedialog.asksaveasfilename = old_save
        # Windows도 페이지 변경 기록과 결과 바로 열기를 제공한다.
        output = Path(directory) / 'history.pdf'
        old_save = filedialog.asksaveasfilename
        filedialog.asksaveasfilename = lambda **kwargs: str(output)
        try:
            dialog = PdfToolsDialog(app, {})
            wait_tools()
            dialog.task.current(7)
            dialog.render()
            field = dialog.fields['페이지 순서·추출']
            field.delete(0, 'end'); field.insert(0, '2,1')
            dialog.apply_button.invoke()
            assert [page['index'] for page in dialog.plan] == [1, 0]
            dialog.undo_button.invoke()
            assert [page['index'] for page in dialog.plan] == [0, 1]
            dialog.redo_button.invoke()
            assert [page['index'] for page in dialog.plan] == [1, 0]
            # 적용한 작업으로 돌아와도 기본 폼을 저장 시 다시 실행하지 않는다.
            dialog.task.current(0); dialog.render()
            dialog.apply_button.invoke()
            dialog.task.current(4); dialog.render()
            dialog.task.current(0); dialog.render()
            assert [page['rotation'] for page in dialog.options()['page_plan']] == [90, 90]
            dialog.task.current(2); dialog.render()
            dialog.apply_button.invoke()
            dialog.task.current(4); dialog.render()
            dialog.task.current(2); dialog.render()
            assert len(dialog.options()['page_plan']) == 3
            dialog.task.current(1); dialog.render()
            field = dialog.fields['대상 페이지']
            field.delete(0, 'end'); field.insert(0, '1')
            dialog.apply_button.invoke()
            dialog.task.current(4); dialog.render()
            dialog.task.current(1); dialog.render()
            assert len(dialog.options()['page_plan']) == 2
            dialog.undo_button.invoke(); dialog.undo_button.invoke()
            dialog.task.current(0); dialog.render()
            dialog.save_button.invoke()
            wait_tools()
            with pymupdf.open(output) as result:
                assert 'page 2' in result[0].get_text()
                assert [page.rotation for page in result] == [90, 90]
            dialog.open_button.invoke()
            app.update()
            assert app.document_path == output
            app.load_pdf(path)
        finally:
            filedialog.asksaveasfilename = old_save
        # 암호 문서를 실제 리더에서 재입력해 열고 PDF 도구로 암호를 해제한다.
        encrypted = Path(directory) / 'encrypted.pdf'
        with pymupdf.open(path) as source:
            source.save(encrypted, encryption=pymupdf.PDF_ENCRYPT_AES_256, owner_pw='smoke-secret', user_pw='smoke-secret')
        old_ask, old_warning = simpledialog.askstring, messagebox.showwarning
        old_save = filedialog.asksaveasfilename
        warnings = []
        attempts = iter(['wrong', 'smoke-secret'])
        simpledialog.askstring = lambda *args, **kwargs: next(attempts)
        messagebox.showwarning = lambda *args, **kwargs: warnings.append(True)
        try:
            app.load_pdf(encrypted)
            app.update()
            assert app.document_path == encrypted and len(warnings) == 1
            assert app._document_password == 'smoke-secret'
            dialog = PdfToolsDialog(app, {})
            wait_tools()
            assert dialog.info['encrypted'] and dialog.info['owner']
            output = Path(directory) / 'unlocked.pdf'
            filedialog.asksaveasfilename = lambda **kwargs: str(output)
            dialog.task.current(6)
            dialog.render()
            dialog.security.current(2)
            dialog.save_button.invoke()
            wait_tools()
            with pymupdf.open(output) as result:
                assert not result.needs_pass and len(result) == 2
            dialog.destroy()
            app.load_pdf(path)
            simpledialog.askstring = lambda *args, **kwargs: None
            app.load_pdf(encrypted)
            assert app.document_path == path
            assert app._document_password == ''
        finally:
            simpledialog.askstring, messagebox.showwarning = old_ask, old_warning
            filedialog.asksaveasfilename = old_save
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
print("Windows 시작 화면·PDF 렌더링·페이지 이동·책갈피·회전·분할 ZIP·되돌리기·다시 실행·결과 열기·암호 재입력·해제 저장 검사 통과")
