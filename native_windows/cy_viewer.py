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

        self._make_ui()

    def _make_ui(self) -> None:
        header = tk.Frame(self, bg="#102a43", padx=16, pady=12)
        header.pack(fill="x")
        tk.Label(
            header,
            text="CY뷰어",
            fg="white",
            bg="#102a43",
            font=("Malgun Gothic", 18, "bold"),
        ).pack(side="left")
        self.file_label = tk.Label(
            header,
            text="PDF 파일을 열어 주세요",
            fg="#d9e2ec",
            bg="#102a43",
            font=("Malgun Gothic", 10),
        )
        self.file_label.pack(side="left", padx=18)

        tools = tk.Frame(self, bg="#d9e2ec", padx=10, pady=8)
        tools.pack(fill="x")
        self._button(tools, "PDF 열기", self.open_pdf).pack(side="left", padx=3)
        self._button(tools, "◀ 이전", self.previous_page).pack(side="left", padx=3)
        self._button(tools, "다음 ▶", self.next_page).pack(side="left", padx=3)
        self._button(tools, "− 축소", lambda: self.change_zoom(-0.2)).pack(side="left", padx=3)
        self._button(tools, "+ 확대", lambda: self.change_zoom(0.2)).pack(side="left", padx=3)
        self._button(tools, "페이지 이동", self.go_to_page).pack(side="left", padx=3)
        self._button(tools, "☆ 책갈피", self.toggle_bookmark).pack(side="left", padx=3)
        self._button(tools, "책갈피 목록", self.show_bookmarks).pack(side="left", padx=3)

        search_box = tk.Frame(tools, bg="#d9e2ec")
        search_box.pack(side="right")
        self.search_entry = ttk.Entry(search_box, width=24)
        self.search_entry.pack(side="left", padx=(0, 4))
        self.search_entry.bind("<Return>", lambda _: self.find_next())
        self._button(search_box, "검색", self.find_next).pack(side="left", padx=3)
        self.search_status = tk.Label(search_box, text="", bg="#d9e2ec")
        self.search_status.pack(side="left", padx=5)

        self.canvas = tk.Canvas(self, bg="#9aa5b1", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", lambda _: self.draw_page())
        self.canvas.bind("<MouseWheel>", self._wheel_zoom)

        self.status = tk.Label(
            self,
            text="PDF 열기를 눌러 문서를 선택하세요.",
            anchor="w",
            padx=14,
            pady=7,
            bg="#243b53",
            fg="white",
            font=("Malgun Gothic", 10),
        )
        self.status.pack(fill="x")

    def _button(self, parent: tk.Widget, label: str, command) -> ttk.Button:
        return ttk.Button(parent, text=label, command=command)

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
        if not self.document or not self.canvas.winfo_width():
            return
        page = self.document[self.page_number]
        pixmap = page.get_pixmap(matrix=pymupdf.Matrix(self.zoom, self.zoom), alpha=False)
        image = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)
        self.page_image = ImageTk.PhotoImage(image)
        self.canvas.delete("all")
        width, height = self.canvas.winfo_width(), self.canvas.winfo_height()
        left = max((width - pixmap.width) // 2, 10)
        top = max((height - pixmap.height) // 2, 10)
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
        self.status.config(
            text=f"{self.page_number + 1} / {len(self.document)} 페이지   |   확대 {int(self.zoom * 100)}%{bookmark}"
        )

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
