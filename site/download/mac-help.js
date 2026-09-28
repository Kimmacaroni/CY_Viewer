/* 기본 dialog로 Escape 닫기와 열기 버튼으로의 포커스 복귀를 유지한다. */
(() => {
  const button = document.getElementById('mac-required');
  const dialog = document.getElementById('mac-install-dialog');
  button.addEventListener('click', () => {
    if (!dialog.open) dialog.showModal();
  });
})();
