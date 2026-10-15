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
    TASKS = ['페이지 회전', '페이지 삭제', '빈 페이지 삽입', 'PDF 분할', '문서 정보', '문서 책갈피', '암호 설정·해제', '페이지 순서·추출', '텍스트 워터마크', '머리말·꼬리말·쪽 번호', '여백 자르기', '페이지 배경색', 'PDF 용량 최적화', '문서 마무리 표시 제거']

    def __init__(self, parent, colors):
        super().__init__(parent)
        self.parent, self.colors = parent, colors
        self.busy = False
        self.info = None
        self.plan = None
        self.undo_stack, self.redo_stack = [], []
        self.page_form_applied = False
        self.applied_tasks = set()
        self.result_path = None
        self.snapshot = parent.document.tobytes(encryption=pymupdf.PDF_ENCRYPT_KEEP)
        self.original = parent.document_path
        self.title(tr('PDF 도구'))
        self.geometry(f'650x{min(810, max(500, self.winfo_screenheight() - 100))}')
        self.transient(parent)
        self.grab_set()
        self.protocol('WM_DELETE_WINDOW', self.close)
        actions = ttk.Frame(self, padding=16)
        actions.pack(side='bottom', fill='x')
        scroller = ttk.Frame(self)
        scroller.pack(fill='both', expand=True)
        canvas = tk.Canvas(scroller, highlightthickness=0, takefocus=True, bg=colors.get('surface', '#FFFFFF'))
        scrollbar = ttk.Scrollbar(scroller, orient='vertical', command=canvas.yview)
        scrollbar.pack(side='right', fill='y')
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side='left', fill='both', expand=True)
        body = ttk.Frame(canvas, padding=20)
        window = canvas.create_window((0, 0), window=body, anchor='nw')
        body.bind('<Configure>', lambda _: canvas.configure(scrollregion=canvas.bbox('all')))
        canvas.bind('<Configure>', lambda event: canvas.itemconfigure(window, width=event.width))
        self.bind('<MouseWheel>', lambda event: canvas.yview_scroll(-1 if event.delta > 0 else 1, 'units'))
        self.bind('<Button-4>', lambda _: canvas.yview_scroll(-1, 'units'))
        self.bind('<Button-5>', lambda _: canvas.yview_scroll(1, 'units'))
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
        history = ttk.Frame(body)
        history.pack(fill='x', pady=(0, 8))
        self.apply_button = ttk.Button(history, text=tr('페이지 변경 적용'), command=self.apply_pages)
        self.apply_button.pack(side='left')
        self.undo_button = ttk.Button(history, text=tr('되돌리기'), command=lambda: self.history(True), state='disabled')
        self.undo_button.pack(side='left', padx=4)
        self.redo_button = ttk.Button(history, text=tr('다시 실행'), command=lambda: self.history(False), state='disabled')
        self.redo_button.pack(side='left')
        ttk.Label(body, text=tr('페이지 목록을 드래그해 순서를 바꿀 수 있습니다.')).pack(anchor='w')
        self.page_list = tk.Listbox(body, height=4, exportselection=False, bg=colors.get('surface', '#FFFFFF'), fg=colors.get('ink', '#182235'), selectbackground=colors.get('blue', '#245EDB'), selectforeground=colors.get('on_blue', '#FFFFFF'))
        self.page_list.pack(fill='x', pady=(4, 8))
        self.drag_start = None
        self.page_list.bind('<ButtonPress-1>', lambda event: setattr(self, 'drag_start', self.page_list.nearest(event.y)))
        self.page_list.bind('<ButtonRelease-1>', self.drag_page)
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
        self.status = ttk.Label(actions, text=tr('문서를 확인하고 있습니다…'), wraplength=600)
        self.status.pack(fill='x', pady=12)
        ttk.Button(actions, text=tr('페이지 추출·병합'), command=self.compose).pack(side='left')
        self.save_button = ttk.Button(actions, text=tr('새 파일로 저장'), command=self.save, state='disabled')
        self.save_button.pack(side='right')
        self.open_button = ttk.Button(actions, text=tr('결과 열기'), command=self.open_result, state='disabled')
        self.open_button.pack(side='right', padx=8)
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
            if self.plan is None:
                self.plan = [{'index': i, 'rotation': 0} for i in range(self.info['pages'])]
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
        variable = tk.StringVar(value=str(value))
        variable.trace_add('write', lambda *_: self.input_changed())
        entry = ttk.Entry(self.form, textvariable=variable)
        entry._variable = variable
        entry.pack(fill='x')
        self.fields[label] = entry
        return entry

    def render(self):
        for child in self.form.winfo_children():
            child.destroy()
        self.fields = {}
        if not self.info:
            return
        task, count = self.task.current(), len(self.plan)
        self.page_form_applied = task in self.applied_tasks
        self.page_list.delete(0, 'end')
        for position, page in enumerate(self.plan):
            label = tr('빈 페이지') if page['index'] is None else tr('원본 {0}쪽', str(page['index'] + 1))
            self.page_list.insert('end', f"{position + 1}. {label} · {page['rotation']}°")
        self.undo_button.state(['!disabled'] if self.undo_stack else ['disabled'])
        self.redo_button.state(['!disabled'] if self.redo_stack else ['disabled'])
        self.apply_button.state(['!disabled'] if task in (0, 1, 2, 7) else ['disabled'])
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
        elif task == 7:
            self.field('페이지 순서·추출', ','.join(str(i + 1) for i in range(count)))
            ttk.Label(self.form, text=tr('예: 3, 1, 2 또는 1-3, 5')).pack(anchor='w', pady=8)
        elif task == 8:
            self.field('워터마크 문구 (영문·숫자)', 'CONFIDENTIAL')
            ttk.Label(self.form, text=tr('옅은 대각선 문구를 각 페이지에 넣습니다.')).pack(anchor='w', pady=8)
            ttk.Label(self.form, text=tr('문구는 현재 영문·숫자·기본 기호를 지원합니다. 한글 문구는 지원하지 않습니다.'), wraplength=570).pack(anchor='w')
        elif task == 9:
            self.field('머리말 (영문·숫자)')
            self.field('꼬리말 (영문·숫자)')
            self.page_numbers = tk.BooleanVar(value=True)
            ttk.Checkbutton(self.form, text=tr('페이지 번호 넣기'), variable=self.page_numbers, command=self.input_changed).pack(anchor='w', pady=8)
            ttk.Label(self.form, text=tr('문구는 현재 영문·숫자·기본 기호를 지원합니다. 한글 문구는 지원하지 않습니다.'), wraplength=570).pack(anchor='w')
        elif task == 10:
            self.reset_crop = tk.BooleanVar(value=False)
            ttk.Checkbutton(self.form, text=tr('자르기 해제'), variable=self.reset_crop, command=self.input_changed).pack(anchor='w', pady=8)
            for label in ['왼쪽 여백 (mm)', '위 여백 (mm)', '오른쪽 여백 (mm)', '아래 여백 (mm)']:
                self.field(label, 5)
            ttk.Label(self.form, text=tr('원본 용지 가장자리 기준입니다. 잘린 내용은 숨겨지며 삭제되지 않습니다.'), wraplength=570).pack(anchor='w', pady=8)
        elif task == 11:
            self.background = ttk.Combobox(self.form, state='readonly', values=[tr('연한 노랑'), tr('연한 파랑')])
            self.background.current(0)
            self.background.bind('<<ComboboxSelected>>', lambda _: self.input_changed())
            self.background.pack(fill='x', pady=8)
        elif task == 12:
            ttk.Label(self.form, text=tr('큰 이미지를 150ppi로 줄입니다. 화질이 달라질 수 있고 용량 감소는 문서에 따라 다릅니다.'), wraplength=570).pack(anchor='w', pady=16)
        elif task == 13:
            ttk.Label(self.form, text=tr('CY뷰어·PdfCraft가 넣은 워터마크·머리말·꼬리말·배경을 제거합니다. 새 설정은 이어서 적용됩니다.'), wraplength=570).pack(anchor='w', pady=16)
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
        task, count = self.task.current(), len(self.plan)
        get = lambda name: self.fields[name].get()
        options = {}
        plan = [dict(page) for page in self.plan]
        if task in (0, 1) and not self.page_form_applied:
            chosen = {p - 1 for p in parse_pages(get('대상 페이지'), count)}
            if task == 0:
                angle = int(get('시계 방향 회전 각도'))
                if angle not in (90, 180, 270):
                    raise ValueError('회전 각도는 90, 180, 270 중에서 선택하세요.')
                for index, p in enumerate(plan):
                    if index in chosen: p['rotation'] = (p['rotation'] + angle) % 360
            else:
                plan = [p for index, p in enumerate(plan) if index not in chosen]
                if not plan: raise ValueError('문서는 최소 한 페이지를 유지해야 합니다.')
            options['page_plan'] = plan
        elif task == 2 and not self.page_form_applied:
            at = int(get('삽입할 위치 (1부터 마지막 다음까지)'))
            if not 1 <= at <= count + 1: raise ValueError('삽입할 페이지 위치가 올바르지 않습니다.')
            plan.insert(at - 1, {'index': None, 'rotation': 0})
            options['page_plan'] = plan
        elif task == 7 and not self.page_form_applied:
            plan = [plan[i - 1] for i in parse_pages(get('페이지 순서·추출'), count)]
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
        if task == 8:
            options['finishing'] = {'watermark': get('워터마크 문구 (영문·숫자)')}
        elif task == 9:
            options['finishing'] = {'header': get('머리말 (영문·숫자)'), 'footer': get('꼬리말 (영문·숫자)'), 'page_numbers': self.page_numbers.get()}
        elif task == 10:
            options['finishing'] = {'reset_crop': True} if self.reset_crop.get() else {'crop_mm': [float(get(label)) for label in ['왼쪽 여백 (mm)', '위 여백 (mm)', '오른쪽 여백 (mm)', '아래 여백 (mm)']]}
        elif task == 11:
            options['finishing'] = {'background': [1.0, 1.0, 0.85] if self.background.current() == 0 else [0.9, 0.95, 1.0]}
        elif task == 12:
            options['finishing'] = {'optimize': True}
        elif task == 13:
            options['finishing'] = {'remove_marks': True}
        if 'page_plan' not in options and self.plan != [{'index': i, 'rotation': 0} for i in range(self.info['pages'])]:
            options['page_plan'] = plan
        security = self.security.current()
        if security == 1:
            password = self.new_password.get()
            if not password or password != self.confirm.get(): raise ValueError('새 암호와 확인 암호를 같게 입력하세요.')
            options['new_password'] = password
        elif security == 2:
            options['remove_password'] = True
        if task == 6 and security == 0: raise ValueError('새 암호 설정 또는 암호 해제를 선택하세요.')
        return options

    def input_changed(self):
        self.page_form_applied = False
        self.result_path = None
        if hasattr(self, 'open_button'):
            self.open_button.state(['disabled'])

    def commit_plan(self, plan):
        self.undo_stack.append([dict(page) for page in self.plan])
        self.undo_stack = self.undo_stack[-30:]
        self.redo_stack.clear()
        self.plan = plan
        self.applied_tasks.add(self.task.current())
        self.render()
        self.page_form_applied = True
        self.result_path = None
        self.open_button.state(['disabled'])

    def apply_pages(self):
        if self.busy or not self.info or self.task.current() not in (0, 1, 2, 7):
            return
        previous = self.page_form_applied
        try:
            # 적용 버튼을 다시 누른 경우에만 같은 입력을 새 작업으로 실행한다.
            self.page_form_applied = False
            self.commit_plan(self.options().get('page_plan', self.plan))
            self.status.config(text=tr('페이지 변경을 적용했습니다. 새 파일로 저장하세요.'))
        except Exception as error:
            self.page_form_applied = previous
            self.status.config(text=tr(str(error)))

    def history(self, undo):
        if self.busy:
            return
        source, target = (self.undo_stack, self.redo_stack) if undo else (self.redo_stack, self.undo_stack)
        if not source:
            return
        target.append([dict(page) for page in self.plan])
        self.plan = source.pop()
        self.applied_tasks.add(self.task.current())
        self.render()
        self.page_form_applied = True
        self.result_path = None
        self.open_button.state(['disabled'])

    def drag_page(self, event):
        if self.busy or self.plan is None or self.drag_start is None:
            return
        end = self.page_list.nearest(event.y)
        if self.drag_start != end:
            plan = [dict(page) for page in self.plan]
            plan.insert(end, plan.pop(self.drag_start))
            self.commit_plan(plan)
        self.drag_start = None

    def open_result(self):
        if self.result_path and not self.busy:
            path = self.result_path
            self.close()
            self.parent.load_pdf(path)

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
                self.result_path = destination if extension == 'pdf' else None
                self.open_button.state(['!disabled'] if self.result_path else ['disabled'])
                self.status.config(text=tr('새 파일을 저장했습니다. 원본은 변경하지 않았습니다.') + '\n' + str(destination))
            self.run(options, saved)
        except Exception as error:
            self.status.config(text=tr(str(error)))
