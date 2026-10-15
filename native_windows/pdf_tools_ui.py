"""PdfCraft의 문서 편집 기능을 Windows에서 제공한다."""
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import ttk, filedialog

import pymupdf
from cy_localization import tr
from pdfcraft import tools_request, parse_pages, save_copy


class PdfToolsDialog(tk.Toplevel):
    TASKS = ['페이지 회전', '페이지 삭제', '빈 페이지 삽입', 'PDF 분할', '문서 정보', '문서 책갈피', '암호 설정·해제']

    def __init__(self, parent, colors):
        super().__init__(parent)
        self.parent, self.colors = parent, colors
        self.busy = False
        self.info = None
        self.snapshot = parent.document.tobytes(encryption=pymupdf.PDF_ENCRYPT_KEEP)
        self.original = parent.document_path
        self.title(tr('PDF 도구'))
        self.geometry('650x730')
        self.transient(parent)
        self.grab_set()
        self.protocol('WM_DELETE_WINDOW', self.close)
        body = ttk.Frame(self, padding=20)
        body.pack(fill='both', expand=True)
        ttk.Label(body, text=self.original.name if self.original else 'PDF', font=('Malgun Gothic', 13, 'bold')).pack(anchor='w')
        ttk.Label(body, text=tr('변경은 새 파일에 저장합니다. 원본은 유지됩니다.')).pack(anchor='w', pady=(4, 12))
        row = ttk.Frame(body)
        row.pack(fill='x')
        ttk.Label(row, text=tr('현재 PDF 암호')).pack(side='left')
        self.password = ttk.Entry(row, show='•')
        self.password.insert(0, getattr(parent, '_document_password', ''))
        self.password.pack(side='left', fill='x', expand=True, padx=8)
        self.inspect_button = ttk.Button(row, text=tr('문서 확인'), command=self.inspect)
        self.inspect_button.pack(side='left')
        self.task = ttk.Combobox(body, state='readonly', values=[tr(t) for t in self.TASKS])
        self.task.current(0)
        self.task.pack(fill='x', pady=16)
        self.task.bind('<<ComboboxSelected>>', lambda _: self.render())
        self.form = ttk.Frame(body)
        self.form.pack(fill='both', expand=True)
        self.security = ttk.Combobox(body, state='readonly', values=[tr('암호 변경 안 함'), tr('새 암호 설정'), tr('암호 해제')])
        self.security.current(0)
        self.security.pack(fill='x', pady=(12, 4))
        self.new_password = ttk.Entry(body, show='•')
        self.new_password.pack(fill='x', pady=4)
        self.confirm = ttk.Entry(body, show='•')
        self.confirm.pack(fill='x', pady=4)
        ttk.Label(body, text=tr('새 암호 설정 시 위 두 칸에 같은 암호를 입력하세요.'), wraplength=600).pack(anchor='w')
        self.status = ttk.Label(body, text=tr('문서를 확인하고 있습니다…'), wraplength=600)
        self.status.pack(fill='x', pady=12)
        actions = ttk.Frame(body)
        actions.pack(fill='x')
        ttk.Button(actions, text=tr('페이지 추출·병합'), command=self.compose).pack(side='left')
        self.save_button = ttk.Button(actions, text=tr('새 파일로 저장'), command=self.save, state='disabled')
        self.save_button.pack(side='right')
        self.fields = {}
        self.inspect()

    def close(self):
        if not self.busy:
            self.destroy()

    def compose(self):
        if not self.busy:
            self.destroy()
            self.parent.organize_pages()

    def run(self, options, done):
        if self.busy:
            return
        self.busy = True
        self.save_button.state(['disabled'])
        self.inspect_button.state(['disabled'])
        self.task.state(['disabled'])
        self.status.config(text=tr('PDF를 처리하고 있습니다…'))
        results = queue.Queue()
        password = self.password.get()
        def worker():
            try:
                results.put((True, tools_request(self.snapshot, self.original.name if self.original else 'PDF', options, password)))
            except Exception as error:
                results.put((False, error))
        threading.Thread(target=worker, daemon=True).start()
        def poll():
            try:
                ok, value = results.get_nowait()
            except queue.Empty:
                self.after(100, poll)
                return
            self.busy = False
            self.inspect_button.state(['!disabled'])
            self.task.state(['!disabled'])
            if self.info and not self.info['signed'] and self.info['owner']:
                self.save_button.state(['!disabled'])
            if ok:
                try:
                    done(value)
                except Exception as error:
                    self.status.config(text=tr(str(error)))
            else:
                self.status.config(text=tr(str(value)))
        self.after(100, poll)

    def inspect(self):
        def loaded(result):
            self.info = result[0]
            self.render()
            if self.info['signed']:
                self.status.config(text=tr('전자서명된 PDF는 편집할 수 없습니다.'))
            elif not self.info['owner']:
                self.status.config(text=tr('편집하려면 PDF의 소유자 암호를 입력하세요.'))
            else:
                self.status.config(text=tr('문서 확인 완료. 작업을 선택하고 새 파일로 저장하세요.'))
                self.save_button.state(['!disabled'])
        self.run({'inspect': True}, loaded)

    def field(self, label, value=''):
        ttk.Label(self.form, text=tr(label)).pack(anchor='w', pady=(8, 4))
        entry = ttk.Entry(self.form)
        entry.insert(0, str(value))
        entry.pack(fill='x')
        self.fields[label] = entry
        return entry

    def render(self):
        for child in self.form.winfo_children():
            child.destroy()
        self.fields = {}
        if not self.info:
            return
        task, count = self.task.current(), self.info['pages']
        if task in (0, 1):
            self.field('대상 페이지', f'1-{count}')
            ttk.Label(self.form, text=tr('예: 1-3, 5')).pack(anchor='w', pady=8)
            if task == 0:
                self.field('시계 방향 회전 각도', '90')
        elif task == 2:
            self.field('삽입할 위치 (1부터 마지막 다음까지)', count + 1)
            ttk.Label(self.form, text=tr('A4 크기의 빈 페이지를 삽입합니다.')).pack(anchor='w', pady=8)
        elif task == 3:
            self.field('몇 쪽마다 나눌까요?', 1)
            ttk.Label(self.form, text=tr('결과를 여러 PDF로 나누어 ZIP 파일 하나로 저장합니다.'), wraplength=600).pack(anchor='w', pady=8)
        elif task == 4:
            for key, label in [('Title', '제목'), ('Author', '작성자'), ('Subject', '주제'), ('Keywords', '키워드')]:
                self.field(label, self.info['metadata'].get(key, ''))
        elif task == 5:
            self.bookmark_action = ttk.Combobox(self.form, state='readonly', values=[tr('책갈피 추가'), tr('책갈피 수정'), tr('책갈피 삭제')])
            self.bookmark_action.current(0)
            self.bookmark_action.pack(fill='x', pady=8)
            self.bookmark = ttk.Combobox(self.form, state='readonly', values=[b['title'] for b in self.info['bookmarks']])
            self.bookmark.pack(fill='x', pady=8)
            title, page = self.field('책갈피 이름'), self.field('원본 쪽', 1)
            def select(_):
                index = self.bookmark.current()
                if index >= 0:
                    bookmark = self.info['bookmarks'][index]
                    title.delete(0, 'end'); title.insert(0, bookmark['title'])
                    page.delete(0, 'end'); page.insert(0, str(bookmark['page'] or 1))
            self.bookmark.bind('<<ComboboxSelected>>', select)
        else:
            ttk.Label(self.form, text=tr('아래에서 새 암호 설정 또는 암호 해제를 선택하세요.\n새 암호는 문서 열기와 소유자 암호로 함께 사용합니다.'), wraplength=600).pack(anchor='w', pady=16)

    def options(self):
        task, count = self.task.current(), self.info['pages']
        get = lambda name: self.fields[name].get()
        options = {}
        plan = [{'index': i, 'rotation': 0} for i in range(count)]
        if task in (0, 1):
            chosen = {p - 1 for p in parse_pages(get('대상 페이지'), count)}
            if task == 0:
                angle = int(get('시계 방향 회전 각도'))
                if angle not in (90, 180, 270):
                    raise ValueError('회전 각도는 90, 180, 270 중에서 선택하세요.')
                for p in plan:
                    if p['index'] in chosen: p['rotation'] = angle
            else:
                plan = [p for p in plan if p['index'] not in chosen]
                if not plan: raise ValueError('문서는 최소 한 페이지를 유지해야 합니다.')
            options['page_plan'] = plan
        elif task == 2:
            at = int(get('삽입할 위치 (1부터 마지막 다음까지)'))
            if not 1 <= at <= count + 1: raise ValueError('삽입할 페이지 위치가 올바르지 않습니다.')
            plan.insert(at - 1, {'index': None, 'rotation': 0})
            options['page_plan'] = plan
        elif task == 3:
            options['split_every'] = int(get('몇 쪽마다 나눌까요?'))
            if options['split_every'] < 1: raise ValueError('분할 간격은 1 이상으로 입력하세요.')
        elif task == 4:
            options['metadata'] = {key: get(label) for key, label in [('Title', '제목'), ('Author', '작성자'), ('Subject', '주제'), ('Keywords', '키워드')]}
        elif task == 5:
            action = self.bookmark_action.current()
            edit = {'action': ['add', 'update', 'delete'][action]}
            if action != 0:
                index = self.bookmark.current()
                if index < 0: raise ValueError('수정하거나 삭제할 책갈피를 선택하세요.')
                edit['path'] = self.info['bookmarks'][index]['path']
            if action != 2:
                edit.update({'title': get('책갈피 이름'), 'page': int(get('원본 쪽'))})
            options['bookmarks'] = [edit]
        security = self.security.current()
        if security == 1:
            password = self.new_password.get()
            if not password or password != self.confirm.get(): raise ValueError('새 암호와 확인 암호를 같게 입력하세요.')
            options['new_password'] = password
        elif security == 2:
            options['remove_password'] = True
        if task == 6 and security == 0: raise ValueError('새 암호 설정 또는 암호 해제를 선택하세요.')
        return options

    def save(self):
        if self.busy or not self.info:
            return
        try:
            options = self.options()
            extension = 'zip' if 'split_every' in options else 'pdf'
            path = filedialog.asksaveasfilename(parent=self, title=tr('새 파일로 저장'), defaultextension='.' + extension, initialfile=(self.original.stem if self.original else 'PDF') + '-edited.' + extension, filetypes=[(extension.upper(), '*.' + extension)])
            if not path:
                return
            destination = Path(path)
            if self.original and destination.resolve() == self.original.resolve():
                raise ValueError('원본과 다른 이름으로 저장하세요.')
            def saved(result):
                report, data = result
                save_copy(data, destination, [self.original] if self.original else [])
                self.status.config(text=tr('새 파일을 저장했습니다. 원본은 변경하지 않았습니다.') + '\n' + str(destination))
            self.run(options, saved)
        except Exception as error:
            self.status.config(text=tr(str(error)))
