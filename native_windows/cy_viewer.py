"""CY뷰어 - Windows용 개인 PDF 뷰어."""

from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

import pymupdf
from PIL import Image, ImageTk


COLORS = {
    "ink": "#0F172A",
    "muted": "#64748B",
    "line": "#E2E8F0",
    "surface": "#FFFFFF",
    "canvas": "#EAF0F6",
    "blue": "#2563EB",
    "blue_soft": "#E0F2FE",
    "green": "#15803D",
    "red": "#DC2626",
    "sidebar": "#F8FAFC",
}


class CyViewer(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("CY뷰어 | 개인용 PDF 뷰어")
        self.geometry("1280x820")
        self.minsize(780, 560)
        self.configure(bg=COLORS["canvas"])

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
        self.is_dirty = False
        self.save_state = "새 문서 없음"

        self._make_ui()

    def _make_ui(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Action.TButton", font=("Malgun Gothic", 10), padding=(10, 8), background=COLORS["surface"], foreground=COLORS["ink"], bordercolor=COLORS["line"])
        style.map("Action.TButton", background=[("active", COLORS["blue_soft"]), ("pressed", "#DBEAFE")])
        style.configure("Primary.TButton", font=("Malgun Gothic", 10, "bold"), padding=(12, 9), background=COLORS["blue"], foreground="white", bordercolor=COLORS["blue"])
        style.map("Primary.TButton", background=[("active", "#1D4ED8"), ("pressed", "#1E40AF")])

        header = tk.Frame(self, bg=COLORS["ink"], padx=24, pady=14)
        header.pack(fill="x")
        tk.Label(
            header,
            text="CY뷰어",
            fg="white",
            bg=COLORS["ink"],
            font=("Malgun Gothic", 18, "bold"),
        ).pack(side="left")
        self.file_label = tk.Label(
            header,
            text="PDF 편집 작업 공간 · 문서를 열어 시작하세요",
            fg="#CBD5E1",
            bg=COLORS["ink"],
            font=("Malgun Gothic", 10),
        )
        self.file_label.pack(side="left", padx=18)
        self.save_badge = tk.Label(header, text=self.save_state, fg="#BFDBFE", bg="#1E3A5F", padx=10, pady=4, font=("Malgun Gothic", 9, "bold"))
        self.save_badge.pack(side="right")

        workspace = tk.Frame(self, bg=COLORS["line"])
        workspace.pack(fill="both", expand=True)
        sidebar = tk.Frame(workspace, width=270, bg=COLORS["sidebar"], padx=16, pady=18)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)
        self._button(sidebar, "＋ PDF 열기", self.open_pdf, "Primary.TButton").pack(fill="x", pady=(0, 18))
        navigation = self._section(sidebar, "01  문서 탐색")
        self._button(navigation, "◀  이전 페이지", self.previous_page).pack(fill="x", pady=2)
        self._button(navigation, "다음 페이지  ▶", self.next_page).pack(fill="x", pady=2)
        self._button(navigation, "페이지로 이동", self.go_to_page).pack(fill="x", pady=2)
        self._button(navigation, "☆  이 페이지 책갈피", self.toggle_bookmark).pack(fill="x", pady=2)
        self._button(navigation, "책갈피 목록", self.show_bookmarks).pack(fill="x", pady=2)
        editing = self._section(sidebar, "02  선택 · 표시 · 수정")
        self._button(editing, "형광펜 표시", lambda: self.mark_selection("highlight")).pack(fill="x", pady=2)
        self._button(editing, "밑줄", lambda: self.mark_selection("underline")).pack(fill="x", pady=2)
        self._button(editing, "취소선", lambda: self.mark_selection("strike")).pack(fill="x", pady=2)
        self._button(editing, "굵게 처리", self.bold_selection).pack(fill="x", pady=2)
        self._button(editing, "문구 수정", self.edit_selection).pack(fill="x", pady=2)
        self._side_title(sidebar, "03  사본으로 저장")
        self._button(sidebar, "PDF로 저장", self.save_as, "Primary.TButton").pack(fill="x", pady=(14, 4))
        selection_card = tk.Frame(sidebar, bg=COLORS["blue_soft"], padx=10, pady=10)
        selection_card.pack(fill="both", expand=True, pady=(16, 0))
        self.selection_label = tk.Label(
            selection_card, text="선택 검사", justify="left", anchor="w",
            bg=COLORS["blue_soft"], fg="#0C4A6E", font=("Malgun Gothic", 9, "bold"),
        )
        self.selection_label.pack(fill="x")
        self.selection_details = tk.Text(
            selection_card, height=8, wrap="word", relief="flat", bd=0,
            bg=COLORS["blue_soft"], fg="#0C4A6E", font=("Malgun Gothic", 9),
            highlightthickness=0, padx=0, pady=7,
        )
        self.selection_details.pack(fill="both", expand=True)
        self.selection_details.config(state="disabled")
        self._set_selection_details("문구, 이미지 또는 빈 공간을\n드래그해 선택하면 이곳에서\n선택한 내용을 확인할 수 있어요.")

        content = tk.Frame(workspace, bg=COLORS["canvas"])
        content.pack(side="left", fill="both", expand=True)
        tools = tk.Frame(content, bg=COLORS["surface"], padx=18, pady=10)
        tools.pack(fill="x")
        tk.Label(tools, text="읽기", bg=COLORS["blue_soft"], fg="#1D4ED8", padx=9, pady=4, font=("Malgun Gothic", 9, "bold")).pack(side="left", padx=(0, 12))
        self._button(tools, "−", lambda: self.change_zoom(-0.2)).pack(side="left", padx=2)
        self._button(tools, "+", lambda: self.change_zoom(0.2)).pack(side="left", padx=2)
        tk.Label(tools, text="Ctrl + 휠: 확대/축소", bg=COLORS["surface"], fg=COLORS["muted"], font=("Malgun Gothic", 9)).pack(side="left", padx=10)
        search_box = tk.Frame(tools, bg=COLORS["surface"])
        search_box.pack(side="right")
        self.search_entry = ttk.Entry(search_box, width=24)
        self.search_entry.pack(side="left", padx=(0, 4))
        self.search_entry.bind("<Return>", lambda _: self.find_next())
        self._button(search_box, "검색", self.find_next).pack(side="left", padx=3)
        self.search_status = tk.Label(search_box, text="", bg=COLORS["surface"], fg=COLORS["muted"])
        self.search_status.pack(side="left", padx=5)

        self.canvas = tk.Canvas(content, bg=COLORS["canvas"], highlightthickness=0)
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
            bg=COLORS["ink"],
            fg="white",
            font=("Malgun Gothic", 10),
        )
        self.status.pack(fill="x")

    def _button(self, parent: tk.Widget, label: str, command, style: str = "Action.TButton") -> ttk.Button:
        return ttk.Button(parent, text=label, command=command, style=style)

    def _side_title(self, parent: tk.Widget, text: str) -> None:
        tk.Label(parent, text=text, bg=COLORS["sidebar"], fg="#475569", font=("Malgun Gothic", 9, "bold")).pack(anchor="w", pady=(12, 5))

    def _section(self, parent: tk.Widget, title: str) -> tk.Frame:
        self._side_title(parent, title)
        section = tk.Frame(parent, bg=COLORS["sidebar"])
        section.pack(fill="x")
        return section

    def _set_save_state(self, state: str, color: str = "#BFDBFE", background: str = "#1E3A5F") -> None:
        self.save_state = state
        self.save_badge.config(text=state, fg=color, bg=background)

    def _mark_dirty(self, message: str) -> None:
        self.is_dirty = True
        self._set_save_state("저장 필요", "#FEF3C7", "#92400E")
        self.status.config(text=message + "  |  오른쪽이 아닌 왼쪽 아래 ‘PDF로 저장’으로 사본을 보관하세요.")

    def _set_selection_details(self, text: str) -> None:
        self.selection_details.config(state="normal")
        self.selection_details.delete("1.0", "end")
        self.selection_details.insert("1.0", text)
        self.selection_details.config(state="disabled")

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
            self.selected_rect = None
            self.is_dirty = False
            self.file_label.config(text=f"{self.document_path.name} · 읽기 및 편집 가능")
            self._set_save_state("변경 없음")
            self.selection_label.config(text="선택 검사")
            self._set_selection_details("문구, 이미지 또는 빈 공간을\n드래그해 선택하면 이곳에서\n선택한 내용을 확인할 수 있어요.")
            self.draw_page()
        except Exception as error:
            messagebox.showerror("CY뷰어", f"PDF를 열 수 없습니다.\n\n{error}")

    def draw_page(self) -> None:
        if not self.canvas.winfo_width():
            return
        if not self.document:
            self.canvas.delete("all")
            width, height = self.canvas.winfo_width(), self.canvas.winfo_height()
            self.canvas.create_rectangle(
                width // 2 - 245, height // 2 - 116, width // 2 + 245, height // 2 + 116,
                fill="#FFFFFF", outline=COLORS["line"], width=1,
            )
            self.canvas.create_text(
                width // 2,
                height // 2 - 52,
                text="CY뷰어에서 PDF를 편집하세요",
                fill=COLORS["ink"],
                font=("Malgun Gothic", 20, "bold"),
            )
            self.canvas.create_text(
                width // 2,
                height // 2 - 10,
                text="열기 → 읽기·검색 → 문구 드래그 → 표시 또는 수정 → 저장",
                fill=COLORS["muted"],
                font=("Malgun Gothic", 11),
            )
            self.canvas.create_text(width // 2, height // 2 + 48, text="왼쪽의 ‘PDF 열기’ 버튼으로 시작하세요.", fill=COLORS["blue"], font=("Malgun Gothic", 10, "bold"))
            self.status.config(text="PDF 열기를 눌러 문서를 선택하세요.")
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
        if self.selected_rect:
            rect = self.selected_rect
            self.canvas.create_rectangle(
                left + rect.x0 * self.zoom,
                top + rect.y0 * self.zoom,
                left + rect.x1 * self.zoom,
                top + rect.y1 * self.zoom,
                outline=COLORS["blue"],
                dash=(4, 2),
                width=2,
            )
        bookmark = "  ★ 책갈피" if self.page_number in self.bookmarks else ""
        selection = "  |  문구 선택됨: 왼쪽에서 표시 또는 수정" if self.selected_rect else ""
        dirty = "  |  저장 필요" if self.is_dirty else ""
        self.status.config(
            text=f"{self.page_number + 1} / {len(self.document)} 페이지   |   확대 {int(self.zoom * 100)}%{bookmark}{selection}{dirty}"
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
            self._inspect_selection()
        else:
            self.selection_label.config(text="선택 검사")
            self._set_selection_details("유효한 영역이 선택되지 않았습니다.\n문구, 이미지 또는 빈 공간을\n조금 더 넓게 드래그해 보세요.")
        self.draw_page()

    def _selected_text(self) -> str:
        if not self.document or not self.selected_rect:
            return ""
        words = self.document[self.page_number].get_text("words")
        selected = [word[4] for word in words if pymupdf.Rect(word[:4]).intersects(self.selected_rect)]
        return " ".join(selected)

    def _inspect_selection(self) -> None:
        if not self.document or not self.selected_rect:
            return
        page = self.document[self.page_number]
        text = self._selected_text()
        image_count = 0
        for block in page.get_text("dict").get("blocks", []):
            if block.get("type") != 1:
                continue
            block_rect = pymupdf.Rect(block["bbox"])
            if block_rect.intersects(self.selected_rect):
                image_count += 1

        parts: list[str] = []
        if text:
            parts.append("텍스트")
        if image_count:
            parts.append(f"이미지 {image_count}개")
        if not parts:
            parts.append("빈 공간")
        self.selection_label.config(text="선택 검사 · " + " · ".join(parts))

        details = [f"선택 종류: {', '.join(parts)}"]
        if text:
            details.extend(["", "선택한 텍스트", text, "", "텍스트는 형광펜·밑줄·취소선·굵게·문구 수정을 사용할 수 있습니다."])
        elif image_count:
            details.extend(["", "선택 영역에 이미지가 있습니다.", "현재 버전에서는 이미지를 확인할 수 있으며, 이미지 편집 기능은 준비 중입니다."])
        else:
            details.extend(["", "선택 영역에 텍스트나 이미지가 없습니다.", "빈 공간에는 표시·문구 수정 기능을 적용할 수 없습니다."])
        self._set_selection_details("\n".join(details))

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
        label = {"highlight": "형광펜", "underline": "밑줄", "strike": "취소선"}[kind]
        self._mark_dirty(f"{label} 표시를 적용했습니다.")
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
        self._mark_dirty("문구를 변경했습니다." if not bold else "선택 문구를 굵게 처리했습니다.")
        self.draw_page()

    def bold_selection(self) -> None:
        text = self._selected_text()
        if not text:
            self._require_selection()
            return
        if messagebox.askyesno("굵게 처리", "선택 문구를 굵게 바꿉니다. 이 변경은 저장 전까지 되돌릴 수 없습니다. 계속할까요?", parent=self):
            self._replace_selected_text(text, bold=True)

    def edit_selection(self) -> None:
        original = self._selected_text()
        if not original:
            self._require_selection()
            return
        changed = simpledialog.askstring("문구 수정", "새 문구를 입력하세요.", initialvalue=original, parent=self)
        if changed is not None and changed.strip():
            if messagebox.askyesno("문구 수정", "기존 문구를 새 문구로 바꿉니다. 이 변경은 저장 전까지 되돌릴 수 없습니다. 계속할까요?", parent=self):
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
            self.is_dirty = False
            self._set_save_state("저장 완료", "#DCFCE7", "#166534")
            self.status.config(text=f"저장 완료 · {Path(selected).name}")
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
