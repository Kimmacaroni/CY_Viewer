# 웹·Mac·Windows PDF 도구 통합

웹·Mac 1.14.0+21, Windows 1.11.1에서 PdfCraft 기반 PDF 도구를 제공한다. 이전 데스크톱 전용 연결을 브라우저까지 확장한 기록이며, 초기 범위와 배포 이력은 PDFCRAFT_WORKBENCH.md에 보존한다.

## 공통 기능과 사용 흐름

세 플랫폼에서 회전·삭제·빈 A4 페이지 삽입·순서 변경·선택 추출·여러 PDF 병합·일정 쪽 수 분할, 제목/작성자/주제/키워드·실제 PDF 내장 책갈피 편집, AES-256 암호 설정·변경·해제를 제공한다. 페이지 편집은 최근 30단계 되돌리기·다시 실행을 지원하고, PDF 결과를 바로 열 수 있다.

웹·Mac은 같은 네 탭의 PDF 도구 화면을 사용한다. Windows는 작업 선택과 페이지 목록을 사용한다. Windows에서는 페이지 변경 적용으로 작업을 쌓거나 드래그하고, 되돌리기·다시 실행 후 저장할 수 있다. 페이지 번호는 해당 화면의 목록을 기준으로 입력하며 문서 책갈피 대상은 편집 전 원본 번호다.

웹은 **파일 준비 → 다운로드**의 두 단계다. 실제 HTML 파일 입력으로 PDF를 추가하고, 준비된 PDF·ZIP은 실제 다운로드 링크를 직접 눌러 저장한다. 준비만 완료한 상태를 다운로드 완료로 표시하지 않는다. Safari·iPhone에서 합성 클릭이나 처리 후 자동 팝업을 요구하지 않는다. PDF 결과 열기는 뷰어 내부에서 새 결과를 연다. 암호 결과를 열 때는 리더의 마스킹된 입력창을 사용한다.

네이티브는 원본 경로·링크의 덮어쓰기를 거부하고 웹은 입력 바이트를 유지한 채 별도 이름의 다운로드 사본을 만든다. 브라우저 저장 경로는 앱이 조회하거나 통제하지 않는다. 소유자 권한 확인, 전자서명 문서 편집 거부와 명시적인 암호 설정/해제 정책을 유지한다. 분할 ZIP 안의 각 PDF에 암호를 적용하며 ZIP 자체를 암호화하는 기능은 아니다. 암호는 현재 작업의 메모리에서만 사용한다. Mac의 임시 화면 표시는 PDF 도구 결과에 포함하지 않는다.

## 같은 엔진, 다른 입출력

`pdfcraft_bridge/src/lib.rs`의 편집 코드는 네이티브와 브라우저가 공유한다. 고정 PdfCraft 커밋은 `d9607ec3befcda3e78062ceb5e54b97563aedad1`이다. 네이티브는 DiskStorage, 브라우저는 MemoryStorage로 입출력만 나눈다. 엔진 버전은 0.3.0이다.

브라우저는 고정 wasm-bindgen 0.2.126으로 만든 WASM을 별도 Web Worker에서 실행한다. 작업마다 원본 바이트를 복사해 전달하고 종료 시 작업자를 해제한다. 시간 제한 180초, 최대 20개 PDF·파일당 256MB·전체 512MB·최대 100000쪽·분할 최대 500개 제한을 유지한다. 이 수치는 브라우저나 전체 프로세스 메모리의 보장 상한이 아니다. 분할 ZIP 구성은 Dart에서 수행한다. 저장 전 PDFium으로 결과 쪽 수를 다시 확인한다.

브라우저 암호 난수는 getrandom의 Web Crypto 백엔드를 사용한다. 문서를 서버로 보내는 API나 외부 PDF 처리 서비스는 사용하지 않는다. 기존 Drive 기능은 사용자가 연결한 경우의 기존 정책을 따른다.

## 재현 빌드·라이선스

- 네이티브: Rust 1.95에서 `python3 scripts/build_pdfcraft.py`.
- 웹: Linux x86_64에서 `python3 scripts/build_pdfcraft_web.py`. 고정 WASM 변환 도구를 SHA-256 검증하고 wasm32 타깃과 의존성 고지를 생성한다.
- 웹 결과는 `macos_app/web/pdfcraft/`에 생성하며 Flutter 웹 빌드에 포함한다. 생성 바이너리를 Git에 수동으로 보관하지 않는다.
- wasm-bindgen 가이드의 Web Worker 로딩 방식을 참고하고, Safari 호환을 위해 classic worker/importScripts 출력을 사용한다: https://wasm-bindgen.github.io/wasm-bindgen/examples/wasm-in-web-worker.html
- README의 ArtCraft Team·PdfCraft contributors·MIT 고지를 유지한다. 웹에서도 `pdfcraft/THIRD_PARTY_NOTICES.txt`를 공개하며 실제 WASM 의존성 고지를 포함한다. ArtCraft 브랜드·UI·자산은 가져오지 않는다.

