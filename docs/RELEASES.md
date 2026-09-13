# CY뷰어 배포 안내

소스, 설치 파일, 아이폰 웹앱은 `Kimmacaroni/CY_Viewer`에서 관리합니다.

## 다운로드 주소

- 설치 파일 및 이전 버전: https://github.com/Kimmacaroni/CY_Viewer/releases
- Windows v1.0.0: https://github.com/Kimmacaroni/CY_Viewer/releases/tag/v1.0.0
- 아이폰 웹앱: https://kimmacaroni.github.io/CY_Viewer/

Windows, macOS, iOS는 릴리스 버전이 다를 수 있습니다. Windows 링크는
Windows 설치 파일이 포함된 릴리스를 가리킵니다. iOS의 `unsigned.ipa`는
서명 전 테스트 파일이며, 일반 사용자용 설치 파일이 아닙니다.

## 웹앱 배포

GitHub 저장소의 Settings → Pages에서 Source를 `GitHub Actions`로 설정합니다.
`main`의 `macos_app` 또는 웹 배포 워크플로가 바뀌면 `deploy-web.yml`이
분석·테스트·웹 빌드를 수행하고 Pages에 배포합니다. 수동 실행도 지원합니다.
PR에서는 빌드만 확인하고 배포하지 않습니다.

웹 진입점은 `macos_app/lib/web_main.dart`이며, 배포 경로는 저장소 이름을
사용한 `/CY_Viewer/`입니다. 빌드 산출물은 소스 브랜치에 커밋하지 않습니다.

## macOS 릴리스

1. `macos_app/pubspec.yaml`의 버전과 빌드 번호를 갱신하고 `main`에 반영합니다.
2. 해당 커밋에 `macos-v1.3.1`처럼 앱 버전과 일치하는 태그를 만들어 push합니다.
3. `build-macos.yml`이 분석·테스트·빌드 후 DMG와 SHA-256 파일을 생성합니다.
4. 태그 실행에서는 본 저장소의 GitHub Release에 파일을 업로드하고 게시합니다.

일반 브랜치 push, PR, 수동 실행에서는 Actions 산출물만 생성합니다.
워크플로는 태그와 앱 버전이 다르면 게시하지 않습니다. 패키지명은
`pubspec.yaml`에서 읽으므로 워크플로 안의 버전을 별도로 수정하지 않습니다.

## 이전 다운로드 저장소

`CY_Viewer_Download`의 기존 릴리스 파일은 원본과 SHA-256을 비교하여
본 저장소로 통합합니다. 기존 Windows 릴리스에 같은 이름의 파일이 있으면
내용이 같은지 확인하고 재사용합니다. 통합 이후 새 배포는 본 저장소에서만
진행하며, 이전 저장소는 기존 주소를 사용하는 사람을 위한 이전 안내로 유지합니다.

이전 웹앱 주소에서 새 주소로 이동하면 브라우저 저장소 경로가 달라집니다.
기존 홈 화면 아이콘은 새 웹앱 주소에서 다시 추가해 주세요.
