# CY뷰어 작업 기록

## 목표

개인용 PDF 뷰어 **CY뷰어**를 Flutter로 제작했다. 하나의 코드베이스로 Windows, macOS, iOS, Android를 지원하도록 프로젝트를 구성했다.

## 현재 구현 기능

- 기기에서 PDF 파일 선택 및 열기
- 확대/축소, 스크롤, 페이지 직접 이동
- 문서 텍스트 검색 및 검색 결과 이동
- 최근 열람 문서 목록과 즐겨찾기
- 마지막 읽은 페이지 복원
- 문서별 책갈피 추가, 삭제, 목록 이동
- 다크 모드
- 텍스트 선택 후 복사와 전체 선택
- 텍스트 선택 영역의 형광펜, 밑줄, 취소선, 굵게 강조 표시
- Windows용 앱 제목, 제품명, 바탕화면 바로가기 이름을 `CY뷰어`로 설정
- `CY` 글자, PDF 라벨, 문서 이미지를 조합한 Windows 앱 아이콘

## 프로젝트 구성

```text
personal_pdf_viewer/
├─ lib/
│  ├─ app.dart              # 문서함, 최근 문서, 즐겨찾기
│  ├─ advanced_reader.dart  # PDF 뷰어, 검색, 책갈피, 텍스트 표시
│  └─ main.dart             # 앱 시작점
├─ assets/cy_viewer_icon.png
├─ windows/                 # Windows 실행 파일 설정 및 아이콘
├─ android/
├─ ios/
└─ macos/
```

## 사용한 주요 패키지

| 패키지 | 용도 |
| --- | --- |
| `pdfrx` | 여러 플랫폼의 PDF 렌더링, 텍스트 선택, 검색 |
| `file_picker` | PDF 파일 선택 |
| `shared_preferences` | 최근 문서, 즐겨찾기, 읽은 위치, 책갈피 저장 |
| `flutter_localizations` | 한국어 Material UI 및 텍스트 선택 메뉴 지원 |
| `flutter_launcher_icons` | Windows 앱 아이콘 생성 |

## Windows 실행 방법

### 개발 환경

1. Flutter SDK를 설치한다.
2. Visual Studio에서 **C++를 사용한 데스크톱 개발** 워크로드를 설치한다.
3. Windows 개발자 모드를 켠다.
4. 프로젝트 폴더에서 실행한다.

```powershell
flutter pub get
flutter run -d windows
```

### 현재 PC의 실행 경로

원본 소스는 한글 경로에 있다.

```text
C:\Users\ForYou\Documents\ChatGPT\[인공지능] 관련자료\personal_pdf_viewer
```

Windows C++ 빌드 도구는 일부 환경에서 한글 경로를 잘못 처리할 수 있다. 그래서 실제 Windows 빌드 및 실행에는 영문 경로 복사본을 사용했다.

```text
C:\Users\ForYou\Documents\CYViewer
```

바탕화면의 `CY뷰어` 바로가기는 이 영문 경로의 릴리스 실행 파일을 가리킨다.

## 작업 과정 요약

1. Flutter 크로스플랫폼 프로젝트 생성
2. PDF 렌더링, 파일 선택, 로컬 저장소 패키지 연결
3. 문서함과 PDF 리더 화면 구현
4. 검색, 책갈피, 마지막 읽은 위치 기능 추가
5. 한국어 로컬라이제이션과 자체 컨텍스트 메뉴 적용
6. CY/PDF/문서 이미지를 활용한 아이콘 생성 및 Windows 아이콘 적용
7. 한글 경로 Windows 빌드 문제를 피하기 위해 영문 빌드 경로 구성
8. GitHub 저장소에 소스 업로드

## 알려진 제약 및 다음 개선 항목

- 텍스트 형광펜·밑줄·취소선·굵게 표시는 현재 열린 문서 세션에서 PDF 위에 그려지는 방식이다. PDF 파일 자체에 영구 주석으로 기록하거나 재실행 후 복원하는 기능은 별도 구현이 필요하다.
- PDF 파일이 이미지 스캔본이면 텍스트 선택·검색이 제한된다. OCR 기능을 추가하면 개선할 수 있다.
- iOS 빌드는 macOS와 Xcode가 필요하다.
- Android 실행은 Android Studio 및 Android SDK 설치가 필요하다.

## GitHub

- 저장소: <https://github.com/Kimmacaroni/CY_Viewer>
- 기본 브랜치: `main`
