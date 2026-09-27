# 홈 화면 아이콘 복구

2026-09-27 iPhone의 ‘홈 화면에 추가’에 CY 로고 대신 기본 C 아이콘이 표시됐다.
기존 아이콘 URL은 HTTP 200으로 응답하지만, manifest는 실제 1254×1254 이미지를 1024×1024로 선언했다. 원본 파일은 약 1.9MB였다. 기기에서 아이콘 선택이 실패한 정확한 원인은 미확정이다.

기존 iOS 앱에 포함된 180×180 CY 로고를 `web/apple-touch-icon.png`로 복사해 명시적인 크기와 함께 연결했다. 새 경로와 버전 쿼리로 기존 아이콘 캐시와 구분했다. 웹 manifest는 기존 Mac 아이콘의 256×256, 512×512 파일을 실제 크기대로 선언하며, maskable 용도로 잘못 선언하지 않는다. 브라우저 favicon과 다운로드 페이지의 Apple 아이콘 링크도 추가했다. 로고 디자인과 네이티브 앱은 변경하지 않았다.

PNG 헤더의 실제 크기와 HTML/manifest 선언을 비교했고, 180px 로고를 직접 확인했다. iPhone의 홈 화면 추가 창은 사용자 기기에서 다시 확인해야 한다.

Apple 참고: https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html
