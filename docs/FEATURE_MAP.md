# CY뷰어 기능·구현체 지도

이 문서는 여러 구현체를 합치지 않고 **어느 경로를 수정하고 무엇을 함께 검증할지** 빠르게 판단하기 위한 작업 지도다. 제품 책임자가 기준 구현체를 확정하기 전까지는 아래 연결을 임시 기준으로 사용하며, 한 구현체의 변경을 다른 구현체에 자동 복사하지 않는다.

## 구현체 경계와 현재 연결

| 구현체 | 실행 진입점 | 현재 연결/소유 범위 | 버전의 코드상 출처 | 최소 자동 검증 |
| --- | --- | --- | --- | --- |
| `native_windows` | `native_windows/cy_viewer.py` | Windows 설치판의 Python UI·PDF·OCR·내보내기·내부 인쇄 흐름 | 설치판은 `installer/CYViewer.iss`의 `AppVersion` | `python -m py_compile native_windows/cy_viewer.py` |
| `windows_print` | `windows_print/App.xaml`, `MainWindow.xaml.cs` | `cyviewer-print` 프로토콜과 WinUI 시스템 인쇄 보조 모듈. Python 인쇄 흐름 중 무엇이 기준인지는 미결정 | `windows_print/Package.appxmanifest`의 `Identity Version` | XAML/XML 파싱 후 Windows에서 `dotnet build` |
| `macos_app` | `macos_app/lib/main.dart` → `app.dart` → `advanced_reader.dart` | macOS 배포 후보와 네이티브 파일 권한·Vision OCR·인쇄 | `macos_app/pubspec.yaml` | `flutter analyze`, `flutter test`, macOS release 빌드 |
| `personal_pdf_viewer` | `personal_pdf_viewer/lib/main.dart` → `app.dart` → `advanced_reader.dart` | Windows/macOS/iOS/Android 공통 구현. 향후 기준 승격 여부 미결정 | `personal_pdf_viewer/pubspec.yaml` | `flutter analyze`, `flutter test`, 변경 플랫폼 빌드 |
| `installer` | `installer/CYViewer.iss` | `native_windows` 폴더형 산출물 설치 | 같은 파일의 `AppVersion` | Windows Inno Setup 컴파일·설치·제거 |

`README.md`와 사용자 가이드는 특정 버전을 중복 선언하지 않는다. 배포 전에는 위 코드상 출처, 산출물 이름, 공개 릴리스 버전을 별도 릴리스 작업에서 함께 맞춘다.

## 기능별 변경 위치

| 기능 | `native_windows` | `macos_app` | `windows_print` | `personal_pdf_viewer` | 변경 시 주의 |
| --- | --- | --- | --- | --- | --- |
| 앱 시작·문서함·최근 문서 | `CyViewer.__init__`, `_make_ui`, `load_pdf` | `lib/app.dart` | 해당 없음 | `lib/app.dart` | 두 Flutter 앱의 파일명이 같아도 코드·플랫폼 채널·버전이 다르다. |
| PDF 열기·끌어놓기 | `open_pdf`, `drop_pdf`, `load_pdf` | `lib/app.dart` 및 macOS Runner | 해당 없음 | `lib/app.dart`, 플랫폼 Runner | 권한·보안 범위 복원은 실제 대상 OS에서 확인한다. |
| 렌더링·보기 방식·탐색 | `draw_page`~`go_to_page` | `lib/advanced_reader.dart` | 인쇄 미리보기만 | `lib/advanced_reader.dart` | Flutter 실행 경로는 `AdvancedPdfReaderPage` 하나다. |
| 검색·선택·표시·편집 | `start_selection`~`edit_selection`, `find_next` | `lib/advanced_reader.dart` | 해당 없음 | `lib/advanced_reader.dart` | 네이티브 Windows만 선택 문구 수정 기능을 포함한다. |
| OCR | `_configure_ocr`~`ocr_document`, `tessdata/` | `lib/advanced_reader.dart` + `macos/Runner/MainFlutterWindow.swift` | 해당 없음 | 전용 OCR 연결 없음 | 언어 데이터·Vision 권한·실제 합성 fixture를 따로 검증한다. |
| 저장·이미지 내보내기 | `save_as`, `export_page` | `lib/advanced_reader.dart` | 해당 없음 | `lib/advanced_reader.dart`의 현재 제공 범위 확인 | 원본 보존, 표시 반영 여부와 권한을 확인한다. |
| 인쇄 | `print_document`, `_legacy_print_preview`, `_show_print_dialog` | `lib/advanced_reader.dart` 및 macOS Runner | `MainWindow.xaml(.cs)` | 플랫폼별 제공 범위 확인 | Windows 기준 경로가 미결정이므로 어느 쪽도 삭제·병합하지 않는다. |
| 패키징·배포 | `CYViewer.spec`, `CYViewer-OneFile.spec` | `.github/workflows/build-macos.yml` | `.csproj`, MSIX 매니페스트 | 플랫폼 Runner/도구 체인 | push·릴리스·서명·배포에는 별도 명시 승인이 필요하다. |

## `native_windows/cy_viewer.py` 구조 감사

기준선은 1,210줄이며 `RoundedButton`과 `CyViewer`에 UI 구성, 렌더링, 선택/편집, OCR, 저장, 인쇄, 탐색이 모여 있다. 다음 후보 경계는 확인했지만 이번 정리에서는 실행 경로를 바꾸는 분할을 하지 않는다.

1. 렌더링·좌표 변환: `draw_page`부터 `_image_rects`
2. 선택·표시·편집: `start_selection`부터 `edit_selection`
3. OCR: `_ocr_data_path`부터 `ocr_document`
4. 저장·내보내기: `save_as`, `export_page`
5. 인쇄: `print_document`부터 `_show_print_dialog`
6. 페이지·검색: `previous_page`부터 `find_next`

분할 전에는 합성 PDF fixture와 Windows 자동/수동 회귀 검증을 먼저 추가해야 한다. 특히 Tk 이벤트 바인딩, 캔버스 좌표, 문서/페이지 상태를 단순 유틸리티처럼 이동하면 기능 손상 위험이 크다.

## 안전한 기능별 작업 순서

1. 작업 로그에 대상 플랫폼과 **정확한 구현체 경로**를 기록한다.
2. `python scripts/verify_structure.py`로 네 구현체와 진입점 기준선을 확인한다.
3. 대상 기능의 위 표 행만 수정하고, 비슷한 이름의 다른 구현체 동기화 여부는 별도 결정으로 남긴다.
4. 정적 검사만으로 끝내지 말고 대상 구현체의 분석·테스트·release 빌드와 실제 OS QA를 수행한다.
5. `python -m unittest discover -s tests -p 'test_*.py'`, `git diff --check`를 실행한다.
6. 구조·버전·연결이 바뀌면 이 문서와 `docs/HERMES_AGENT_HANDOFF_KO.md`를 같은 커밋에서 갱신한다.

## 구조 검증 도구의 범위

`scripts/verify_structure.py`는 네 구현체 보존, Python AST, Windows XAML/XML, Flutter 진입점과 고급 리더 연결, 제거된 미사용 단순 리더의 재유입, README의 버전/개인 경로 중복을 검사한다. 이는 실제 앱 빌드나 플랫폼 QA를 대체하지 않는다.
