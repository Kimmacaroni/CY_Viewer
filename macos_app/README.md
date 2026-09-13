# CY뷰어 for Apple 플랫폼과 웹

CY뷰어 메인 저장소에서 관리하는 macOS·iPhone·iPad용 앱입니다.

## 대상 환경

- macOS 12 Monterey 이상
- Apple Silicon 및 Intel Mac
- iOS/iPadOS 15 이상
- iPhone Safari용 설치형 웹앱(PWA)

## 아이폰에서 GitHub로 설치

1. Safari에서 [CY뷰어 웹앱](https://kimmacaroni.github.io/CY_Viewer/)을 엽니다.
2. Safari의 `공유` 버튼을 누릅니다.
3. `홈 화면에 추가`를 누른 뒤 `추가`를 선택합니다.
4. 홈 화면의 `CY뷰어` 아이콘으로 실행하고 `PDF 선택`을 누릅니다.

웹앱에서 연 PDF는 서버로 전송되지 않습니다. PDF 열기, 검색, 책갈피,
페이지 이동, 확대·축소, 보기 방식 변경, 인쇄, PDF 저장·공유를 지원합니다.
브라우저 보안 제한 때문에 네이티브 Apple Vision OCR과 페이지별 PNG·JPG 저장은
macOS/iOS 앱에서만 사용할 수 있습니다.

## 사용자 기능

- PDF 열기와 문서 탐색
- 페이지 이동 및 확대·축소
- 문서 검색
- 텍스트 선택과 표시
- 페이지 책갈피
- Finder에서 PDF 끌어놓기
- macOS 시스템 인쇄 창
- 세로·가로 스크롤 및 두 페이지 보기
- PDF 복사본, 페이지별 PNG·JPG 저장
- Apple Vision 기반 한국어·영어 문서 전체 OCR
- CY뷰어 전용 앱 아이콘
- iPhone·iPad 파일 앱에서 PDF 가져오기 및 다른 앱에서 PDF 열기

## macOS 단축키

- `⌘O`: PDF 열기
- `⌘F`: 문서 검색
- `⌘G` / `⇧⌘G`: 다음 / 이전 검색 결과
- `⌘+` / `⌘-` / `⌘0`: 확대 / 축소 / 실제 크기
- `⌘S`: PDF 복사본 저장
- `⌘P`: 인쇄

macOS 설치 파일과 기존 iOS 테스트 파일은 [본 저장소의 릴리스](https://github.com/Kimmacaroni/CY_Viewer/releases)에서 관리합니다. 기존 iOS IPA는 서명 전 개발용 파일이며, 실제 iPhone 설치 또는 TestFlight 배포에는 Apple 개발자 서명이 필요합니다. 유선 연결이나 개발자 서명 없이 아이폰에서 사용할 때는 위의 GitHub Pages 웹앱을 이용하세요.

웹앱은 `main` 변경 시 본 저장소의 GitHub Actions에서 빌드하여 배포합니다.
macOS 릴리스는 `macos-v버전` 태그로 게시합니다. 자세한 절차는
[배포 안내](../docs/RELEASES.md)를 확인하세요.
