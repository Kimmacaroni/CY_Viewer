# CY뷰어 기능별 코드 정리 보고서

- **상태**: 구현 완료 / 독립 QA 승인 / macOS CI 성공 / PR 검토 중 / 배포 미수행
- **기능 정리 커밋**: `343a46acbdc8eee6cd68103207c5b885766a47cf`
- **Pull Request**: <https://github.com/Kimmacaroni/CY_Viewer/pull/2>
- **구현 부서**: CY뷰어 코드 정리 담당
- **검토 부서**: 독립 QA·보안 검토부

## 변경 내용

- `native_windows`, `macos_app`, `windows_print`, `personal_pdf_viewer` 네 구현체 모두 보존
- 구현체별 기능 소유권·진입점·버전 출처·검증 범위를 `docs/FEATURE_MAP.md`에 정리
- 참조가 없는 Flutter `PdfReaderPage` 샘플 구현과 전용 미사용 import 제거
- 실제 `AdvancedPdfReaderPage` 실행 경로 유지
- `scripts/verify_structure.py`와 구조 단위 테스트 추가
- 개인 Windows 경로 및 고정 설치 버전 중복 제거

## 보존한 코드

플랫폼 실환경 검증이 없는 상태에서 네 구현체를 병합·삭제하지 않았으며, 1,210줄 Windows Python 본체도 무검증 분할하지 않았습니다.

## 검증

- 구조 검사: 구현체 4개, 오류 0건
- Python 단위 테스트 2/2 통과
- Python 문법 검사 통과
- Windows XML·XAML 5개 파싱 통과
- 두 Flutter 앱의 `AdvancedPdfReaderPage` 연결 각 1건 확인
- 제거된 `PdfReaderPage` 참조 0건 확인
- macOS GitHub Actions build 성공: 5분 13초
- 독립 QA에서 확인된 기능 회귀 및 P1 없음

## 병합·배포 조건

macOS CI는 성공했습니다. 다른 플랫폼 릴리스와 운영 배포는 별도 검증 및 사용자의 명시적 지시 후 수행합니다.
