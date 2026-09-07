# CY뷰어

개인용 PDF 뷰어입니다. 하나의 Flutter 코드로 Windows, macOS, iOS, Android에서 동작하도록 구성했습니다.

## 제공 기능

- PDF 열기, 스크롤, 확대·축소, 페이지 번호 이동
- 문서 텍스트 검색과 검색 결과 이전·다음 이동
- 최근 문서, 즐겨찾기, 마지막 읽은 페이지 복원
- 문서별 책갈피 추가·목록·삭제
- 다크 모드
- 텍스트 선택 후 복사·형광펜·밑줄·취소선·강조
- CY/PDF/문서 이미지를 사용한 앱 아이콘과 앱 제목 `CY뷰어`

## 텍스트 표시 사용법

문서에서 글자를 드래그해 선택하면 화면 아래에 도구막대가 나타납니다. 여기서 **복사**, **형광펜**, **밑줄**, **취소선**, **강조**를 누르면 됩니다.

우클릭 메뉴는 사용하지 않습니다. 일부 Windows 환경에서 PDF 라이브러리의 우클릭 메뉴가 선택 좌표 오류를 내던 문제를 피하고, 모든 기기에서 같은 위치의 도구막대를 쓰도록 변경했습니다.

표시는 열린 문서 화면에 적용되며, PDF 원본 파일을 직접 수정하지는 않습니다. 기능 메뉴의 **이 문서의 표시 지우기**로 현재 표시를 지울 수 있습니다.

## 실행

```powershell
flutter pub get
flutter run -d windows
```

Windows 빌드 도구가 한글 경로를 처리하지 못하는 경우에는 영문 경로(예: `C:\Users\ForYou\Documents\CYViewer`)에 프로젝트를 두고 빌드하세요.

## 개발 환경별 준비물

| 대상 | 준비물 |
| --- | --- |
| Windows | Flutter, Visual Studio의 C++ 데스크톱 개발 구성 요소 |
| Android | Flutter, Android Studio 및 Android SDK |
| iOS | macOS, Xcode, Flutter |
| macOS | macOS, Xcode, Flutter |