## 검증

`tests/pdfcraft_browser.cjs`는 실제 Chrome·WebKit 작업자에서 회전·삭제·빈 페이지·추출·병합·분할·정보·책갈피·암호 변경/해제를 실행하고 PyMuPDF로 결과를 재검사한다. 링크·폼 보존, 서명/소유자 제한, 잘못된 요청, 입력 바이트 보존과 문서 업로드 없음(GET 요청만 발생)도 확인한다.

`tests/pdfcraft_ui.cjs`는 빌드된 웹앱에서 파일 열기 → PDF 도구 → 회전·정보·책갈피 → PDF 추가 → 분할 ZIP → 암호 결과 다운로드 → 잘못된 암호 재입력 → 결과 열기를 직접 실행하고 결과를 독립 엔진으로 검사한다. 좁은 390px 화면의 도구 접근도 검사한다. WebKit 검사를 실제 iPhone 기기 검사로 간주하지 않는다.

기존 네이티브 회귀 8개·Windows 단위/GUI/설치·Mac 샌드박스/PDFKit·Flutter 전체 검사도 유지한다. Windows GUI smoke에 페이지 기록 되돌리기·다시 실행·결과 바로 열기를 추가했다. 공개 파일·체크섬과 실제 배포 결과는 아래에 기록한다.

## 공개 배포 검증 (2026-10-15)

[PR #33](https://github.com/Kimmacaroni/CY_Viewer/pull/33)을 `97c2e01b055f2707061202784069e289107dee5f`에 병합했다. 웹·Mac 1.14.0+21, Windows 1.11.1을 공개했다. Mac 출시 Actions `38680077226`, Windows 출시 `38680658316`, 웹 배포 `38680062420`이 성공했다.

- Mac: `CYViewer-macOS-v1.14.0.dmg`, 36,163,879바이트, SHA-256 `7166cb235206e350bcf5be0daf3b5d9b78bb85ac5c3dbd36658a13c04982683f`. 공식 공개 주소에서 직접 내려받아 릴리스 메타데이터·체크섬과 대조했다.
- Windows: `CYViewer-Setup-v1.11.1.exe`, 37,468,082바이트, SHA-256 `fe4ad5db04f24570c15a7aa92bbb4a137169e78920d9287c1f294387142c8521`. 공식 공개 주소에서 직접 내려받아 릴리스 메타데이터·체크섬과 대조했다.

공개 웹에서 `1.14.0+21`과 `pdfcraft-all-1.14.0-21`, 실제 WASM 바이너리 및 wasm-bindgen·getrandom·PdfCraft 저작권 고지를 확인했다. 공개 사이트의 Chrome·WebKit에서 회전·정보·책갈피·추가 PDF·분할 ZIP·암호 PDF 다운로드를 실행하고 독립 엔진으로 확인했다. 잘못된 암호 재입력·결과 다시 열기와 390px 창도 통과했다.

Windows 1.11.1은 [PR #34](https://github.com/Kimmacaroni/CY_Viewer/pull/34), `3d117ea61cc37144b990826c11d89a9938472890`의 저장·오류 안내 고정을 포함한다. Windows 출시 빌드에서 실제 GUI 저장·되돌리기·다시 실행·결과 열기·암호와 설치/재설치·설치된 모듈 실행을 확인했다. 회전·빈 페이지·삭제를 적용한 뒤 다른 작업으로 이동했다가 돌아와 저장해도 기본 폼을 중복 실행하지 않는 검사도 포함한다. Mac 출시 빌드에서 universal 앱·서명·샌드박스 모듈의 PDFKit 재열기를 확인했다. 공개 DMG 내부의 1.14.0+21, PDF 도구·0.3.0 모듈·제작자 고지도 확인했다.

사용자의 실제 Mac/Windows 설치 상태나 iPhone 기기에서 직접 누른 결과로 간주하지 않는다. 기존 설치 앱은 새 설치본으로 교체하고 웹은 새로고침 후 PDF 도구를 연다.

[웹앱](https://kimmacaroni.github.io/CY_Viewer/) · [Mac 1.14.0](https://github.com/Kimmacaroni/CY_Viewer/releases/tag/macos-v1.14.0) · [Windows 1.11.1](https://github.com/Kimmacaroni/CY_Viewer/releases/tag/windows-v1.11.1)
