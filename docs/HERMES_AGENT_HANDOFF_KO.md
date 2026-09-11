# CY뷰어 Hermes Agent 인수인계

- 최종 갱신: 2026-09-11
- 기준 저장소: `Kimmacaroni/CY_Viewer`
- 기준 브랜치/커밋: `origin/main` / `9b1e74a34566c4b9abf01546ec64c8220635822f`
- 문서 목적: 새 작업자가 구현체 관계와 검증·배포 경계를 이해하고 안전하게 작업을 재개하도록 하는 운영 기준

> 버전과 상태는 위 기준 커밋의 추적 파일을 근거로 한다. 원격 릴리스의 현재 상태를 단정하려면 작업 시작 시 GitHub에서 다시 확인한다.

## 1. 저장소 구조

| 경로 | 기술/대상 | 현재 역할 |
| --- | --- | --- |
| `native_windows/` | Python, Tkinter, PyMuPDF, Pillow, pywin32, tkinterdnd2, Tesseract | Windows 배포판의 PyInstaller 진입점인 `cy_viewer.py`와 한국어·영어 OCR 데이터 |
| `macos_app/` | Flutter/Dart, macOS Swift, PDFKit/Vision 연동 | macOS 전용 앱. 현재 버전 `1.1.1+3`; 독립된 앱 코드·테스트·macOS Runner 보유 |
| `windows_print/` | .NET 8, WinUI 3, Windows App SDK, MSIX | `cyviewer-print` 프로토콜로 PDF를 받아 시스템 인쇄 미리보기/대기열을 여는 Windows 보조 모듈. 매니페스트 버전 `1.0.0.2` |
| `personal_pdf_viewer/` | Flutter/Dart, Windows/macOS/iOS/Android Runner | 초기 크로스플랫폼 구현. 현재 버전 `1.0.0+1`; 최근 문서·즐겨찾기·읽던 페이지·표시 기능 중심 |
| `installer/` | Inno Setup | `native_windows` PyInstaller 폴더형 산출물을 설치하는 Windows 설치 프로그램 정의. 버전 `1.0.0` |
| `.github/workflows/build-macos.yml` | GitHub Actions | `macos_app` 분석·테스트·release 빌드 및 `CYViewer-macOS-v1.1.1.dmg` 아티팩트 생성 |
| `docs/` | 운영/사용 문서 | 사용자 설명, 기존 대화 기록, 본 인수인계와 작업 로그 |

## 2. 현재 main 상태와 주요 기능

기준 `main`은 `9b1e74a`이며 마지막 변경은 macOS v1.1.1 패키지 워크플로 갱신이다. 저장소에는 Git 태그가 없다. 코드에 선언된 버전은 구현체별로 다르므로 단일한 저장소 버전으로 간주하면 안 된다.

### Windows 네이티브 구현

- PDF 열기와 끌어놓기, 단일/연속 스크롤/좌우 보기, 페이지 이동, 확대·축소
- 문서 검색, 책갈피, 한국어·영어 전체 OCR
- 텍스트·이미지·빈 영역을 구분하는 선택과 복사
- 형광펜·밑줄·취소선·굵게, 선택 문구 수정
- PDF 저장, 페이지 JPG/PNG 내보내기
- Windows 인쇄 흐름과 별도 WinUI 인쇄 모듈 연동
- PyInstaller 실행 파일 및 Inno Setup 설치 프로그램 구조

### macOS 전용 구현

- PDF 열기/끌어놓기, 탐색, 검색, 선택과 표시, 책갈피
- 세로·가로 스크롤과 두 페이지 보기, 확대·축소
- 최근 문서·즐겨찾기·마지막 페이지 및 샌드박스 파일 접근 복원
- Apple Vision 기반 한국어·영어 OCR
- PDF 복사본 및 페이지별 PNG/JPG 내보내기
- macOS 시스템 인쇄 창
- 기준 문서상 macOS 12 이상, Apple Silicon/Intel 대상

### 크로스플랫폼 Flutter 구현

- Windows/macOS/iOS/Android Runner가 있으며 PDF 열람, 검색, 최근 문서, 즐겨찾기, 마지막 페이지, 책갈피, 다크 모드, 텍스트 선택·표시를 구현한다.
- `macos_app`과 이름·일부 Dart 구조가 겹치지만 버전과 의존성, 플랫폼 네이티브 기능은 동일하지 않다.

## 3. 빌드·테스트 경로

모든 명령은 해당 플랫폼의 전용 worktree에서 실행하고 결과를 `docs/WORK_LOG.md`에 기록한다. 고객 문서 대신 비민감 합성 PDF를 사용한다.

### `native_windows`와 Windows 설치 프로그램

필수 환경은 Windows 10/11 x64, Python, 앱 의존 패키지, Tesseract 실행 파일, PyInstaller이며 인쇄 검증에는 Windows 프린터/PDF 프린터가 필요하다.

