# CY뷰어 배포 안내

소스, 설치 파일, 아이폰 웹앱은 `Kimmacaroni/CY_Viewer`에서 관리합니다.

## 다운로드 주소

- 설치 파일 및 이전 버전: https://github.com/Kimmacaroni/CY_Viewer/releases
- OS별 최신 다운로드·Mac 실행 안내: https://kimmacaroni.github.io/CY_Viewer/download/
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

별도 다운로드 저장소의 릴리스 3개와 파일 6개는 본 저장소의 Release에 통합되어 있습니다. 2026-09-28에 양쪽의 실제 파일을 다시 내려받아 SHA-256을 검증했습니다. `v1.0.0`의 검증 파일은 원본에서 한 줄에 이어 붙은 두 해시를 정상적인 두 줄로 수정했으며, 설치 파일의 해시는 동일합니다.

- [통합 검증 기록](archive/download-repository/verification.json)
- [원본 v1.0.0 검증 파일](archive/download-repository/SHA256SUMS-v1.0.0-original.txt)
- [이전 안내와 전체 소스 기록](https://github.com/Kimmacaroni/CY_Viewer/tree/codex/archive-download-history)
- [이전 웹 배포 기록](https://github.com/Kimmacaroni/CY_Viewer/tree/codex/archive-download-pages)

두 보존 브랜치는 과거 기록 확인용이며 배포하지 않습니다. 앞으로 소스·안내·설치 파일·웹앱은 본 프로젝트에서만 관리합니다. 별도 다운로드 저장소를 삭제하면 기존 저장소와 릴리스 주소는 사용할 수 없으므로 위의 본 프로젝트 주소를 사용하세요.

이전 웹앱 주소에서 새 주소로 이동하면 브라우저 저장소 경로가 달라집니다.
기존 홈 화면 아이콘은 새 웹앱 주소에서 다시 추가해 주세요.

## Windows 릴리스

1. `installer/CYViewer.iss`의 `MyAppVersion`을 갱신하고 검증한 변경을 `main`에 반영한다.
2. `windows-v1.1.0`처럼 설치 버전과 같은 태그를 push한다.
3. `build-windows.yml`이 Windows에서 시작 화면·PDF 렌더링·탐색·책갈피를 검사하고 PyInstaller와 Inno Setup으로 설치 파일을 만든다.
4. 태그 실행에서 EXE·SHA-256·빌드 의존성 목록을 본 저장소의 공개 Release에 게시한다.

사용자가 배포를 금지하지 않은 작업은 검증부터 실제 배포 확인까지 완료한다.

`publish-desktop-versions.yml`은 main에서 Mac/Windows 소스 버전이 바뀌면 해당 커밋에 플랫폼 버전 태그를 만들고 기존 빌드 워크플로를 명시적으로 실행한다. 기존 공개 태그를 이동하거나 덮어쓰지 않는다. 설치 파일은 기존 플랫폼별 분석·테스트·설치 검사가 성공한 뒤 게시한다. 수동 실행은 아직 릴리스가 없는 현재 버전의 배포를 재시도할 때 사용한다. GitHub의 GITHUB_TOKEN으로 만든 태그 push는 새 워크플로를 시작하지 않으므로 workflow_dispatch를 사용한다. 근거: [GitHub 워크플로 실행 안내](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

배포 사이트는 `/download/`에서 제공하며 사이트 변경도 Pages 배포를 실행한다.
앱의 자동 업데이트는 플랫폼별 정식 릴리스를 조회한다. Windows는 설치 스크립트와 `native_windows/version.py` 버전을 함께 올린다.
상세 동작과 제한은 [다운로드·업데이트 안내](DOWNLOAD_AND_UPDATES.md)를 따른다.
