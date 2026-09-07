"""CY뷰어 - Windows용 개인 PDF 뷰어."""

from __future__ import annotations

import tkinter as tk
import csv
import ctypes
import io
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

import pymupdf
import win32ui
from PIL import Image, ImageDraw, ImageTk, ImageWin
from tkinterdnd2 import DND_FILES, TkinterDnD


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


class RoundedButton(tk.Canvas):
    """Tk 기본 버튼 대신 사용하는 일관된 작업 버튼."""

    def __init__(self, parent: tk.Widget, text: str, command, variant: str = "secondary") -> None:
        compact = text in {"+", "−", "☆"}
        self.height = 38 if compact else 42
        self.radius = 8
        self.command = command
        self.text = text
        self.variant = variant
        self.hovered = False
        self.pressed = False
        super().__init__(
            parent,
            height=self.height,
            width=42 if compact else 220,
            bg=parent.cget("bg"),
            highlightthickness=0,
            bd=0,
            cursor="hand2",
        )
        self.bind("<Configure>", lambda _: self._draw())
        self.bind("<Enter>", self._enter)
        self.bind("<Leave>", self._leave)
        self.bind("<ButtonPress-1>", self._press)
        self.bind("<ButtonRelease-1>", self._release)
        self._draw()

    def _palette(self) -> tuple[str, str]:
        if self.variant == "primary":
            return ("#1D4ED8" if self.hovered else COLORS["blue"], "#FFFFFF")
        return ("#E8F0FE" if self.hovered else COLORS["surface"], COLORS["ink"])

    def _draw(self) -> None:
        self.delete("all")
        width, height = max(self.winfo_width(), 2), self.height
        radius = min(self.radius, height // 2, width // 2)
        background, foreground = self._palette()
        outline = background if self.variant == "primary" else ("#C7D2E0" if not self.hovered else "#93C5FD")
        surface = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        ImageDraw.Draw(surface).rounded_rectangle(
            (0, 0, width - 1, height - 1), radius=radius, fill=background, outline=outline, width=1
        )
        self.surface_image = ImageTk.PhotoImage(surface)
        self.create_image(0, 0, anchor="nw", image=self.surface_image)
        self.create_text(width // 2, height // 2, text=self.text, fill=foreground, font=("Malgun Gothic", 10, "bold" if self.variant == "primary" else "normal"))

    def _enter(self, _) -> None:
        self.hovered = True
        self._draw()

    def _leave(self, _) -> None:
        self.hovered = False
        self.pressed = False
        self._draw()

    def _press(self, _) -> None:
        self.pressed = True

    def _release(self, event) -> None:
        was_pressed = self.pressed
        self.pressed = False
        self._draw()
        if was_pressed and 0 <= event.x <= self.winfo_width() and 0 <= event.y <= self.height:
            self.command()


class CyViewer(TkinterDnD.Tk):
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
        self.view_mode = "scroll"
        self.bookmarks: set[int] = set()
        self.search_text = ""
        self.search_matches: list[tuple[int, pymupdf.Rect]] = []
        self.search_index = -1
        self.ocr_words: dict[int, list[tuple[pymupdf.Rect, str]]] = {}
        self.page_image: ImageTk.PhotoImage | None = None
        self.page_images: list[ImageTk.PhotoImage] = []
        self.page_layouts: dict[int, tuple[int, int, int, int]] = {}
        self.page_left = 0
        self.page_top = 0
        self.selected_rect: pymupdf.Rect | None = None
        self.selection_regions: list[pymupdf.Rect] = []
        self.selection_start: tuple[int, int] | None = None
        self.selection_kind = "none"
        self.selection_preview: int | None = None
        self.is_dirty = False
        self.save_state = "새 문서 없음"

        self._make_ui()
        self.drop_target_register(DND_FILES)
        self.dnd_bind("<<Drop>>", self.drop_pdf)

    def _make_ui(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")

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

        workspace = tk.Frame(self, bg="#EEF3F8")
        workspace.pack(fill="both", expand=True)
        sidebar = tk.Frame(workspace, width=278, bg="#F7F9FC", padx=16, pady=20)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)
        self._button(sidebar, "＋  PDF 열기", self.open_pdf, "Primary.TButton").pack(fill="x", pady=(0, 20))
        navigation = self._section(sidebar, "01  문서 탐색")
        page_controls = tk.Frame(navigation, bg=COLORS["sidebar"])
        page_controls.pack(fill="x", pady=(0, 8))
        previous = self._button(page_controls, "◀ 이전", self.previous_page)
        previous.configure(width=1)
        previous.grid(row=0, column=0, sticky="ew")
        go_to = self._button(page_controls, "이동", self.go_to_page)
        go_to.configure(width=1)
        go_to.grid(row=0, column=1, sticky="ew", padx=6)
        following = self._button(page_controls, "다음 ▶", self.next_page)
        following.configure(width=1)
        following.grid(row=0, column=2, sticky="ew")
        for column in range(3):
            page_controls.grid_columnconfigure(column, weight=1, uniform="page_navigation")
        quick_actions = tk.Frame(navigation, bg=COLORS["sidebar"])
        quick_actions.pack(fill="x")
        self._button(quick_actions, "☆", self.toggle_bookmark).pack(side="left")
        self._button(quick_actions, "OCR", self.ocr_document).pack(side="left", fill="x", expand=True, padx=(8, 0))
        editing = tk.Frame(sidebar, bg="#F7F9FC")
        editing.pack(fill="x", pady=(16, 0))
        tk.Label(
            editing,
            text="문구를 드래그해 선택한 뒤\n마우스 오른쪽 버튼을 누르세요.\n\n형광펜 · 밑줄 · 취소선 · 굵게\n문구 수정 · 텍스트 복사를 제공합니다.",
            justify="left", anchor="w", bg=COLORS["sidebar"], fg=COLORS["muted"],
            font=("Malgun Gothic", 9),
        ).pack(fill="x", pady=(0, 6))
        save_actions = tk.Frame(sidebar, bg="#F7F9FC")
        save_actions.pack(fill="x", pady=(16, 0))
        self._button(save_actions, "PDF로 저장", self.save_as, "Primary.TButton").pack(fill="x", pady=(0, 8))
        image_saves = tk.Frame(save_actions, bg="#F7F9FC")
        image_saves.pack(fill="x", pady=(0, 8))
        jpg_button = self._button(image_saves, "JPG로 저장", lambda: self.export_page("jpg"))
        jpg_button.configure(width=1)
        jpg_button.grid(row=0, column=0, sticky="ew")
        png_button = self._button(image_saves, "PNG로 저장", lambda: self.export_page("png"))
        png_button.configure(width=1)
        png_button.grid(row=0, column=1, sticky="ew", padx=(8, 0))
        image_saves.grid_columnconfigure(0, weight=1, uniform="image_save")
        image_saves.grid_columnconfigure(1, weight=1, uniform="image_save")
        self._button(save_actions, "인쇄", self.print_document).pack(fill="x")
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
        self._set_selection_details("문구를 드래그해 선택하면\n이곳에서 선택한 내용을\n확인할 수 있어요.")

        content = tk.Frame(workspace, bg="#EEF3F8")
        content.pack(side="left", fill="both", expand=True)
        tools = tk.Frame(content, bg=COLORS["surface"], padx=20, pady=13)
        tools.pack(fill="x", padx=16, pady=(16, 10))
        tk.Label(tools, text="읽기", bg=COLORS["blue_soft"], fg="#1D4ED8", padx=9, pady=4, font=("Malgun Gothic", 9, "bold")).pack(side="left", padx=(0, 12))
        self.view_mode_var = tk.StringVar(value="스크롤 보기")
        view_selector = ttk.Combobox(tools, textvariable=self.view_mode_var, state="readonly", width=11, values=("스크롤 보기", "좌우 보기"), font=("Malgun Gothic", 9))
        view_selector.pack(side="left", padx=(0, 12), ipady=4)
        view_selector.bind("<<ComboboxSelected>>", self._change_view_mode)
        self.selection_state = tk.Label(
            tools, text="선택 없음", bg="#F1F5F9", fg=COLORS["muted"],
            padx=10, pady=4, font=("Malgun Gothic", 9, "bold"),
        )
        self.selection_state.pack(side="left", padx=(0, 12))
        self._button(tools, "−", lambda: self.change_zoom(-0.2)).pack(side="left", padx=2)
        self._button(tools, "+", lambda: self.change_zoom(0.2)).pack(side="left", padx=2)
        tk.Label(tools, text="Ctrl + 휠: 확대/축소", bg=COLORS["surface"], fg=COLORS["muted"], font=("Malgun Gothic", 9)).pack(side="left", padx=10)
        search_box = tk.Frame(tools, bg="#F1F5F9", padx=8, pady=6)
        search_box.pack(side="right")
        tk.Label(search_box, text="문서 검색", bg="#F1F5F9", fg=COLORS["muted"], font=("Malgun Gothic", 9, "bold")).pack(side="left", padx=(2, 8))
        self.search_entry = ttk.Entry(search_box, width=22)
        self.search_entry.pack(side="left", padx=(0, 6))
        self.search_entry.bind("<Return>", lambda _: self.find_next())
        search_button = self._button(search_box, "검색", self.find_next)
        search_button.configure(width=70)
        search_button.pack(side="left")
        self.search_status = tk.Label(search_box, text="", bg="#F1F5F9", fg=COLORS["muted"], font=("Malgun Gothic", 9))
        self.search_status.pack(side="left", padx=(8, 2))

        canvas_frame = tk.Frame(content, bg="#DCE5EF")
        canvas_frame.pack(fill="both", expand=True, padx=16, pady=(0, 12))
        self.canvas = tk.Canvas(canvas_frame, bg="#DCE5EF", highlightthickness=0)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        self.canvas_vscroll = ttk.Scrollbar(canvas_frame, orient="vertical", command=self.canvas.yview)
        self.canvas_vscroll.grid(row=0, column=1, sticky="ns")
        self.canvas_hscroll = ttk.Scrollbar(canvas_frame, orient="horizontal", command=self.canvas.xview)
        self.canvas_hscroll.grid(row=1, column=0, sticky="ew")
        canvas_frame.rowconfigure(0, weight=1)
        canvas_frame.columnconfigure(0, weight=1)
        self.canvas.configure(yscrollcommand=self.canvas_vscroll.set, xscrollcommand=self.canvas_hscroll.set)
        self.canvas.bind("<Configure>", lambda _: self.draw_page())
        self.canvas.bind("<MouseWheel>", self._wheel_zoom)
        self.canvas.bind("<ButtonPress-1>", self.start_selection)
        self.canvas.bind("<B1-Motion>", self.update_selection)
        self.canvas.bind("<ButtonRelease-1>", self.finish_selection)
        self.canvas.bind("<Button-3>", self.show_context_menu)
        self.canvas.drop_target_register(DND_FILES)
        self.canvas.dnd_bind("<<Drop>>", self.drop_pdf)
        self.context_menu = tk.Menu(self, tearoff=0, font=("Malgun Gothic", 10), bg=COLORS["surface"], fg=COLORS["ink"], activebackground=COLORS["blue_soft"], activeforeground=COLORS["ink"])
        self.context_menu.add_command(label="형광펜", command=lambda: self.mark_selection("highlight"))
        self.context_menu.add_command(label="밑줄", command=lambda: self.mark_selection("underline"))
        self.context_menu.add_command(label="취소선", command=lambda: self.mark_selection("strike"))
        self.context_menu.add_separator()
        self.context_menu.add_command(label="굵게 처리", command=self.bold_selection)
        self.context_menu.add_command(label="문구 수정", command=self.edit_selection)
        self.context_menu.add_command(label="텍스트 복사", command=self.copy_selected_text)

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
        self.status.pack(fill="x", padx=16, pady=(0, 16))

    def _button(self, parent: tk.Widget, label: str, command, style: str = "Action.TButton") -> RoundedButton:
        return RoundedButton(parent, label, command, "primary" if style == "Primary.TButton" else "secondary")

    def _side_title(self, parent: tk.Widget, text: str) -> None:
        tk.Label(parent, text=text, bg="#F7F9FC", fg="#475569", font=("Malgun Gothic", 10, "bold")).pack(anchor="w", pady=(16, 8))

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

    def _set_selection_feedback(self, text: str | None = None, kind: str = "none") -> None:
        if text:
            self.selection_state.config(text=f"텍스트 선택됨 · {len(text)}자", bg="#DBEAFE", fg="#1D4ED8")
        elif kind == "image":
            self.selection_state.config(text="이미지 선택됨", bg="#EDE9FE", fg="#6D28D9")
        else:
            self.selection_state.config(text="선택 없음", bg="#F1F5F9", fg=COLORS["muted"])

    def open_pdf(self) -> None:
        selected = filedialog.askopenfilename(
            title="PDF 파일 선택", filetypes=[("PDF 문서", "*.pdf")]
        )
        if not selected:
            return
        self.load_pdf(Path(selected))

    def drop_pdf(self, event) -> str:
        files = self.tk.splitlist(event.data)
        if not files:
            return "break"
        selected = Path(files[0])
        if selected.suffix.lower() != ".pdf":
            messagebox.showinfo("CY뷰어", "PDF 파일만 열 수 있습니다.")
            return "break"
        self.load_pdf(selected)
        return "break"

    def load_pdf(self, selected: Path) -> None:
        try:
            if self.document:
                self.document.close()
            self.document = pymupdf.open(str(selected))
            self.document_path = selected
            self.page_number = 0
            self.zoom = 1.2
            self.bookmarks.clear()
            self.search_matches.clear()
            self.search_index = -1
            self.ocr_words.clear()
            self.selected_rect = None
            self.selection_regions = []
            self.selection_kind = "none"
            self.is_dirty = False
            self.file_label.config(text=f"{self.document_path.name} · 읽기 및 편집 가능")
            self._set_save_state("변경 없음")
            self.selection_label.config(text="선택 검사")
            self._set_selection_details("문구를 드래그해 선택하면\n이곳에서 선택한 내용을\n확인할 수 있어요.")
            self._set_selection_feedback()
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
                text="PDF 열기 또는 끌어놓기\n읽기·검색 → 문구 선택 → 편집 → 저장",
                fill=COLORS["muted"],
                font=("Malgun Gothic", 11),
                justify="center",
                width=420,
            )
            self.canvas.create_text(width // 2, height // 2 + 48, text="왼쪽의 ‘PDF 열기’ 버튼으로 시작하세요.", fill=COLORS["blue"], font=("Malgun Gothic", 10, "bold"))
            self.status.config(text="PDF 열기를 눌러 문서를 선택하세요.")
            return
        self.canvas.delete("all")
        width, height = self.canvas.winfo_width(), self.canvas.winfo_height()
        self.page_images, self.page_layouts = [], {}
        pages = range(len(self.document)) if self.view_mode == "scroll" else range(self.page_number, min(self.page_number + 2, len(self.document)))
        rendered = []
        for page_no in pages:
            pixmap = self.document[page_no].get_pixmap(matrix=pymupdf.Matrix(self.zoom, self.zoom), alpha=False)
            photo = ImageTk.PhotoImage(Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples))
            self.page_images.append(photo)
            rendered.append((page_no, photo, pixmap.width, pixmap.height))
        gap, margin = 24, 20
        if self.view_mode == "scroll":
            top = margin
            content_width = max([width] + [item[2] + margin * 2 for item in rendered])
            for page_no, photo, page_width, page_height in rendered:
                left = max((content_width - page_width) // 2, margin)
                self._draw_rendered_page(page_no, photo, left, top, page_width, page_height)
                top += page_height + gap
            content_height = max(height, top)
        else:
            total_width = sum(item[2] for item in rendered) + gap * max(0, len(rendered) - 1)
            content_width = max(width, total_width + margin * 2)
            left = max((content_width - total_width) // 2, margin)
            max_height = 0
            for page_no, photo, page_width, page_height in rendered:
                self._draw_rendered_page(page_no, photo, left, margin, page_width, page_height)
                left += page_width + gap
                max_height = max(max_height, page_height)
            content_height = max(height, max_height + margin * 2)
        self.canvas.configure(scrollregion=(0, 0, content_width, content_height))
        if self.page_number in self.page_layouts:
            self.page_left, self.page_top = self.page_layouts[self.page_number][:2]
        bookmark = "  ★ 책갈피" if self.page_number in self.bookmarks else ""
        selection = "  |  문구 선택됨: 왼쪽에서 표시 또는 수정" if self.selected_rect else ""
        dirty = "  |  저장 필요" if self.is_dirty else ""
        self.status.config(
            text=f"{self.page_number + 1} / {len(self.document)} 페이지   |   {'스크롤 보기' if self.view_mode == 'scroll' else '좌우 보기'}   |   확대 {int(self.zoom * 100)}%{bookmark}{selection}{dirty}"
        )

    def _draw_rendered_page(self, page_no: int, photo: ImageTk.PhotoImage, left: int, top: int, width: int, height: int) -> None:
        self.page_layouts[page_no] = (left, top, width, height)
        self.canvas.create_image(left, top, anchor="nw", image=photo)
        for match_page, rect in self.search_matches:
            if match_page == page_no:
                self.canvas.create_rectangle(left + rect.x0 * self.zoom, top + rect.y0 * self.zoom, left + rect.x1 * self.zoom, top + rect.y1 * self.zoom, outline="#EF4444", width=2)
        if self.selected_rect and page_no == self.page_number:
            for rect in self.selection_regions or [self.selected_rect]:
                image_selection = self.selection_kind == "image"
                self.canvas.create_rectangle(left + rect.x0 * self.zoom, top + rect.y0 * self.zoom, left + rect.x1 * self.zoom, top + rect.y1 * self.zoom, fill="" if image_selection else "#60A5FA", stipple="" if image_selection else "gray50", outline="#7C3AED" if image_selection else "#2563EB", width=3 if image_selection else 1)

    def _change_view_mode(self, _event=None) -> None:
        self.view_mode = "spread" if self.view_mode_var.get() == "좌우 보기" else "scroll"
        if self.view_mode == "spread" and self.page_number % 2:
            self.page_number -= 1
        self.canvas.xview_moveto(0)
        self.canvas.yview_moveto(0)
        self.draw_page()

    def _canvas_to_page(self, x: int, y: int) -> pymupdf.Point:
        return pymupdf.Point(
            (x - self.page_left) / self.zoom,
            (y - self.page_top) / self.zoom,
        )

    def _page_at_canvas_point(self, x: float, y: float) -> int | None:
        for page_no, (left, top, width, height) in self.page_layouts.items():
            if left <= x <= left + width and top <= y <= top + height:
                return page_no
        return None

    def _image_rects(self, page_number: int) -> list[pymupdf.Rect]:
        if not self.document:
            return []
        return [pymupdf.Rect(block["bbox"]) for block in self.document[page_number].get_text("dict").get("blocks", []) if block.get("type") == 1]

    def start_selection(self, event) -> None:
        if not self.document:
            return
        canvas_x, canvas_y = self.canvas.canvasx(event.x), self.canvas.canvasy(event.y)
        selected_page = self._page_at_canvas_point(canvas_x, canvas_y)
        if selected_page is None:
            self.selection_start = None
            return
        self.page_number = selected_page
        self.page_left, self.page_top = self.page_layouts[selected_page][:2]
        self.selection_start = (canvas_x, canvas_y)
        self.selected_rect = None
        self.selection_regions = []
        self.selection_kind = "none"
        self.selection_preview = None
        self._set_selection_feedback()

    def update_selection(self, event) -> None:
        if not self.selection_start:
            return
        start_x, start_y = self.selection_start
        if self.selection_preview:
            self.canvas.delete(self.selection_preview)
        self.selection_preview = self.canvas.create_rectangle(
            start_x,
            start_y,
            self.canvas.canvasx(event.x),
            self.canvas.canvasy(event.y),
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
        end_x, end_y = self.canvas.canvasx(event.x), self.canvas.canvasy(event.y)
        rect = pymupdf.Rect(self._canvas_to_page(start_x, start_y), self._canvas_to_page(end_x, end_y))
        rect = rect & self.document[self.page_number].rect
        self.selected_rect = rect if rect.width > 3 and rect.height > 3 else None
        if self.selected_rect:
            word_rects = self._selected_word_rects()
            self.selection_regions = self._line_regions(word_rects)
            if word_rects:
                self.selection_kind = "text"
            elif any(image_rect.intersects(self.selected_rect) for image_rect in self._image_rects(self.page_number)):
                self.selection_kind = "image"
                self.selection_regions = [self.selected_rect]
            else:
                self.selected_rect = None
                self.selection_regions = []
                self.selection_kind = "none"
        if self.selected_rect:
            self._inspect_selection()
        else:
            self.selection_label.config(text="선택 검사")
            self._set_selection_details("유효한 영역이 선택되지 않았습니다.\n문구, 이미지 또는 빈 공간을\n조금 더 넓게 드래그해 보세요.")
            self._set_selection_feedback()
        self.draw_page()

    def _selected_text(self) -> str:
        return " ".join(text for _, text in self._selected_word_items())

    def _selected_word_items(self) -> list[tuple[pymupdf.Rect, str]]:
        if not self.document or not self.selected_rect:
            return []
        words = self.document[self.page_number].get_text("words")
        selected = [(pymupdf.Rect(word[:4]), word[4]) for word in words if pymupdf.Rect(word[:4]).intersects(self.selected_rect)]
        if not selected:
            selected = []
            for rect, text in self.ocr_words.get(self.page_number, []):
                intersection = rect & self.selected_rect
                if not intersection.is_empty and intersection.get_area() / max(rect.get_area(), 1) >= 0.35:
                    selected.append((rect, text))
            # 그림의 넓은 영역을 잡았을 때 그림 속 우연한 OCR 결과가 텍스트로
            # 오인되지 않도록, 실제 글자 상자가 차지하는 비율도 확인한다.
            if selected and any(rect.intersects(self.selected_rect) for rect in self._image_rects(self.page_number)):
                covered = sum((rect & self.selected_rect).get_area() for rect, _ in selected)
                if covered / max(self.selected_rect.get_area(), 1) < 0.08:
                    selected = []
        return selected

    def _selected_word_rects(self) -> list[pymupdf.Rect]:
        if not self.document or not self.selected_rect:
            return []
        return [rect for rect, _ in self._selected_word_items()]

    def _line_regions(self, word_rects: list[pymupdf.Rect]) -> list[pymupdf.Rect]:
        """단어를 줄별로 묶어, 줄 안의 띄어쓰기만 포함하는 선택 영역을 만든다."""
        regions: list[pymupdf.Rect] = []
        for rect in sorted(word_rects, key=lambda item: (item.y0, item.x0)):
            if regions and rect.y0 <= regions[-1].y1 + 2 and rect.y1 >= regions[-1].y0 - 2:
                current = regions[-1]
                regions[-1] = pymupdf.Rect(
                    min(current.x0, rect.x0), min(current.y0, rect.y0),
                    max(current.x1, rect.x1), max(current.y1, rect.y1),
                )
            else:
                regions.append(pymupdf.Rect(rect))
        return regions

    def _selection_bounds(self) -> pymupdf.Rect | None:
        if not self.selection_regions:
            return self.selected_rect
        bounds = pymupdf.Rect(self.selection_regions[0])
        for region in self.selection_regions[1:]:
            bounds.include_rect(region)
        return bounds

    def _selected_font_size(self) -> float:
        if not self.document or not self.selected_rect:
            return 10.0
        regions = self.selection_regions or [self.selected_rect]
        sizes: list[float] = []
        for block in self.document[self.page_number].get_text("dict").get("blocks", []):
            for line in block.get("lines", []):
                for span in line.get("spans", []):
                    span_rect = pymupdf.Rect(span["bbox"])
                    if any(span_rect.intersects(region) for region in regions):
                        sizes.append(float(span.get("size", 10)))
        if not sizes:
            return 10.0
        sizes.sort()
        return max(6.0, sizes[len(sizes) // 2])

    def _ocr_data_path(self) -> Path:
        base = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))
        return base / "tessdata"

    def _configure_ocr(self) -> tuple[Path, Path]:
        candidates = [
            Path("C:/Program Files/Tesseract-OCR/tesseract.exe"),
            Path("C:/Program Files (x86)/Tesseract-OCR/tesseract.exe"),
        ]
        executable = next((candidate for candidate in candidates if candidate.exists()), None)
        if not executable:
            raise RuntimeError("OCR 엔진을 찾을 수 없습니다. Tesseract OCR을 설치한 뒤 다시 시도하세요.")
        data_path = self._ocr_data_path()
        if not (data_path / "kor.traineddata").exists() or not (data_path / "eng.traineddata").exists():
            raise RuntimeError("한국어·영어 OCR 언어 데이터를 찾을 수 없습니다.")
        return executable, data_path

    @staticmethod
    def _decode_ocr_output(raw: bytes) -> str:
        for encoding in ("utf-8", "cp949", "euc-kr"):
            try:
                return raw.decode(encoding)
            except UnicodeDecodeError:
                continue
        return raw.decode("utf-8", errors="replace")

    def _ocr_page(self, page_number: int, executable: Path, data_path: Path) -> list[tuple[pymupdf.Rect, str]]:
        if not self.document:
            return []
        scale = 2.0
        page = self.document[page_number]
        pixmap = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
        image = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temporary:
            image_path = Path(temporary.name)
        try:
            image.save(image_path)
            result = subprocess.run(
                [
                    str(executable), "--tessdata-dir", str(data_path), str(image_path), "stdout",
                    "-l", "kor+eng", "--oem", "3", "--psm", "6", "-c", "tessedit_create_tsv=1",
                ],
                capture_output=True,
                check=False,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            if result.returncode != 0:
                raise RuntimeError(self._decode_ocr_output(result.stderr).strip() or "OCR 엔진이 결과를 만들지 못했습니다.")
            data = list(csv.DictReader(io.StringIO(self._decode_ocr_output(result.stdout)), delimiter="\t"))
        finally:
            image_path.unlink(missing_ok=True)

        words: list[tuple[pymupdf.Rect, str]] = []
        for item in data:
            text = item.get("text", "").strip()
            confidence = float(item.get("conf", "-1")) if item.get("conf", "-1") != "-1" else -1
            if not text or confidence < 20:
                continue
            rect = pymupdf.Rect(
                float(item.get("left", 0)) / scale,
                float(item.get("top", 0)) / scale,
                (float(item.get("left", 0)) + float(item.get("width", 0))) / scale,
                (float(item.get("top", 0)) + float(item.get("height", 0))) / scale,
            )
            words.append((rect, text))
        return words

    def ocr_document(self) -> None:
        if not self.document:
            messagebox.showinfo("CY뷰어", "먼저 PDF를 열어 주세요.")
            return
        try:
            executable, data_path = self._configure_ocr()
            self.ocr_words.clear()
            total_words = 0
            failed_pages: list[int] = []
            total_pages = len(self.document)
            for number in range(total_pages):
                self.status.config(text=f"OCR 진행 중 · {number + 1} / {total_pages} 페이지를 인식하고 있습니다…")
                self.update_idletasks()
                try:
                    words = self._ocr_page(number, executable, data_path)
                    self.ocr_words[number] = words
                    total_words += len(words)
                except Exception:
                    failed_pages.append(number + 1)
            self.draw_page()
            if failed_pages:
                pages = ", ".join(map(str, failed_pages))
                self.status.config(text=f"OCR 완료 · {total_pages - len(failed_pages)} / {total_pages} 페이지, {total_words}개 단어 인식")
                messagebox.showwarning("CY뷰어", f"문서 OCR을 마쳤습니다.\n\n인식 단어: {total_words}개\n실패한 페이지: {pages}")
            else:
                self.status.config(text=f"OCR 완료 · 전체 {total_pages}페이지에서 {total_words}개 단어를 인식했습니다.")
                messagebox.showinfo("CY뷰어", f"문서 전체 OCR이 완료됐습니다.\n\n페이지: {total_pages}개\n인식 단어: {total_words}개\n이제 모든 페이지에서 검색·선택·복사·표시·수정할 수 있습니다.")
        except Exception as error:
            self.status.config(text="OCR 실패")
            messagebox.showerror("CY뷰어", f"OCR을 실행할 수 없습니다.\n\n{error}")

    def copy_selected_text(self) -> None:
        text = self._selected_text()
        if not text:
            self._require_selection()
            return
        self.clipboard_clear()
        self.clipboard_append(text)
        self.update()
        self.status.config(fg="white", text=f"선택 텍스트를 클립보드에 복사했습니다. ({len(text)}자)")

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
        self._set_selection_feedback(text, "image" if image_count and not text else "text" if text else "none")

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

    def show_context_menu(self, event) -> None:
        if not self.document:
            return
        if not self.selected_rect or not self._selected_text():
            self.status.config(text="먼저 문구를 드래그해 선택한 뒤 마우스 오른쪽 버튼을 누르세요.")
            return
        self.context_menu.tk_popup(event.x_root, event.y_root)

    def mark_selection(self, kind: str) -> None:
        rect = self._require_selection()
        if not rect or not self.document:
            return
        page = self.document[self.page_number]
        regions = self.selection_regions or [rect]
        if kind == "highlight":
            for region in regions:
                annotation = page.add_rect_annot(region)
                annotation.set_colors(fill=(1, 0.92, 0))
                annotation.set_opacity(0.38)
                annotation.set_border(width=0)
                annotation.update()
        elif kind == "underline":
            for region in regions:
                annotation = page.add_underline_annot(region)
                annotation.update()
        else:
            for region in regions:
                annotation = page.add_strikeout_annot(region)
                annotation.update()
        self.selected_rect = None
        label = {"highlight": "형광펜", "underline": "밑줄", "strike": "취소선"}[kind]
        self._mark_dirty(f"{label} 표시를 적용했습니다.")
        self.draw_page()

    def _replace_selected_text(self, text: str, bold: bool) -> None:
        rect = self._require_selection()
        if not rect or not self.document:
            return
        rect = self._selection_bounds() or rect
        page = self.document[self.page_number]
        font_path = Path("C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf")
        # PDF 내부 글꼴 이름을 분리해야 굵은 글꼴이 일반 문구 수정에 재사용되지 않는다.
        font_name = "cyviewerbold" if bold else "cyviewerregular"
        font_kwargs = {"fontname": font_name, "fontfile": str(font_path)} if font_path.exists() else {"fontname": "hebo" if bold else "helv"}
        source_size = self._selected_font_size()
        target = pymupdf.Rect(
            rect.x0 - 1,
            rect.y0 - source_size * 0.18,
            page.rect.x1 - 8,
            min(page.rect.y1 - 8, rect.y1 + source_size * 2.2),
        ) & page.rect
        trial = pymupdf.open(stream=self.document.tobytes(), filetype="pdf")
        try:
            result = trial[self.page_number].insert_textbox(target, text, fontsize=source_size, color=(0, 0, 0), **font_kwargs)
        finally:
            trial.close()
        if result < 0:
            messagebox.showwarning("CY뷰어", "원래 글자 크기를 유지할 공간이 부족합니다. 글자를 축소하지 않았으며 원문도 바꾸지 않았습니다.")
            return
        page.add_redact_annot(rect, fill=(1, 1, 1))
        page.apply_redactions()
        page.insert_textbox(target, text, fontsize=source_size, color=(0, 0, 0), **font_kwargs)
        self.selected_rect = None
        self._mark_dirty("문구를 변경했습니다." if not bold else "선택 문구를 굵게 처리했습니다.")
        self.draw_page()

    def bold_selection(self) -> None:
        text = self._selected_text()
        if not text:
            self._require_selection()
            return
        if messagebox.askyesno("굵게 처리", "원문을 굵은 글꼴로 교체합니다. 계속할까요?", parent=self):
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

    def export_page(self, image_format: str) -> None:
        if not self.document:
            messagebox.showinfo("CY뷰어", "먼저 PDF를 열어 주세요.")
            return
        extension = ".jpg" if image_format == "jpg" else ".png"
        selected = filedialog.asksaveasfilename(
            title=f"현재 페이지를 {image_format.upper()}로 저장",
            defaultextension=extension,
            filetypes=[(f"{image_format.upper()} 이미지", f"*{extension}")],
        )
        if not selected:
            return
        try:
            pixmap = self.document[self.page_number].get_pixmap(matrix=pymupdf.Matrix(2, 2), alpha=False)
            image = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)
            if image_format == "jpg":
                image.save(selected, format="JPEG", quality=95)
            else:
                image.save(selected, format="PNG")
            self.status.config(text=f"현재 페이지를 {Path(selected).name}으로 저장했습니다.")
            messagebox.showinfo("CY뷰어", f"현재 페이지를 {image_format.upper()} 이미지로 저장했습니다.")
        except Exception as error:
            messagebox.showerror("CY뷰어", f"이미지로 저장할 수 없습니다.\n\n{error}")

    def print_document(self) -> None:
        if not self.document:
            messagebox.showinfo("CY뷰어", "먼저 PDF를 열어 주세요.")
            return

        preview = tk.Toplevel(self)
        preview.title("인쇄 미리보기 | CY뷰어")
        preview.geometry("980x760")
        preview.minsize(680, 520)
        preview.configure(bg=COLORS["canvas"])
        preview.transient(self)

        header = tk.Frame(preview, bg=COLORS["ink"], padx=20, pady=14)
        header.pack(fill="x")
        tk.Label(header, text="인쇄 미리보기", bg=COLORS["ink"], fg="white", font=("Malgun Gothic", 16, "bold")).pack(side="left")
        page_label = tk.Label(header, text="", bg=COLORS["ink"], fg="#CBD5E1", font=("Malgun Gothic", 10))
        page_label.pack(side="left", padx=18)

        controls = tk.Frame(preview, bg=COLORS["surface"], padx=16, pady=10)
        controls.pack(fill="x")
        preview_canvas = tk.Canvas(preview, bg="#DCE5EF", highlightthickness=0)
        preview_canvas.pack(fill="both", expand=True, padx=16, pady=(12, 16))
        state = {"page": self.page_number, "zoom": 1.0, "image": None}

        def draw_preview(_event=None) -> None:
            if not preview.winfo_exists() or not self.document:
                return
            page = self.document[state["page"]]
            available_width = max(preview_canvas.winfo_width() - 48, 100)
            available_height = max(preview_canvas.winfo_height() - 48, 100)
            fit = min(available_width / page.rect.width, available_height / page.rect.height)
            scale = max(0.2, min(3.0, fit * state["zoom"]))
            pixmap = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
            state["image"] = ImageTk.PhotoImage(Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples))
            preview_canvas.delete("all")
            x = max((preview_canvas.winfo_width() - pixmap.width) // 2, 24)
            y = max((preview_canvas.winfo_height() - pixmap.height) // 2, 24)
            preview_canvas.create_rectangle(x - 1, y - 1, x + pixmap.width + 1, y + pixmap.height + 1, fill="white", outline="#CBD5E1")
            preview_canvas.create_image(x, y, anchor="nw", image=state["image"])
            page_label.config(text=f"{state['page'] + 1} / {len(self.document)} 페이지 · {int(state['zoom'] * 100)}%")

        def move_page(change: int) -> None:
            state["page"] = max(0, min(len(self.document) - 1, state["page"] + change))
            draw_preview()

        def change_preview_zoom(change: float) -> None:
            state["zoom"] = max(0.5, min(2.0, round(state["zoom"] + change, 1)))
            draw_preview()

        self._button(controls, "◀ 이전", lambda: move_page(-1)).pack(side="left", padx=(0, 8))
        self._button(controls, "다음 ▶", lambda: move_page(1)).pack(side="left", padx=(0, 16))
        self._button(controls, "−", lambda: change_preview_zoom(-0.1)).pack(side="left", padx=(0, 6))
        self._button(controls, "+", lambda: change_preview_zoom(0.1)).pack(side="left")

        def open_printer_settings() -> None:
            if self._show_print_dialog():
                preview.destroy()

        print_button = self._button(controls, "프린터 설정 및 인쇄", open_printer_settings, "Primary.TButton")
        print_button.configure(width=170)
        print_button.pack(side="right")
        close_button = self._button(controls, "닫기", preview.destroy)
        close_button.configure(width=80)
        close_button.pack(side="right", padx=(0, 8))
        preview_canvas.bind("<Configure>", draw_preview)
        preview.bind("<Left>", lambda _: move_page(-1))
        preview.bind("<Right>", lambda _: move_page(1))
        preview.bind("<Escape>", lambda _: preview.destroy())
        preview.after_idle(draw_preview)
        preview.focus_set()

    def _show_print_dialog(self) -> bool:
        if not self.document:
            return False

        class PrintDialog(ctypes.Structure):
            _fields_ = [
                ("lStructSize", ctypes.c_uint32),
                ("hwndOwner", ctypes.c_void_p),
                ("hDevMode", ctypes.c_void_p),
                ("hDevNames", ctypes.c_void_p),
                ("hDC", ctypes.c_void_p),
                ("Flags", ctypes.c_uint32),
                ("nFromPage", ctypes.c_uint16),
                ("nToPage", ctypes.c_uint16),
                ("nMinPage", ctypes.c_uint16),
                ("nMaxPage", ctypes.c_uint16),
                ("nCopies", ctypes.c_uint16),
                ("hInstance", ctypes.c_void_p),
                ("lCustData", ctypes.c_ssize_t),
                ("lpfnPrintHook", ctypes.c_void_p),
                ("lpfnSetupHook", ctypes.c_void_p),
                ("lpPrintTemplateName", ctypes.c_wchar_p),
                ("lpSetupTemplateName", ctypes.c_wchar_p),
                ("hPrintTemplate", ctypes.c_void_p),
                ("hSetupTemplate", ctypes.c_void_p),
            ]

        pd_return_dc = 0x00000100
        pd_no_selection = 0x00000004
        pd_page_nums = 0x00000002
        pd_use_driver_copies = 0x00040000
        pd_hide_print_to_file = 0x00100000
        pd_disable_print_to_file = 0x00080000
        dialog = PrintDialog()
        dialog.lStructSize = ctypes.sizeof(PrintDialog)
        dialog.hwndOwner = self.winfo_id()
        dialog.Flags = pd_return_dc | pd_no_selection | pd_use_driver_copies | pd_hide_print_to_file | pd_disable_print_to_file
        dialog.nFromPage = 1
        dialog.nToPage = len(self.document)
        dialog.nMinPage = 1
        dialog.nMaxPage = len(self.document)
        dialog.nCopies = 1

        try:
            print_dialog = ctypes.windll.comdlg32.PrintDlgW
            print_dialog.argtypes = [ctypes.POINTER(PrintDialog)]
            print_dialog.restype = ctypes.c_int
            if not print_dialog(ctypes.byref(dialog)):
                error = ctypes.windll.comdlg32.CommDlgExtendedError()
                if error:
                    raise RuntimeError(f"Windows 인쇄 대화상자 오류: {error}")
                self.status.config(text="인쇄가 취소됐습니다.")
                return False

            first_page = dialog.nFromPage if dialog.Flags & pd_page_nums else 1
            last_page = dialog.nToPage if dialog.Flags & pd_page_nums else len(self.document)
            printer_dc = win32ui.CreateDCFromHandle(int(dialog.hDC))
            document_name = f"CY뷰어 - {self.document_path.name if self.document_path else 'PDF 문서'}"
            job_id = printer_dc.StartDoc(document_name)
            # pywin32의 CDC.StartDoc는 프린터 드라이버에 따라 성공 시에도
            # 작업 번호 대신 None을 반환한다. 음수/0이 명시적으로 반환된
            # 경우만 실패이며, None은 정상으로 보고 페이지 전송을 계속한다.
            if isinstance(job_id, int) and job_id <= 0:
                raise RuntimeError("Windows 인쇄 대기열에 작업을 만들지 못했습니다.")
            try:
                printable_width = printer_dc.GetDeviceCaps(8)
                printable_height = printer_dc.GetDeviceCaps(10)
                if printable_width <= 0 or printable_height <= 0:
                    raise RuntimeError("선택한 프린터의 인쇄 가능 영역을 확인할 수 없습니다.")
                for page_number in range(first_page - 1, last_page):
                    page = self.document[page_number]
                    pixmap = page.get_pixmap(matrix=pymupdf.Matrix(2, 2), alpha=False)
                    image = Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)
                    scale = min(printable_width / image.width, printable_height / image.height)
                    draw_width = int(image.width * scale)
                    draw_height = int(image.height * scale)
                    left = (printable_width - draw_width) // 2
                    top = (printable_height - draw_height) // 2
                    start_page_result = printer_dc.StartPage()
                    if isinstance(start_page_result, int) and start_page_result <= 0:
                        raise RuntimeError(f"{page_number + 1}페이지 인쇄 작업을 시작하지 못했습니다.")
                    ImageWin.Dib(image).draw(printer_dc.GetHandleOutput(), (left, top, left + draw_width, top + draw_height))
                    end_page_result = printer_dc.EndPage()
                    if isinstance(end_page_result, int) and end_page_result <= 0:
                        raise RuntimeError(f"{page_number + 1}페이지를 인쇄 대기열에 보내지 못했습니다.")
            except Exception:
                printer_dc.AbortDoc()
                raise
            else:
                printer_dc.EndDoc()
                job_text = f"작업 #{job_id} · " if isinstance(job_id, int) else ""
                self.status.config(text=f"인쇄 대기열 전송 완료 · {job_text}{first_page}~{last_page}페이지")
                messagebox.showinfo("CY뷰어", f"인쇄 작업을 Windows 대기열에 보냈습니다.\n\n{job_text}페이지: {first_page}~{last_page}")
                return True
            finally:
                printer_dc.DeleteDC()
        except Exception as error:
            messagebox.showerror("CY뷰어", f"인쇄를 시작할 수 없습니다.\n\n{error}")
            return False
        finally:
            if dialog.hDevMode:
                ctypes.windll.kernel32.GlobalFree(dialog.hDevMode)
            if dialog.hDevNames:
                ctypes.windll.kernel32.GlobalFree(dialog.hDevNames)

    def previous_page(self) -> None:
        if self.document and self.page_number > 0:
            self.page_number = max(0, self.page_number - (2 if self.view_mode == "spread" else 1))
            self._show_current_page()

    def next_page(self) -> None:
        if self.document and self.page_number < len(self.document) - 1:
            self.page_number = min(len(self.document) - 1, self.page_number + (2 if self.view_mode == "spread" else 1))
            self._show_current_page()

    def _show_current_page(self) -> None:
        self.draw_page()
        self.update_idletasks()
        if self.view_mode == "scroll" and self.page_number in self.page_layouts:
            top = self.page_layouts[self.page_number][1]
            scroll_region = self.canvas.bbox("all")
            if scroll_region and scroll_region[3] > self.canvas.winfo_height():
                self.canvas.yview_moveto(top / scroll_region[3])

    def change_zoom(self, change: float) -> None:
        if self.document:
            self.zoom = max(0.5, min(3.0, round(self.zoom + change, 1)))
            self.draw_page()

    def _wheel_zoom(self, event) -> None:
        if event.state & 0x0004:
            self.change_zoom(0.1 if event.delta > 0 else -0.1)
        elif self.view_mode == "scroll":
            self.canvas.yview_scroll(-3 if event.delta > 0 else 3, "units")
            center_y = self.canvas.canvasy(self.canvas.winfo_height() // 2)
            nearest = min(self.page_layouts, key=lambda page: abs(self.page_layouts[page][1] + self.page_layouts[page][3] / 2 - center_y), default=self.page_number)
            self.page_number = nearest
            return "break"
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
            query_lower = query.casefold()
            for number, words in self.ocr_words.items():
                self.search_matches.extend(
                    (number, rect) for rect, text in words if query_lower in text.casefold()
                )
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
