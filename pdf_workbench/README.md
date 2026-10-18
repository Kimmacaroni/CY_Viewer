# CY뷰어 전체 PDF 작업실

ArtCraft Team 및 PdfCraft 기여자의 PdfCraft 0.9.0 전체 엔진·egui 편집 화면을 CY뷰어에 연결한다.
원본: https://github.com/storytold/pdfcraft/tree/50f261d70c8e199600a82dbaa6912c6fbc4b4612

- 고정 아카이브 전체를 받아 SHA-256을 검증한다. 파일 목록은 `docs/PDFCRAFT_SOURCE_INDEX.json`.
- 원본 UI와 엔진은 소스에서 직접 빌드한다. 기존 CY 문서 도구 네 모듈에 그치지 않는다.
- CY 수정: 원본 상표 이미지 제외, 한국어 기본 조작 번역·나눔고딕 폴백, 사본 전달·결과 수신, CY 작업실 진입점.
- 웹은 동일 출처 WASM, Mac/Windows는 설치본에 포함된 Rust 창이다. 서버에 PDF를 업로드하지 않는다.
- 일부 고급 메뉴는 영어로 표시된다. 원본에도 예정 상태인 도구는 구현된 것으로 간주하지 않는다.
- 원본 OCR 모델은 영어 전용이며 네이티브 패키지에만 포함한다. 기존 CY 한국어 OCR 경로는 유지한다.
- 이식 범위는 PDF 엔진·읽기·편집 UI다. 원본의 GitHub CI, 원본 앱 배포/업데이트 서버, 개발용 MCP 서버·브랜드는 CY 제품 기능으로 옮기지 않는다.
- 원본 MIT 저작권과 전체 의존성·자산 라이선스를 설치본과 웹 작업실에 동봉한다.

빌드: `python3 scripts/build_pdf_workbench.py` 또는 `--web`. Native 창은 현재 문서의 별도 사본으로 시작하므로 첫 저장은 새 파일 선택이다. 현재 CY 도구 창에서 아직 저장하지 않은 설정은 이 별도 작업실에 자동 적용되지 않는다.
