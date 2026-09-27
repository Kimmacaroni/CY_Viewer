# 설치형 웹앱 PDF 선택 버튼

2026-09-27 홈 화면에 추가한 웹앱에서 PDF 열기 버튼이 반응하지 않는 현상이 보고됐다.

기존 구현은 Flutter FilledButton, 투명한 HTML 파일 입력, 포커스 표시용 Flutter 레이어를 겹쳤다. 별도 Flutter 클릭 경로는 화면 밖에 입력을 만들고 합성 click을 호출하며, 취소 이벤트가 오지 않으면 `_opening`이 계속 true로 남을 수 있었다. 해당 기기의 터치 이벤트를 직접 관찰하지 못했으므로 원인을 확정한 것은 아니다.

웹 버튼을 하나의 HTML 컨트롤로 통합했다. 실제 file input이 버튼 전체 터치를 직접 받고, 문구와 포커스 테두리도 동일한 DOM 안에 표시한다. Flutter 버튼과 합성 click 경로를 제거했다. 파일 선택창이 열려 있는 동안에는 잠금 상태를 만들지 않고, 실제 파일을 읽는 동안만 중복 입력을 막는다. 동일한 파일을 다시 선택할 수 있도록 값을 초기화하며, 파일 읽기가 60초 동안 완료되지 않으면 오류를 표시하고 버튼을 복구한다. 기존 PDF 리더와 로고·다운로드 사이트는 유지한다.

Flutter 공식 문서의 HTML platform view 포인터 및 합성 레이어 동작을 참고했다:
https://docs.flutter.dev/platform-integration/web/web-content-in-flutter

iPhone 홈 화면 웹앱에서 파일 선택창을 직접 여는 검증은 아직 필요하다. 일반 Flutter 위젯 테스트 및 웹 컴파일 성공을 실제 iPhone 검증으로 간주하지 않는다.