```powershell
# 저장소 루트
python -m py_compile native_windows/cy_viewer.py
pyinstaller --clean CYViewer.spec
# 단일 파일 변형이 필요할 때만
pyinstaller --clean CYViewer-OneFile.spec
```

- 폴더형 배포본 예상 위치: `dist/CYViewer/` (설치 스크립트는 현재 `dist_titleicon4/CYViewer/`를 참조하므로 패키징 전에 경로를 반드시 맞추거나 스크립트를 수정한다).
- Inno Setup에서 `installer/CYViewer.iss`를 컴파일하면 `release/CYViewer-Setup-v1.0.0.exe`를 만들도록 정의되어 있다.
- 자동화된 Python 테스트 모음은 기준 커밋에 없다. 실제 앱 구동과 Windows 기능 수동 QA가 필수다.

### `windows_print`

Windows에서 .NET 8 SDK, Visual Studio의 Windows 앱 SDK/WinUI 및 MSIX 빌드 환경을 준비한다.

```powershell
cd windows_print
dotnet restore
dotnet build CYViewer.Print.csproj -c Release -p:Platform=x64
```

MSIX를 만들고 테스트 인증서로 설치할 때만 관리자 권한과 `install_print_module.ps1`을 사용한다. 인증서나 개인키는 저장소에 넣지 않는다. 설치 후 `cyviewer-print` 프로토콜, 미리보기, 실제 Windows 인쇄 대기열 제출을 확인한다.

### `macos_app`

macOS 12 이상과 Xcode, stable Flutter가 필요하다. CI와 같은 순서로 실행한다.

