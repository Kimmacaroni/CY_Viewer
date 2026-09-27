'use strict';
(() => {
  const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const environment = standalone ? '홈 화면 웹앱' : '일반 브라우저';
  document.getElementById('environment').textContent = `실행 환경: ${environment}`;
  const file = document.getElementById('file');
  const fileStatus = document.getElementById('file-status');
  const printStatus = document.getElementById('print-status');
  let clicks = 0;
  let before = 0;
  let after = 0;
  function summary() {
    document.getElementById('summary').textContent = `${environment} · 인쇄 클릭 ${clicks} · 인쇄 시작 이벤트 ${before} · 종료 이벤트 ${after}`;
  }
  file.addEventListener('click', () => { fileStatus.textContent = '터치가 전달됐습니다. 파일 목록이 열리는지 확인해 주세요.'; });
  file.addEventListener('cancel', () => { fileStatus.textContent = '파일 선택이 취소됐습니다.'; });
  file.addEventListener('change', () => {
    fileStatus.textContent = file.files[0] ? `선택 완료: ${file.files[0].name}` : '선택한 파일이 없습니다.';
  });
  window.addEventListener('beforeprint', () => {
    before++;
    printStatus.textContent = '브라우저가 인쇄 시작 이벤트를 보냈습니다. 실제 시스템 창이 보이는지 확인해 주세요.';
    summary();
  });
  window.addEventListener('afterprint', () => {
    after++;
    printStatus.textContent = '인쇄 종료 이벤트를 받았습니다. 실제 창이 열렸는지 알려 주세요.';
    summary();
  });
  document.getElementById('print').addEventListener('click', () => {
    clicks++;
    printStatus.textContent = '버튼 터치를 받았습니다. 시스템 인쇄 창을 요청합니다.';
    summary();
    const started = before;
    try { window.print(); }
    catch (error) { printStatus.textContent = `인쇄 호출 오류: ${error.name}`; return; }
    setTimeout(() => {
      if (before === started) printStatus.textContent = '인쇄 시작 이벤트가 감지되지 않았습니다. 창이 실제로 열렸는지 알려 주세요.';
    }, 2500);
  });
  summary();
})();
