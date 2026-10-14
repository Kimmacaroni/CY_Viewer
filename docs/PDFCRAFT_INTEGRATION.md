# PdfCraft 페이지 기능 연결

CY뷰어 Mac 1.12.0·Windows 1.9.0의 리더에서 **페이지 구성·병합**을 연다. 현재 문서의 페이지와 순서를 지정하고 필요한 PDF를 추가한 뒤 **새 PDF로 저장**한다. `1-3, 5`는 일부 페이지 추출, `3, 1, 2`는 순서 변경이다. 추가한 문서는 목록 순서대로 현재 문서 뒤에 붙는다. 추가 문서는 제거 후 다시 추가해 순서를 바꿀 수 있다.

## 연결한 코드

[storytold/pdfcraft](https://github.com/storytold/pdfcraft)의 `d9607ec3befcda3e78062ceb5e54b97563aedad1`을 고정해 `pdfcraft-cos`, `pdfcraft-organize`와 그 하위 의존성을 사용한다. `pdfcraft_bridge/Cargo.lock`도 고정한다. 기존 PDF 렌더링·OCR·Drive 엔진은 유지한다.

`cy-pdfcraft`는 CY뷰어에 포함된 Rust 실행 모듈이다. 외부 설치 프로그램이나 PATH의 실행 파일을 호출하지 않는다. JSON 요청을 표준 입력으로 받고, 임시 사본의 PDF 객체를 PdfCraft `Combiner`로 구성해 새 PDF를 만든다. 정상 종료 시 페이지 수를 JSON으로 돌려준다. 네트워크 서버·MCP는 시작하지 않는다. 문서 전송은 없다.

Windows는 현재 문서의 미저장 편집을 포함한 사본을 전달한다. Mac은 이미 읽어 둔 원본 바이트를 사용하며, 화면에만 표시되는 임시 텍스트 표시는 포함하지 않는다. 결과를 독립 엔진으로 다시 열어 페이지 수를 확인한 뒤 저장한다. 현재 문서나 최근 문서 목록을 자동 교체하지 않으며, 결과를 읽으려면 PDF 열기로 선택한다.

## 저장과 지원 범위

- 입력 원본 경로, 심볼릭 링크 및 하드링크에 저장하지 못하도록 확인한다. 결과는 별도 파일이다. 기존 다른 파일의 교체는 운영체제 저장창에서 사용자가 선택한 경우 허용한다.
- Windows는 같은 저장 폴더의 임시 파일을 원자적으로 교체한다. Mac은 NSSavePanel의 사용자 선택 권한 안에서 Data의 atomic 저장을 사용한다.
- Mac 모듈은 Apple Silicon·Intel universal이며 부모 앱의 샌드박스를 상속한다. 실제 모듈을 샌드박스 부모 프로세스에서 실행하는 CI 검사를 포함한다.
- 최대 20개 PDF, 파일당 256MB, 전체 입력·출력 512MB, 최대 100000쪽, 처리 시간 180초. 크기 제한은 프로세스 전체 메모리의 상한을 의미하지 않는다.
- 암호화·전자서명된 입력은 거부한다. 암호나 서명을 조용히 제거해 새 문서로 만들지 않는다. 서명 필드가 있는 Windows 문서도 보수적으로 거부할 수 있다.
- 이 버전의 새 기능은 **Mac·Windows 데스크톱용**이다. 웹·iPhone에는 로컬 실행 모듈을 연결하지 않으며 작동하지 않는 메뉴를 표시하지 않는다. 브라우저 WASM 연결은 별도 작업이다.

## 라이선스와 재현 빌드

PdfCraft 코드는 MIT 조건으로 사용한다. 고정 원본의 MIT 고지는 `pdfcraft_bridge/LICENSE-PDFCRAFT-MIT.txt`에 보존한다. ArtCraft의 상표·로고·글꼴·이미지·UI는 가져오지 않는다.

Rust 1.95 환경에서 `python3 scripts/build_pdfcraft.py`를 실행한다. 결과는 `build/pdfcraft/`의 실행 파일과 `THIRD_PARTY_NOTICES.txt`다. 스크립트는 실제 의존성의 라이선스 파일을 수집하고, 누락되면 실패한다. Windows 설치본 내부 `pdfcraft/`, Mac 앱의 `Contents/Resources/`에 고지를 함께 넣는다.

## 검증

- Rust 범위·순서 검증과 Clippy 경고 오류 검사.
- `tests/pdfcraft_integration.py`: 실제 Rust 모듈로 추출·재정렬·병합 후 PyMuPDF로 다시 열기, 텍스트 순서·페이지 픽셀·내부 링크·주석·동명 폼 필드 분리·책갈피·한글 파일 경로 검증. 입력 체크섬 및 덮어쓰기 거부 검사.
- Windows: 원본과 하드링크 보호 단위 검사 및 실제 GUI 대화상자에서 `2,1` 결과 저장하는 smoke 검사.
- Flutter: 범위 오류 및 좁은 화면·큰 글자 구성 화면 검사. 전체 기존 회귀 검사도 실행한다.
- Mac: 앱 빌드·코드 서명 확인 및 실제 샌드박스 부모→배포 모듈→PDFKit 재열기 검사. 로컬 Linux에서 Mac GUI 검증했다고 보고하지 않는다.

배포 설치 파일과 공개 버전의 확인 결과는 릴리스 완료 뒤 기록한다.