```bash
cd macos_app
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

- 앱 예상 위치: `macos_app/build/macos/Build/Products/Release/CYViewer.app`
- DMG 생성 절차와 이름은 `.github/workflows/build-macos.yml`을 따른다.
- 자동 검증 뒤 실제 Mac에서 파일 선택/끌어놓기, 보안 범위 북마크, 트랙패드, OCR, 내보내기, 인쇄, Intel/Apple Silicon 호환성을 확인한다.

### `personal_pdf_viewer`

각 지원 플랫폼의 Flutter 도구 체인에서 실행한다.

```bash
cd personal_pdf_viewer
flutter pub get
flutter analyze
flutter test
flutter build windows --release   # Windows
flutter build macos --release     # macOS
flutter build apk --release       # Android 예시
flutter build ios --release       # iOS 서명 설정 필요
```

변경 플랫폼마다 실제 기기 또는 적절한 테스트 환경에서 파일 권한, 재실행 상태 복원, PDF 상호작용을 확인한다.

## 4. 배포·릴리스 구조

- 메인 개발 저장소 `Kimmacaroni/CY_Viewer`: 소스, 문서, 테스트 및 빌드 워크플로 관리.
- 공개 다운로드 저장소 `Kimmacaroni/CY_Viewer_Download`: 기존 프로젝트 기록과 `macos_app/README.md`에 따르면 완성 설치 파일, 사용자 설명, 체크섬 공개 대상.
- macOS 워크플로는 분석·테스트·DMG 빌드 후 GitHub Actions 아티팩트만 업로드하며, 릴리스를 자동 생성하지 않는다.
- Windows Inno Setup은 로컬 `release/` 산출물을 만들며 자동 게시 단계는 없다.
- 루트 `README.md`와 `docs/USER_GUIDE.md`의 Windows 다운로드 링크는 현재 메인 저장소 Releases를 가리키지만, 기존 배포 원칙은 공개 다운로드 저장소를 가리킨다. 다음 릴리스 전에 단일 정책을 결정하고 링크를 일치시켜야 한다.
- 사용자가 대상 사용자/환경, 저장소, 버전, 산출물을 명시적으로 승인하기 전에는 push, 릴리스 생성, 공개 업로드, 서명·공증 또는 스토어 제출을 하지 않는다.
- 배포 전 앱 버전·파일명·문서·워크플로의 버전을 일치시키고, 체크섬, 설치/실행/제거, 지원 OS/아키텍처, 서명·공증 상태를 기록한다.

## 5. 알려진 위험과 필요한 결정

### 여러 구현체가 동시에 존재하는 위험

1. `native_windows`, `macos_app`, `personal_pdf_viewer`에 사용자 기능과 UI가 중복되어 수정이 한 구현체에만 반영될 수 있다.
2. `macos_app`과 `personal_pdf_viewer`는 패키지 이름과 Dart 파일 구조가 유사해 잘못된 디렉터리에서 명령을 실행하거나 변경을 복사할 위험이 있다.
3. 버전이 `1.0.0`, `1.0.0+1`, `1.1.1+3`, MSIX `1.0.0.2`로 분산되어 릴리스 이름과 실제 바이너리가 어긋날 수 있다.
4. Windows 설치 스크립트의 입력 경로(`dist_titleicon4`)와 기본 PyInstaller 출력 경로(`dist`)가 다르다.
5. Windows 다운로드 저장소 정책이 문서 사이에서 충돌한다.
6. Windows 인쇄에는 Python 내부의 레거시 흐름과 별도 WinUI 모듈이 함께 있어 지원 경로가 불명확하다.
7. 자동 테스트가 Flutter 기본/위젯 테스트 중심이며 실제 PDF 편집, OCR, 인쇄, 샌드박스 권한을 충분히 검증하지 못한다.

### 기준 구현체 결정 필요

제품 책임자가 플랫폼별 기준 구현체를 명시해야 한다. 결정 전에는 다음을 임시 원칙으로 사용한다.

- Windows 설치 배포의 현재 연결 구조는 `native_windows` + 필요 시 `windows_print` + `installer`로 본다.
- macOS 배포의 현재 연결 구조는 `macos_app`과 `.github/workflows/build-macos.yml`로 본다.
- `personal_pdf_viewer`를 향후 공통 기준으로 승격할지, 레거시/실험 구현으로 유지할지는 결정되지 않았다.
- 기능 요청을 받으면 먼저 대상 플랫폼과 구현체를 작업 로그에 명시하고, 다른 구현체 동기화 여부를 제품 책임자에게 결정받는다.
- 최종 결정 후 README, 버전 출처, 테스트 매트릭스, 배포 파이프라인과 중복 코드 폐기 계획을 함께 갱신한다.

## 6. append-only 기록과 상태 판정

- `docs/WORK_LOG.md`는 엄격한 append-only 감사 기록이다. 한 번 작성한 블록은 수정·삭제·재정렬하지 않는다.
- 기존 기록의 오류를 정정하거나 작업 완료, 독립 QA, 배포 결과를 추가할 때는 원본 블록을 그대로 두고, 해당 블록의 시각·제목·커밋을 참조하는 새 블록을 파일 끝에 추가한다.
- 상태는 반드시 `구현 상태`, `독립 QA 상태`, `배포 상태`로 나눠 기록한다. 구현 완료는 독립 QA 통과 또는 배포 완료를 의미하지 않는다.
- 독립 QA 통과는 구현 담당자와 다른 검토 주체, 검증 환경·명령, 결과 근거가 있을 때만 선언한다. 근거가 없으면 `QA 대기`, 실패하면 `QA 거부`로 기록하고 보완 후 새 QA 블록을 추가한다.
- 배포는 사용자가 대상 사용자/환경, 저장소, 버전, 산출물을 명시적으로 지시한 경우에만 수행한다. 그 전에는 구현·QA 상태와 무관하게 `배포 미수행`이다.
- 로그에는 실제 절대 worktree 경로 대신 중립 표기 `$WORKTREE`를 사용한다. 비밀정보와 사용자·호스트별 경로를 기록하지 않는다.

## 7. 안전한 재개 절차

1. 사용자 요청에서 대상 플랫폼, 구현체, 완료 조건, 배포 여부와 배포 대상 사용자를 확인한다. 불명확하면 배포는 범위에서 제외한다.
2. 원격 변경을 조회하고 최신 `origin/main` SHA를 확인한다. 기존 worktree의 미커밋 변경을 건드리지 않는다.
3. 최신 `main`에서 작업 전용 브랜치와 별도 worktree를 만든다. 브랜치명에 작업 목적을 담는다.
4. 새 worktree에서 `git status --short --branch`, 기준 SHA, 대상 파일을 확인한다.
5. `AGENTS.md`, 본 문서, `docs/WORK_LOG.md`와 대상 구현체 README/설정을 읽는다.
6. `docs/WORK_LOG.md` 파일 끝에 시작 시각, 담당 주체, 브랜치/`$WORKTREE`, 기준 SHA, 범위, 검증 계획을 새 블록으로 추가한다.
7. 고객 PDF·비밀정보 대신 합성 fixture로 최소 재현을 만들고 대상 구현체만 수정한다. 다른 구현체에 미치는 영향을 별도로 검토한다.
8. 대상 플랫폼에서 정적 분석, 자동 테스트, 실제 release 빌드와 변경 기능 수동 QA를 수행한다. 실행하지 못한 항목은 성공으로 표시하지 않는다.
9. 구조·버전·절차·위험이 바뀌면 본 문서를 갱신하고, 작업 로그 파일 끝에 구현 결과와 미검증 사항을 새 블록으로 추가한다. 기존 블록은 갱신하지 않는다.
10. `git status`, `git diff`, `git diff --check`로 변경 범위와 민감정보/산출물 포함 여부를 확인한 뒤 커밋한다.
11. 구현, 독립 QA, 배포 상태를 분리해 최종 커밋 SHA와 검증 근거를 인계한다. push·PR·릴리스·배포는 사용자의 별도 명시 지시가 있을 때만 수행한다.
