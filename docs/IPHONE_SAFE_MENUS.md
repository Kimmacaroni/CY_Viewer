# 아이폰 메뉴 안전 영역 보완

사용자가 제공한 문서함 스크린샷의 메뉴 가림 신고에 대응한다. 이전 듀오 수정은 전체 PDF 작업실의 크기 대응이었으며 Flutter 문서함·리더·대화상자의 브라우저 안전 영역 연결이 빠져 있었다.

CSS safe-area-inset 네 방향을 숨겨진 측정 요소로 읽어 웹 루트 SafeArea에 전달한다. 기존 OS 여백과 중복 적용하지 않고 큰 쪽을 사용한다. 내부 MediaQuery 크기도 실제 내용 영역으로 줄여 전체 화면 도구와 대화상자가 그 안에서 배치되게 한다. 회전 및 홈 화면 실행 직후 뒤늦게 바뀌는 환경 값을 관찰하고 닫히면 관찰/타이머/측정 요소를 해제한다.

홈 화면 상태 표시줄 설정도 black-translucent에서 default로 바꿔 콘텐츠를 덮는 구성을 해제한다. Apple Safari HTML Reference의 Supported Meta Tags 기준이다(https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariHTMLRef/Articles/MetaTags.html). 실제 iOS 버전별 동작은 실기기 확인과 구분한다.

모델명이나 스크린샷의 상태줄 크기를 제품 코드에 고정하지 않는다. CSS 변수를 통해 같은 값을 전체 작업실에도 제공한다. 기존 HTML 파일 선택/인쇄는 Flutter 전역 좌표를 사용하므로 이동한 메뉴와 터치 위치가 함께 유지된다. 한국어·원본 보호·제작자 고지는 유지한다.

웹만 변경한다. Mac/Windows 설치본은 변경하지 않는다. 웹 버전 1.17.1+28, 새 배포 식별자 iphone-safe-menus-20261024-1.

검증: Flutter 분석 및 안전 영역 중복/실제 내용 크기 회귀 검사 통과. Chrome·WebKit의 밝음/어두움에서 상단30·오른쪽112·하단24·왼쪽16px의 안전 영역을 주입하고 문서함 메뉴, 실제 HTML 파일 선택 터치, 리더 메뉴, 편집 대화상자, 세로 회전 후 탭 보존 검사 통과. Flutter 63개 통과(기존 네이티브 의존 검사 5개 건너뜀), 추가 안전 영역 검사도 통과. 공개 배포 검증은 진행 중이다. 실제 사용자 기기에서의 해소 확인은 별도다.
