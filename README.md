# CY뷰어

PDF를 읽고, 찾고, 표시하고, 저장하고, 인쇄할 수 있는 개인용 문서 뷰어입니다.

## 다운로드

**[CY뷰어 배포 사이트](https://kimmacaroni.github.io/CY_Viewer/download/)**에서 접속한 기기에 맞는 버전을 받을 수 있습니다. 소스 코드, 설치 파일, 웹앱을 이 저장소에서 함께 관리합니다.

| 사용 환경 | 다운로드 및 실행 |
| --- | --- |
| Windows 10·11 64비트 | [Windows 설치 파일 v1.4.0](https://github.com/Kimmacaroni/CY_Viewer/releases/download/windows-v1.4.0/CYViewer-Setup-v1.4.0.exe) |
| macOS | [macOS 설치 파일 v1.7.0](https://github.com/Kimmacaroni/CY_Viewer/releases/download/macos-v1.7.0/CYViewer-macOS-v1.7.0.dmg) |
| iPhone·iPad·웹 | [CY뷰어 웹앱 열기](https://kimmacaroni.github.io/CY_Viewer/) |

아이폰에서는 Safari로 웹앱을 연 뒤 `공유` → `홈 화면에 추가`를 선택하면
CY뷰어 아이콘으로 실행할 수 있습니다. 개발자 모드나 유선 연결은 필요하지 않습니다.

Windows 10·11 64비트 환경을 지원합니다. Release에서 `CYViewer-Setup-v1.4.0.exe`를 내려받아 설치하세요. 설치 마법사에서 설치 위치와 바탕화면 바로가기 생성 여부를 선택할 수 있습니다.

## 업데이트

Mac 1.5.0·Windows 1.2.0부터 앱 실행 시 새 버전을 자동으로 확인합니다. 기존 버전 사용자는 새 설치 파일을 한 번 직접 설치해 주세요.
Windows는 다운로드·검증 후 설치 확인을 누르면 앱을 종료하고 업데이트한 뒤 재실행합니다. 저장하지 않은 변경이 있으면 먼저 저장해야 합니다.
Mac은 다운로드·검증 후 DMG를 열며, Applications로의 마지막 교체는 직접 합니다.
자세한 설명은 [다운로드·업데이트 안내](docs/DOWNLOAD_AND_UPDATES.md)를 확인하세요.

## 주요 기능

- PDF 열기 및 파일 끌어놓기
- 한 페이지, 연속 스크롤, 좌우 보기
- 페이지 이동과 확대·축소
- 문서 전체 검색
- 페이지 책갈피
- 한국어·영어 문서 전체 OCR
- 텍스트, 이미지, 빈 영역 구분 선택
- 선택한 글자에 형광펜, 밑줄, 취소선, 굵게 적용
- 선택 문구 수정 및 복사
- PDF, JPG, PNG 저장
- Windows 인쇄 설정 및 미리보기
- 오프라인 문서 처리

## 빠른 사용법

1. `PDF 열기`를 누르거나 PDF 파일을 창 안으로 끌어놓습니다.
2. 문구를 마우스로 드래그해 선택합니다.
3. 선택한 문구를 마우스 오른쪽 버튼으로 눌러 표시 또는 수정 기능을 사용합니다.
4. 필요한 형식으로 저장하거나 인쇄합니다.

자세한 설명은 [CY뷰어 사용 설명서](docs/USER_GUIDE.md)를 확인하세요.

Apple 앱과 웹앱의 기능 차이는 [플랫폼 안내](macos_app/README.md),
빌드와 배포 방법은 [배포 안내](docs/RELEASES.md)를 확인하세요.

## 개인정보

문서는 사용자의 PC에서 처리됩니다. CY뷰어는 문서 내용을 별도의 서버에 업로드하지 않습니다.

## 문의 및 오류 제보

[GitHub Issues](https://github.com/Kimmacaroni/CY_Viewer/issues)에 사용 중인 Windows 버전, 문제 상황, 오류 화면을 함께 남겨 주세요.

## 배포 안내

CY뷰어와 아이콘의 저작권은 저장소 소유자에게 있습니다. 프로그램을 다시 배포하거나 상업적으로 이용하려면 저장소 소유자의 허가를 받아 주세요.

## Public downloads / 공개 사용

Anyone can use [CY Viewer on the web](https://kimmacaroni.github.io/CY_Viewer/) or download the Mac/Windows apps from the [download site](https://kimmacaroni.github.io/CY_Viewer/download/), without signing in.

CY Viewer supports **한국어 and English**. It follows the device language by default (English for other languages). Use the language menu to choose manually. Web and Mac apply changes immediately; Windows applies the selected language next time it starts. Your PDF content is not translated or uploaded.

한국어·영어와 기기 언어 자동 선택을 지원합니다. 웹·Mac은 언어 선택을 바로 반영하고 Windows는 문서 작업을 유지하기 위해 다음 실행부터 반영합니다. 파일 선택·인쇄 창의 언어는 운영체제 설정을 따릅니다.

## 최근 열어본 파일

웹·Mac·Windows에서 최근 열어본 파일을 최대 5개 표시합니다. 다시 연 파일은 맨 위로 이동합니다. 웹은 브라우저 안에 PDF 사본을 저장해 다시 열며, 목록의 제거 버튼으로 사본을 삭제할 수 있습니다. 목록은 기기·브라우저별로 관리되고 자동 동기화하지 않습니다. [보관 방식과 제한](docs/RECENT_FILES.md)을 참고하세요.
