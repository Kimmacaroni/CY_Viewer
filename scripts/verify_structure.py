#!/usr/bin/env python3
"""실행 없이 CY뷰어 구현체 경계와 정적 구조를 검증한다."""

from __future__ import annotations

import argparse
import ast
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

IMPLEMENTATIONS = {
    "native_windows": ("native_windows/cy_viewer.py",),
    "macos_app": ("macos_app/lib/main.dart", "macos_app/lib/advanced_reader.dart"),
    "windows_print": ("windows_print/App.xaml", "windows_print/MainWindow.xaml.cs"),
    "personal_pdf_viewer": (
        "personal_pdf_viewer/lib/main.dart",
        "personal_pdf_viewer/lib/advanced_reader.dart",
    ),
}


def _read(root: Path, relative: str, errors: list[str]) -> str:
    path = root / relative
    if not path.is_file():
        errors.append(f"필수 파일 없음: {relative}")
        return ""
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        errors.append(f"파일 읽기 실패: {relative}: {exc}")
        return ""


def _check_implementations(root: Path, errors: list[str]) -> None:
    for name, required_files in IMPLEMENTATIONS.items():
        if not (root / name).is_dir():
            errors.append(f"구현체 디렉터리 없음: {name}")
        for relative in required_files:
            _read(root, relative, errors)


def _check_native_windows(root: Path, errors: list[str]) -> None:
    relative = "native_windows/cy_viewer.py"
    source = _read(root, relative, errors)
    if not source:
        return
    try:
        tree = ast.parse(source, filename=relative)
    except SyntaxError as exc:
        errors.append(f"Python 문법 오류: {relative}:{exc.lineno}: {exc.msg}")
        return
    classes = [node.name for node in tree.body if isinstance(node, ast.ClassDef)]
    if classes.count("CyViewer") != 1:
        errors.append("native_windows에 CyViewer 클래스가 정확히 하나여야 함")
    if "if __name__ == \"__main__\":" not in source:
        errors.append("native_windows 실행 가드가 없음")


def _xml_candidates(root: Path) -> list[Path]:
    candidates = list((root / "windows_print").glob("*.xaml"))
    candidates += list((root / "windows_print").glob("*.manifest"))
    candidates.append(root / "windows_print/Package.appxmanifest")
    candidates.append(root / "personal_pdf_viewer/windows/runner/runner.exe.manifest")
    return sorted(set(candidates))


def _check_xml(root: Path, errors: list[str]) -> None:
    for path in _xml_candidates(root):
        relative = path.relative_to(root).as_posix()
        if not path.is_file():
            errors.append(f"필수 XML/XAML 없음: {relative}")
            continue
        try:
            ET.parse(path)
        except (ET.ParseError, OSError) as exc:
            errors.append(f"XML/XAML 오류: {relative}: {exc}")


def _check_flutter_app(root: Path, app_root: str, errors: list[str]) -> None:
    main_relative = f"{app_root}/lib/main.dart"
    app_relative = f"{app_root}/lib/app.dart"
    main = _read(root, main_relative, errors)
    app = _read(root, app_relative, errors)
    if "import 'app.dart';" not in main or "runApp(const PersonalPdfApp())" not in main:
        errors.append(f"Flutter 진입점 연결 오류: {main_relative}")
    if "AdvancedPdfReaderPage(" not in app:
        errors.append(f"고급 PDF 리더 연결 없음: {app_relative}")
    if re.search(r"class\s+_?PdfReaderPage", app):
        errors.append(f"참조 0건 단순 샘플 리더가 재유입됨: {app_relative}")


def _check_docs(root: Path, errors: list[str]) -> None:
    for relative in ("README.md", "docs/USER_GUIDE.md"):
        text = _read(root, relative, errors)
        if re.search(r"CYViewer-Setup-v\d+\.\d+\.\d+\.exe", text):
            errors.append(f"README에 설치 버전이 중복 고정됨: {relative}")
    personal_readme = _read(root, "personal_pdf_viewer/README.md", errors)
    if re.search(r"[A-Za-z]:\\Users\\[^\\`\s]+", personal_readme):
        errors.append("personal_pdf_viewer README에 개인 Windows 사용자 경로가 있음")
    feature_map = _read(root, "docs/FEATURE_MAP.md", errors)
    for name in IMPLEMENTATIONS:
        if f"`{name}`" not in feature_map:
            errors.append(f"기능 지도에서 구현체 누락: {name}")


def validate(root: Path) -> list[str]:
    """저장소 구조를 검사하고 오류 문자열 목록을 반환한다."""
    root = root.resolve()
    errors: list[str] = []
    _check_implementations(root, errors)
    _check_native_windows(root, errors)
    _check_xml(root, errors)
    for app_root in ("macos_app", "personal_pdf_viewer"):
        _check_flutter_app(root, app_root, errors)
    _check_docs(root, errors)
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--json", action="store_true", help="기계 판독용 JSON 출력")
    args = parser.parse_args(argv)
    errors = validate(args.root)
    result = {
        "ok": not errors,
        "implementation_count": len(IMPLEMENTATIONS),
        "errors": errors,
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif errors:
        print("구조 검증 실패:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
    else:
        print(f"구조 검증 통과: 구현체 {len(IMPLEMENTATIONS)}개, Python AST, Windows XML/XAML, Flutter 진입점")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
