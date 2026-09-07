"""CY뷰어 - Windows용 개인 PDF 뷰어."""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

import pymupdf
from PIL import Image, ImageTk


class CyViewer(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("CY뷰어 | 개인용 PDF 뷰어")
        self.geometry("1280x820")
        self.minsize(780, 560)
        self.configure(bg="#eef2f7")

        self.document: pymupdf.Document | None = None
        self.document_path: Path | None = None
        self.page_number = 0
        self.zoom = 1.2
        self.bookmarks: set[int] = set()
        self.search_text = ""
        self.search_matches: list[tuple[int, pymupdf.Rect]] = []
        self.search_index = -1
        self.page_image: ImageTk.PhotoImage | None = None
        self.page_left = 0
        self.page_top = 0
        self.selected_rect: pymupdf.Rect | None = None
        self.selection_start: tuple[int, int] | None = None
        self.selection_preview: int | None = None

        self._make_ui()

    def _make_ui(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Action.TButton", font=("Malgun Gothic", 10), padding=(10, 7))
        style.configure("Primary.TButton", font=("Malgun Gothic", 10, "bold"), padding=(12, 8))

        header = tk.Frame(self, bg="#0f172a", padx=24, pady=16)
        header.pack(fill="x")
        tk.Label(
            header,
            text="CY뷰어  |  PDF 작업 공간",
            fg="white",
            bg="#0f172a",
            font=("Malgun Gothic", 18, "bold"),
        ).pack(side="left")
        self.file_label = tk.Label(
            header,
            text="문서를 열어 시작하세요",
            fg="#94a3b8",
            bg="#0f172a",
            font=("Malgun Gothic", 10),
        )
        self.file_label.pack(side="left", padx=18)

        workspace = tk.Frame(self, bg="#e2e8f0")
        workspace.pack(fill="both", expand=True)
        sidebar = tk.Frame(workspace, width=250, bg="#f8fafc", padx=16, pady=18)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)
        self._button(sidebar, "＋ PDF 열기", self.open_pdf, "Primary.TButton").pack(fill="x", pady=(0, 18))
        self._side_title(sidebar, "문서 탐색")
        self._button(sidebar, "◀  이전 페이지", self.previous_page).pack(fill="x", pady=2)
        self._button(sidebar, "다음 페이지  ▶", self.next_page).pack(fill="x", pady=2)
        self._button(sidebar, "페이지로 이동", self.go_to_page).pack(fill="x", pady=2)
        self._button(sidebar, "☆  이 페이지 책갈피", self.toggle_bookmark).pack(fill="x", pady=2)
        self._button(sidebar, "책갈피 목록", self.show_bookmarks).pack(fill="x", pady=2)
        self._side_title(sidebar, "선택한 문구 편집")
        self._button(sidebar, "형광펜 표시", lambda: self.mark_selection("highlight")).pack(fill="x", pady=2)
        self._button(sidebar, "밑줄", lambda: self.mark_selection("underline")).pack(fill="x", pady=2)
        self._button(sidebar, "취소선", lambda: self.mark_selection("strike")).pack(fill="x", pady=2)
        self._button(sidebar, "굵게 처리", self.bold_selection).pack(fill="x", pady=2)
        self._button(sidebar, "문구 수정", self.edit_selection).pack(fill="x", pady=2)
        self._button(sidebar, "PDF로 저장", self.save_as, "Primary.TButton").pack(fill="x", pady=(14, 4))
        self.selection_label = tk.Label(
            sidebar,
            text="사용 순서\n1. PDF 열기\n2. 문구를 드래그\n3. 왼쪽 기능 선택\n4. PDF로 저장",
            justify="left",
            anchor="w",
            bg="#e0f2fe",
            fg="#0c4a6e",
            padx=12,
            pady=12,
            font=("Malgun Gothic", 9),
        )
        self.selection_label.pack(fill="x", pady=(16, 0))

        content = tk.Frame(workspace, bg="#e2e8f0")
        content.pack(side="left", fill="both", expand=True)
        tools = tk.Frame(content, bg="#ffffff", padx=16, pady=10)
        tools.pack(fill="x")
        self._button(tools, "−", lambda: self.change_zoom(-0.2)).pack(side="left", padx=2)
        self._button(tools, "+", lambda: self.change_zoom(0.2)).pack(side="left", padx=2)
        tk.Label(tools, text="Ctrl + 휠로 확대/축소", bg="#ffffff", fg="#64748b", font=("Malgun Gothic", 9)).pack(side="left", padx=10)
        search_box = tk.Frame(tools, bg="#ffffff")
        search_box.pack(side="right")
        self.search_entry = ttk.Entry(search_box, width=24)
        self.search_entry.pack(side="left", padx=(0, 4))
        self.search_entry.bind("<Return>", lambda _: self.find_next())
        self._button(search_box, "검색", self.find_next).pack(side="left", padx=3)
        self.search_status = tk.Label(search_box, text="", bg="#ffffff")
        self.search_status.pack(side="left", padx=5)

        self.canvas = tk.Canvas(content, bg="#94a3b8", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", lambda _: self.draw_page())
        self.canvas.bind("<MouseWheel>", self._wheel_zoom)
        self.canvas.bind("<ButtonPress-1>", self.start_selection)
        self.canvas.bind("<B1-Motion>", self.update_selection)
        self.canvas.bind("<ButtonRelease-1>", self.finish_selection)

        self.status = tk.Label(
            content,
            text="PDF 열기를 눌러 문서를 선택하세요.",
            anchor="w",
            padx=14,
            pady=7,
            bg="#0f172a",
            fg="white",
            font=("Malgun Gothic", 10),
        )
        self.status.pack(fill="x")

    def _button(self, parent: tk.Widget, label: str, command, style: str = "Action.TButton") -> ttk.Button:
        return ttk.Button(parent, text=label, command=command, style=style)

    def _side_title(self, parent: tk.Widget, text: str) -> None:
        tk.Label(parent, text=text, bg="#f8fafc", fg="#475569", font=("Malgun Gothic", 9, "bold")).pack(anchor="w", pady=(12, 5))

    def open_pdf(self) -> None:
        selected = filedialog.askopenfilename(
            title="PDF 파일 선택", filetypes=[("PDF 문서", "*.pdf")]
        )
        if not selected:
            return
        try:
            if self.document:
                self.document.close()
            self.document = pymupdf.open(selected)
            self.document_path = Path(selected)
            self.page_number = 0
            self.zoom = 1.2
            self.bookmarks.clear()
            self.search_matches.clear()
            self.search_index = -1
            self.file_label.config(text=self.document_path.name)
            self.draw_page()
        except Exception as error:
            messagebox.showerror("CY뷰어", f"PDF를 열 수 없습니다.\n\n{error}")

    def draw_page(self) -> None:
        if not self.canvas.winfo_width():
            return
        if not self.document:
            self.canvas.delete("all")
            width, height = self.canvas.winfo_width(), self.canvas.winfo_height()
            self.canvas.create_text(
                width // 2,
                height // 2 - 20,
                text="CY뷰어에 오신 것을 환영합니다",
                fill="white",
                font=("Malgun Gothic", 20, "bold"),
            )
            self.canvas.create_text(
                width // 2,
                height // 2 + 24,
                text="왼쪽의 ‘PDF 열기’ 버튼을 눌러 문서를 선택하세요.",
                fill="#e2e8f0",
                font=("Malgun Gothic", 11),
            )
            return
        page = self.document[self.page_number]
        pixmap = page.get_pixmap(matrix=pymupdf.Matrix(self.zoom, self.zoom), alpha=False)
        image = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)
        self.page_image = ImageTk.PhotoImage(image)
        self.canvas.delete("all")
        width, height = self.canvas.winfo_width(), self.canvas.winfo_height()
        left = max((width - pixmap.width) // 2, 10)
        top = max((height - pixmap.height) // 2, 10)
        self.page_left, self.page_top = left, top
        self.canvas.create_image(left, top, anchor="nw", image=self.page_image)
        for page_no, rect in self.search_matches:
            if page_no == self.page_number:
                self.canvas.create_rectangle(
                    left + rect.x0 * self.zoom,
                    top + rect.y0 * self.zoom,
                    left + rect.x1 * self.zoom,
                    top + rect.y1 * self.zoom,
                    outline="#ef4444",
                    width=2,
                )
        bookmark = "  ★ 책갈피" if self.page_number in self.bookmarks else ""
        selection = "  |  텍스트 선택됨" if self.selected_rect else ""
        self.status.config(
            text=f"{self.page_number + 1} / {len(self.document)} 페이지   |   확대 {int(self.zoom * 100)}%{bookmark}{selection}"
        )

    def _canvas_to_page(self, x: int, y: int) -> pymupdf.Point:
        return pymupdf.Point(
            (x - self.page_left) / self.zoom,
            (y - self.page_top) / self.zoom,
        )

    def start_selection(self, event) -> None:
        if not self.document:
            return
        self.selection_start = (event.x, event.y)
        self.selected_rect = None
        self.selection_preview = None

    def update_selection(self, event) -> None:
        if not self.selection_start:
            return
        start_x, start_y = self.selection_start
        if self.selection_preview:
            self.canvas.delete(self.selection_preview)
        self.selection_preview = self.canvas.create_rectangle(
            start_x,
            start_y,
            event.x,
            event.y,
            outline="#2563eb",
            dash=(4, 2),
            width=2,
        )

    def finish_selection(self, event) -> None:
        if not self.document or not self.selection_start:
            return
        start_x, start_y = self.selection_start
        self.selection_start = None
        if self.selection_preview:
            self.canvas.delete(self.selection_preview)
            self.selection_preview = None
        rect = pymupdf.Rect(self._canvas_to_page(start_x, start_y), self._canvas_to_page(event.x, event.y))
        rect = rect & self.document[self.page_number].rect
        self.selected_rect = rect if rect.width > 3 and rect.height > 3 else None
        if self.selected_rect:
            words = self._selected_text()
            preview = words[:45] + ("…" if len(words) > 45 else "")
            self.selection_label.config(text=f"선택한 문구\n{preview}\n\n왼쪽에서 편집 기능을 선택하세요.")
        else:
            self.selection_label.config(text="문구를 드래그해 선택하면\n형광펜·밑줄·취소선·굵게·문구 수정이 가능합니다.")
        self.draw_page()

    def _selected_text(self) -> str:
        if not self.document or not self.selected_rect:
            return ""
        words = self.document[self.page_number].get_text("words")
        selected = [word[4] for word in words if pymupdf.Rect(word[:4]).intersects(self.selected_rect)]
        return " ".join(selected)

    def _require_selection(self) -> pymupdf.Rect | None:
        if not self.document or not self.selected_rect:
            messagebox.showinfo("CY뷰어", "문서에서 문구를 드래그해 먼저 선택하세요.")
            return None
        return self.selected_rect

    def mark_selection(self, kind: str) -> None:
        rect = self._require_selection()
        if not rect or not self.document:
            return
        page = self.document[self.page_number]
        if kind == "highlight":
            annotation = page.add_highlight_annot(rect)
        elif kind == "underline":
            annotation = page.add_underline_annot(rect)
        else:
            annotation = page.add_strikeout_annot(rect)
        annotation.update()
        self.selected_rect = None
        self.draw_page()

    def _replace_selected_text(self, text: str, bold: bool) -> None:
        rect = self._require_selection()
        if not rect or not self.document:
            return
        page = self.document[self.page_number]
        page.add_redact_annot(rect, fill=(1, 1, 1))
        page.apply_redactions()
        font_path = Path("C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf")
        font_kwargs = {"fontname": "malgun", "fontfile": str(font_path)} if font_path.exists() else {"fontname": "helv"}
        page.insert_textbox(
            rect,
            text,
            fontsize=max(8, min(18, rect.height * 0.7)),
            color=(0, 0, 0),
            **font_kwargs,
        )
        self.selected_rect = None
        self.draw_page()

    def bold_selection(self) -> None:
        text = self._selected_text()
        if not text:
            self._require_selection()
            return
        self._replace_selected_text(text, bold=True)

    def edit_selection(self) -> None:
        original = self._selected_text()
        if not original:
            self._require_selection()
            return
        changed = simpledialog.askstring("문구 수정", "새 문구를 입력하세요.", initialvalue=original, parent=self)
        if changed is not None and changed.strip():
            self._replace_selected_text(changed.strip(), bold=False)

    def save_as(self) -> None:
        if not self.document:
            return
        selected = filedialog.asksaveasfilename(
            title="편집한 PDF 저장",
            defaultextension=".pdf",
            filetypes=[("PDF 문서", "*.pdf")],
        )
        if not selected:
            return
        try:
            self.document.save(selected)
            messagebox.showinfo("CY뷰어", "편집한 PDF를 저장했습니다.")
        except Exception as error:
            messagebox.showerror("CY뷰어", f"저장할 수 없습니다.\n\n{error}")

    def previous_page(self) -> None:
        if self.document and self.page_number > 0:
            self.page_number -= 1
            self.draw_page()

    def next_page(self) -> None:
        if self.document and self.page_number < len(self.document) - 1:
            self.page_number += 1
            self.draw_page()

    def change_zoom(self, change: float) -> None:
        if self.document:
            self.zoom = max(0.5, min(3.0, round(self.zoom + change, 1)))
            self.draw_page()

    def _wheel_zoom(self, event) -> None:
        if event.state & 0x0004:
            self.change_zoom(0.1 if event.delta > 0 else -0.1)
        elif event.delta > 0:
            self.previous_page()
        else:
            self.next_page()

    def go_to_page(self) -> None:
        if not self.document:
            return
        value = simpledialog.askinteger(
            "페이지 이동", f"이동할 페이지 번호를 입력하세요. (1~{len(self.document)})", parent=self
        )
        if value and 1 <= value <= len(self.document):
            self.page_number = value - 1
            self.draw_page()

    def toggle_bookmark(self) -> None:
        if not self.document:
            return
        if self.page_number in self.bookmarks:
            self.bookmarks.remove(self.page_number)
        else:
            self.bookmarks.add(self.page_number)
        self.draw_page()

    def show_bookmarks(self) -> None:
        if not self.document:
            return
        if not self.bookmarks:
            messagebox.showinfo("CY뷰어", "저장된 책갈피가 없습니다.")
            return
        options = ", ".join(str(page + 1) for page in sorted(self.bookmarks))
        value = simpledialog.askinteger("책갈피 목록", f"저장된 페이지: {options}\n이동할 페이지 번호:", parent=self)
        if value and value - 1 in self.bookmarks:
            self.page_number = value - 1
            self.draw_page()

    def find_next(self) -> None:
        if not self.document:
            return
        query = self.search_entry.get().strip()
        if not query:
            return
        if query != self.search_text:
            self.search_text = query
            self.search_matches = []
            for number, page in enumerate(self.document):
                self.search_matches.extend((number, rect) for rect in page.search_for(query))
            self.search_index = -1
        if not self.search_matches:
            self.search_status.config(text="결과 없음")
            self.draw_page()
            return
        self.search_index = (self.search_index + 1) % len(self.search_matches)
        self.page_number = self.search_matches[self.search_index][0]
        self.search_status.config(text=f"{self.search_index + 1}/{len(self.search_matches)}")
        self.draw_page()


if __name__ == "__main__":
    CyViewer().mainloop()
