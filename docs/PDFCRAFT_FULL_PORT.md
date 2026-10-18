# PdfCraft 전체 엔진·작업실 연결

사용자 요청은 기존 네 모듈의 메뉴 확대가 아니라 ArtCraft PDF 뷰어의 전체 코드 이식이다.
전체 소스를 확보한 뒤 엔진과 원본 편집 UI를 소스 의존성으로 빌드해 CY뷰어에 연결한다.

원본: https://github.com/storytold/pdfcraft/tree/50f261d70c8e199600a82dbaa6912c6fbc4b4612

- 기준: PdfCraft 0.9.0, 커밋 `50f261d70c8e199600a82dbaa6912c6fbc4b4612`.
- 전체 아카이브 SHA-256: `2b0b0e3ba0be381b73eccb448d3a4c7b033a265164acf37f5077e0b00eec4faa`.
- 소스 파일 인덱스: `PDFCRAFT_SOURCE_INDEX.json` (Rust·TOML·HTML·언어 카탈로그 977개, vendor 포함 Rust 426,873줄).
- 숫자는 확보한 소스의 양이며 모든 줄을 사람이 정독하거나 모든 기능을 검증했다는 뜻은 아니다. 엔진 공개 API·도구 카탈로그·원본 UI·웹 host 계약·네이티브 시작·보안·저장 경로를 중심으로 검토했다.

## 연결 범위

| 계층 | 연결 |
| --- | --- |
| cos·crypt·filters·geom·model·content·fonts | PDF 해석·저장·암호·폰트·내용의 원본 구현 |
| render | 원본 렌더러와 텍스트/객체 선택 |
| organize·edit·create·optimize | 페이지·본문/이미지·새 문서·최적화 |
| annot·xfdf·measure | 주석·검토 데이터·측정 |
| forms·xfa·js | PDF 양식과 스크립트 샌드박스 |
| redact·audit | 실제 삭제와 숨은 정보 검사 |
| compare·export·preflight·a11y | 비교·내보내기·출력 전 검사·접근성 도구 |
| sign·print·ocr·platform | 서명·인쇄·문자 인식·OS 서비스 |
| engine·ui-egui | 원본 기능 카탈로그·문서 세션·원본 전체 편집 화면 |
| automation·oracle·testkit·xtask | 개발/검증 도구의 소스도 확보하되 사용자 앱의 원격 제어 서버로 자동 실행하지 않음 |

`Ready`·`Planned`·`Provider` 구분은 원본 카탈로그 상태를 유지한다. 원본에 없는 기능이나
외부 OCR/클라우드 제공자를 새로 구현했다고 주장하지 않는다. 기존 네 모듈 어댑터는
검증된 이전 고정 소스를 유지하며 전체 작업실이 별도 최신 소스를 사용한다.

## 사용자 흐름

PDF 도구 → 전체 PDF 작업실. 리더에서 연 문서의 사본으로 시작한다. 기존 도구 창에서
아직 저장하지 않은 설정과 리더 임시 표시는 자동 합성되지 않는다.

Mac/Windows는 설치본 내 Rust 편집 창을 실행한다. 원본 경로를 넘기지 않으므로 첫 저장은
새 파일 선택이다. 임시 사본은 프로세스 종료 후 CY에서 정리한다. 웹은 같은 출처 iframe의
WASM 작업실로 메모리 사본을 전달한다. 저장 결과는 준비와 다운로드 요청을 구분하며
CY뷰어에서 열 수도 있다. 미저장 변경을 닫을 때 확인하고 원본 사본·비밀번호를 URL에 넣지 않는다.

## 유지 조건과 제한

- ArtCraft Team 및 PdfCraft contributors의 MIT 저작권 전문, 원본 NOTICE·자산·실제 의존성 라이선스를 동봉한다. 원본 상표 이미지는 빌드 소스에서 제외한다.
- 한국어 기본 조작 카탈로그와 OFL 나눔고딕 UI 폴백을 추가한다. 일부 고급 설명은 영어 원문이다. UI 글꼴 추가가 모든 PDF 내용의 한글 편집 지원을 의미하지 않는다.
- 원본 OCR 모델은 영어 전용이며 Mac/Windows에만 동봉한다. 기존 CY의 한국어 OCR은 유지한다.
- 원본 앱의 자체 업데이트 서버와 배포 CI를 CY에 복사하지 않는다. CY 설치본은 기존 CY 업데이트 경로를 쓴다.
- 원본의 고급 편집 UI를 그대로 연결하는 기능 이식이다. 작업실 전체를 AppKit으로 다시 만든 것이나 Apple HIG 완전 준수로 표시하지 않는다.
- 아이폰 홈 화면 컨테이너의 이전 터치 신고는 실기기 확인이 남아 있으며 이 이식의 데스크톱/브라우저 검사만으로 해결됐다고 간주하지 않는다.

## 검증 기록

진행 중. 출시·공개 파일 검증 결과는 완료 후 기록한다.
