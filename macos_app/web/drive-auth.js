// 토큰은 메모리에서만 사용하며 저장소나 URL에 기록하지 않습니다.
window.cyDriveAuthorize = () => new Promise((resolve, reject) => {
  if (!window.google?.accounts?.oauth2) {
    reject(new Error('Google 로그인 준비 중입니다. 잠시 후 다시 눌러 주세요.'));
    return;
  }
  let done = false;
  const timer = setTimeout(() => finish(null), 120000);
  function finish(token) {
    if (done) return;
    done = true; clearTimeout(timer);
    token ? resolve(token) : reject(new Error('Google 연결을 완료하지 못했습니다. 다시 연결해 주세요.'));
  }
  const client = google.accounts.oauth2.initTokenClient({
    client_id: '99146066883-1ng3o05vjfhhaigm4mu357lemnt23ddg.apps.googleusercontent.com',
    scope: 'https://www.googleapis.com/auth/drive.file',
    include_granted_scopes: false,
    callback: response => finish(!response.error && google.accounts.oauth2.hasGrantedAllScopes(response, 'https://www.googleapis.com/auth/drive.file') ? response.access_token : null),
    error_callback: () => finish(null),
  });
  client.requestAccessToken({prompt: 'select_account'});
});
