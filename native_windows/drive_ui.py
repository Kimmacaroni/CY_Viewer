"""Tk 주 스레드와 Drive 네트워크 작업을 분리하는 연결 화면."""
import threading
import hashlib
import re
import queue
import tempfile
import time
import tkinter as tk
from pathlib import Path
from tkinter import ttk
from cy_localization import tr
from drive_sync import Drive, reading, merge_reading


class DriveUI:
    def __init__(self, app):
        self.app = app
        self.drive = Drive()
        self.jobs = queue.Queue()
        threading.Thread(target=self.worker, daemon=True).start()
        self.results = queue.Queue()
        self.row = None
        self.document_generation = 0
        self.path = None
        self.rows = []
        self.pending = None
        self.save_timer = None
        self.old_marks = set()
        self.status = tr('Google 계정을 연결하면 이후 여는 PDF와 책갈피·읽던 페이지를 개인 Drive에 저장합니다.')
        self.busy = False
        self.window = None
        self.app.after(100, self.poll)

    def worker(self):
        while True:
            self.jobs.get()()

    def poll(self):
        while not self.results.empty():
            drive, callback, result, error = self.results.get()
            if drive is not self.drive:
                continue
            self.busy = False
            if error:
                self.status = tr('Drive 동기화에 실패했습니다. 연결과 저장 공간을 확인해 주세요.')
            elif callback:
                callback(result)
            self.app.status.config(text=self.status)
            self.render()
        self.app.after(100, self.poll)

    def submit(self, work, callback=None):
        drive = self.drive
        self.busy = True
        self.status = tr('Drive 동기화 중…')
        self.render()
        def run():
            try:
                if drive is not self.drive:
                    return
                self.results.put((drive, callback, work(), None))
            except Exception as error:
                self.results.put((drive, callback, None, type(error).__name__))
        self.jobs.put(run)

    def show(self):
        if self.window and self.window.winfo_exists():
            self.window.lift(); return
        self.window = tk.Toplevel(self.app)
        self.window.title(tr('Google Drive 동기화'))
        self.window.geometry('560x520')
        self.window.minsize(420, 420)
        self.frame = ttk.Frame(self.window, padding=20)
        self.frame.pack(fill='both', expand=True)
        self.render()
        if self.drive.token:
            self.refresh()

    def render(self):
        self.app.refresh_drive_home()
        if not self.window or not self.window.winfo_exists():
            return
        for child in self.frame.winfo_children():
            child.destroy()
        ttk.Label(self.frame, text=tr('Google Drive 동기화'), font=('Malgun Gothic', 16, 'bold')).pack(anchor='w', pady=(0,12))
        ttk.Label(self.frame, text=self.drive.account or tr('개인 Google Drive'), wraplength=480).pack(anchor='w')
        ttk.Label(self.frame, text=self.status, wraplength=480).pack(anchor='w', pady=12)
        if self.drive.token:
            ttk.Label(self.frame, text=tr('Drive 최근 파일 · 최대 5개')).pack(anchor='w', pady=8)
            for row in self.rows:
                ttk.Button(self.frame, text=row.get('name', 'PDF'), command=lambda r=row:self.download(r), state='disabled' if self.busy else 'normal').pack(fill='x', pady=3)
            if not self.rows:
                ttk.Label(self.frame, text=tr('아직 동기화한 PDF가 없습니다. 이 창을 닫고 PDF를 열어 주세요.'), wraplength=480).pack(anchor='w', pady=10)
            actions = ttk.Frame(self.frame)
            actions.pack(fill='x')
            ttk.Button(actions, text=tr('새로고침'), command=self.refresh, state='disabled' if self.busy else 'normal').pack(side='left', pady=12)
            ttk.Button(actions, text=tr('연결 해제'), command=self.disconnect).pack(side='left', padx=8)
        else:
            ttk.Button(self.frame, text=tr('Google 계정으로 Drive 연결'), command=self.connect, state='disabled' if self.busy else 'normal').pack(fill='x', pady=16)
        ttk.Label(self.frame, text=tr('앱을 다시 실행하거나 연결이 만료되면 다시 연결해 주세요. 이전 PDF는 Drive에 남습니다.'), wraplength=480).pack(anchor='w', pady=10)

    def connect(self):
        drive = self.drive
        def ready(rows):
            self.rows = rows
            self.status = tr('Drive 연결 완료. 이후 여는 PDF를 동기화합니다.')
        self.submit(drive.connect, ready)

    def disconnect(self):
        if self.save_timer:
            self.app.after_cancel(self.save_timer)
        self.save_timer = None
        self.pending = None
        self.drive.token = None
        self.drive = Drive()
        self.row = None
        self.rows = []
        self.status = tr('Drive 연결을 해제했습니다. 저장된 파일은 Drive에 남습니다.')
        self.busy = False
        self.render()

    def refresh(self):
        drive = self.drive
        def ready(rows):
            self.rows = rows
            self.status = tr('Drive 최근 파일을 불러왔습니다.')
        self.submit(drive.recent, ready)

    def download(self, row):
        drive = self.drive
        def ready(data):
            directory = Path(tempfile.gettempdir()) / 'CYViewer-Drive' / hashlib.sha256(data).hexdigest()
            directory.mkdir(parents=True, exist_ok=True)
            name = 'PDF-' + re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', row.get('name', 'document.pdf'))[:120].rstrip(' .')
            target = directory / name
            target.write_bytes(data)
            if self.window and self.window.winfo_exists():
                self.window.destroy()
            self.app.load_pdf(target)
        self.submit(lambda: drive.download(row), ready)

    def opened(self, path):
        self.flush()
        self.document_generation += 1
        generation = self.document_generation
        self.row = None
        self.path = path
        self.old_marks = set(self.app.bookmarks)
        if not self.drive.token:
            return
        drive = self.drive
        start_page = self.app.page_number
        start_marks = set(self.app.bookmarks)
        def ready(row):
            if generation != self.document_generation or path != self.path:
                return
            self.row = row
            state = reading(row)
            if self.app.bookmarks == start_marks and 'marks' in state:
                self.app.bookmarks = {int(n)-1 for n, v in state.get('marks', {}).items() if str(n).isdigit() and v.get('on') and 0 < int(n) <= len(self.app.document)}
            self.old_marks = {int(n)-1 for n,v in state.get('marks', {}).items() if v.get('on')}
            if self.app.page_number == start_page and 'page' in state:
                self.app.page_number = min(max(0,int(state.get('page',{}).get('n',1))-1),len(self.app.document)-1)
                self.app.draw_page()
            self.changed()
            self.status = tr('Drive 동기화 중…')
        self.submit(lambda: drive.open(path.name, path.read_bytes()), ready)

    def changed(self):
        if not self.row or not self.drive.token:
            return
        at = int(time.time()*1000)
        current = set(self.app.bookmarks)
        delta = {'page': {'n': self.app.page_number+1, 'at': at}, 'marks': {
            str(n+1): {'on': n in current, 'at': at} for n in self.old_marks ^ current}}
        self.old_marks = current
        self.pending = merge_reading(self.pending or {}, delta)
        if self.save_timer:
            self.app.after_cancel(self.save_timer)
        self.save_timer = self.app.after(800, self.flush)

    def flush(self):
        if self.save_timer:
            self.app.after_cancel(self.save_timer)
        self.save_timer = None
        if not self.pending or not self.row or not self.drive.token:
            return
        drive, row, delta = self.drive, self.row, self.pending
        self.pending = None
        # 문서/계정 참조를 고정해 다른 문서의 늦은 작업과 섞이지 않게 합니다.
        self.submit(lambda: drive.save(row, delta), lambda _: setattr(self, 'status', tr('Drive 동기화 완료')))
