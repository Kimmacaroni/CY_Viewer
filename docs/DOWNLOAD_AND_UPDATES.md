# 배포 사이트와 앱 업데이트

## 공개 진입점

배포 사이트: `https://kimmacaroni.github.io/CY_Viewer/download/`
웹앱: `https://kimmacaroni.github.io/CY_Viewer/`

기존 웹앱/PWA 경로는 유지한다. 배포 사이트는 OS를 감지해 상단 추천 버튼을 바꾸고 모든 플랫폼 링크도 항상 제공한다.
iPad의 데스크톱 Mac User-Agent는 터치 포인트로 구분한다. 모바일/알 수 없는 기기는 웹앱을 추천한다.
GitHub의 공개 정식 릴리스에서 플랫폼별 가장 높은 완성 버전을 고른다. 조회 오류에는 마지막 배포본 링크를 남기고 상태를 안내한다.

## 앱 업데이트

- Windows 1.2.0, macOS 1.5.0부터 시작 5초 후 및 6시간마다 확인한다. 기존 버전에는 업데이트 코드가 없으므로 이 버전을 한 번 직접 설치해야 한다.
- 수동 확인: Windows 상단 ‘업데이트 확인’, Mac 문서함 상단 업데이트 아이콘.
- GitHub API는 인증 없이 HTTPS로 조회한다. 초안·시험 버전·현재 버전 이하·설치/체크섬 파일이 없는 릴리스는 제외한다.
- 설치 파일 URL은 고정 저장소의 정확한 플랫폼·버전·파일명과 일치해야 한다. 파일 크기와 SHA-256이 맞지 않으면 설치하지 않는다.
- SHA-256은 전송 무결성 검사다. Apple/Windows 게시자 코드 서명을 대신하지 않는다.

### Windows

알림에서 다운로드에 동의하면 백그라운드로 받는다. 검증 후 별도 설치 확인을 받으며 미저장 변경이 있으면 설치를 시작하지 않는다.
설치 도우미는 현재 앱 프로세스가 종료될 때까지 기다린 뒤 현재 설치 폴더에 Inno Setup의 `/SILENT /NORESTART /NOCLOSEAPPLICATIONS`로 설치한다.
설치 성공일 때만 앱을 재실행한다. 설치 오류에는 안내를 표시한다. 강제 재부팅이나 다른 실행 중인 앱의 강제 종료는 하지 않는다.
개발 실행에서는 설치 동작을 시작하지 않는다.

### macOS

기존 App Sandbox를 유지하고 업데이트 확인·다운로드용 `network.client` 권한을 추가한다.
다운로드와 검증이 끝나면 사용자가 DMG를 열 수 있다. 앱을 종료하고 Applications로 옮기는 마지막 교체는 직접 한다.
완전 자동 교체를 위해서는 안정적인 업데이트 서명/배포 체계를 갖춘 Sparkle 통합을 별도로 진행해야 한다. 현재 서명·공증 전 배포본에서 샌드박스를 해제하거나 임의 셸 스크립트로 자기 앱을 교체하지 않는다.

참고: [Sparkle 문서](https://sparkle-project.org/documentation/), [Inno Setup 설치 인수](https://jrsoftware.org/ishelp/topic_setupcmdline.htm).

## 이후 배포

- Mac은 `pubspec.yaml`, Windows는 `version.py`와 `installer/CYViewer.iss` 버전을 함께 갱신한다.
- 공개 태그는 `macos-vX.Y.Z`, `windows-vX.Y.Z`. 기존 워크플로에서 설치 파일과 SHA256SUMS를 함께 공개한다.
- 사이트와 앱은 공개 릴리스를 직접 조회하므로 정상 게시 후 별도 버전 피드를 편집할 필요가 없다.
- 사이트의 JavaScript 없는 fallback 링크는 새 릴리스 확인 후 갱신한다.
- 실패·오프라인은 자동 확인에서는 조용히 넘어가고 수동 확인에서는 오류를 표시한다. 사용자 문서는 변경하지 않는다.

## 검증

OS·정식 릴리스 선택 테스트 3개, Windows 업데이트 테스트 7개, Mac Swift 릴리스 선택·버전·체크섬 검사와 Flutter 회귀 테스트 17개를 실행한다. Windows CI에서는 실제 앱 PDF 검사와 설치 파일의 설치·덮어쓰기 및 실행 파일 해시 검사를 수행한다.
2026-09-26 로컬 Mac 빌드와 Flutter 분석·테스트가 통과했다. Chrome의 다른 확장 프로그램 UI로 브라우저 제어가 차단되어 실제 배포 사이트의 시각 검증은 완료하지 못했다. Mac 업데이트 알림부터 DMG 열기까지의 실제 GUI 및 사용자 PC에서 이전 버전→새 버전 전체 업데이트는 별도 확인이 필요하다.
