/* 공개된 정식 릴리스만 선택한다. 기기 감지가 실패해도 모든 다운로드는 남긴다. */
(function (root) {
  const repo = 'https://github.com/Kimmacaroni/CY_Viewer';
  function platform(nav) {
    const ua = nav.userAgent || '';
    if (/iPad|iPhone|iPod|Android/i.test(ua) || (nav.platform === 'MacIntel' && nav.maxTouchPoints > 1)) return 'web';
    if (/Windows/i.test(ua)) return 'windows';
    if (/Mac/i.test(nav.platform || ua)) return 'mac';
    return 'web';
  }
  function latest(releases, kind) {
    const prefix = kind === 'mac' ? 'macos' : 'windows';
    return releases.filter(r => !r.draft && !r.prerelease && new RegExp('^' + prefix + '-v\\d+\\.\\d+\\.\\d+$').test(r.tag_name))
      .sort((a,b) => {
        const av=a.tag_name.split('-v')[1].split('.').map(Number), bv=b.tag_name.split('-v')[1].split('.').map(Number);
        return bv[0]-av[0] || bv[1]-av[1] || bv[2]-av[2];
      }).map(r => {
        const version=r.tag_name.split('-v')[1];
        const name=kind==='mac' ? `CYViewer-macOS-v${version}.dmg` : `CYViewer-Setup-v${version}.exe`;
        const url=`${repo}/releases/download/${r.tag_name}/${name}`;
        const asset=(r.assets || []).find(a => a.name===name && a.browser_download_url===url && a.size>0);
        return asset ? {version,url,notes:`${repo}/releases/tag/${r.tag_name}`} : null;
      }).find(Boolean) || null;
  }
  const api={platform,latest};
  if (typeof module !== 'undefined') module.exports=api;
  root.CyDownloads=api;
  if (typeof document === 'undefined') return;
  const t = root.CyLanguage ? root.CyLanguage.t : (s,...args) => s.replace(/\{(\d+)\}/g, (_,i) => args[i]);
  let statusMessage = '아래에서 기기에 맞는 버전을 선택하세요.';
  const device=platform(navigator), names={mac:'Mac',windows:'Windows'};
  function recommend() {
    if (device==='web') return;
    document.getElementById('device-label').textContent=t('이 기기에 추천 · {0}', names[device]);
    const source=document.getElementById(`${device}-download`), primary=document.getElementById('primary-download');
    primary.href=source.href; primary.textContent=t('{0}용 CY뷰어 다운로드 ↓', names[device]);
    document.getElementById('primary-detail').textContent=document.getElementById(`${device}-version`).textContent;
  }
  root.addEventListener('cylanguagechange', () => { recommend(); document.getElementById('release-status').textContent=t(statusMessage); });
  recommend();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  fetch('https://api.github.com/repos/Kimmacaroni/CY_Viewer/releases?per_page=100', {signal:controller.signal})
    .then(r => {if(!r.ok) throw Error('releases'); return r.json();})
    .then(releases => {
      if(!Array.isArray(releases)) throw Error('releases');
      let found=0;
      for(const kind of ['mac','windows']) {
        const release=latest(releases,kind); if(!release) continue;
        document.getElementById(`${kind}-download`).href=release.url;
        document.getElementById(`${kind}-notes`).href=release.notes;
        document.getElementById(`${kind}-version`).textContent=`v${release.version} · ${kind==='mac'?'DMG':'EXE'}`;
        found++;
      }
      if(found!==2) throw Error('incomplete');
      recommend(); statusMessage='공개된 최신 정식 버전을 확인했습니다.'; document.getElementById('release-status').textContent=t(statusMessage);
    }).catch(() => {
      recommend(); statusMessage='최신 버전을 확인하지 못했습니다. 아래 배포본을 받거나 모든 릴리스에서 확인해 주세요.'; document.getElementById('release-status').textContent=t(statusMessage);
    }).finally(() => clearTimeout(timeout));
})(globalThis);
