# 공개 사용과 한국어·영어 지원

## 공개 주소

- 다운로드: https://kimmacaroni.github.io/CY_Viewer/download/
- 웹앱: https://kimmacaroni.github.io/CY_Viewer/
- 저장소와 설치 파일: https://github.com/Kimmacaroni/CY_Viewer

저장소는 public이며 다운로드 사이트와 웹앱은 로그인 없이 이용한다. 추가로 권한이나 비밀 정보를 공개하지 않는다.

## 언어

기기 언어가 한국어면 한국어, 그 외에는 영어로 시작한다. 앱과 사이트에서 한국어·English·System을 선택할 수 있다. 웹과 Mac은 즉시 적용되며 열린 문서를 닫지 않는다. Windows는 메뉴에서 선택을 저장하고 다음 실행부터 적용하며, 저장되지 않은 문서를 강제로 닫지 않는다. 운영체제 파일 선택창 및 인쇄창은 운영체제 언어를 따른다. PDF 내용 자체를 번역하거나 OCR 인식 언어를 추가하는 기능은 아니다.

번역 원본은 `localization/en.json`이다. 원문 한국어와 동적 인수 `{0}` 등을 유지한다. `python3 scripts/generate_localizations.py`로 Flutter, Python, Swift, 다운로드 페이지의 번역 데이터를 생성한 다음 Dart 형식을 정리한다. 보관 폴더 및 저장된 문서 데이터 키는 언어 변경으로 바꾸지 않는다.

Mac은 v1.6.0, Windows는 v1.3.0으로 배포한다. 네이티브 업데이트 알림 및 Mac 기본 메뉴도 번역한다. 기존 파일 선택 버튼은 사용자가 PDF 열기와 본문 표시를 확인한 기본 HTML file input 방식을 유지한다.

## 검증 범위

기존 PDF·업데이트 회귀 검사와 함께 언어 저장, 영어 대체, 동적 인수 보존, 열린 화면 유지, 320px/1024px 영어 레이아웃을 검사한다. 실제 iPhone/Windows/Mac의 언어별 모든 GUI 흐름을 자동 테스트로 검증했다고 간주하지 않는다.

## 릴리스 검사 기록

- PR #9에서 Flutter 분석·30개 테스트, 웹·Mac 빌드, Windows PDF 렌더링·탐색·책갈피 및 설치·재설치 검사가 통과했다.
- 로컬 Windows 단위 검사 9개, 사이트 검사 4개, Mac 업데이트 검증이 통과했다.
- 정식 배포 태그: `macos-v1.6.0`, `windows-v1.3.0` (PR #9의 최종 소스이며 병합 결과와 파일 내용이 동일하다).
- 실제 iPhone의 영어 UI와 모든 운영체제별 수동 GUI 검증은 별도다. 브라우저 자동화 연결이 끊겨 이 작업에서 실제 브라우저 화면 검증은 수행하지 못했다.
