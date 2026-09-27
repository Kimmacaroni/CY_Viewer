const {test}=require('node:test');
const assert=require('node:assert/strict');
const {platform,latest}=require('../site/download/downloads.js');
test('Windows와 Mac 감지 및 iPad 데스크톱 UA 구분',()=>{
  assert.equal(platform({userAgent:'Mozilla Windows NT 10.0'}),'windows');
  assert.equal(platform({userAgent:'Macintosh',platform:'MacIntel',maxTouchPoints:0}),'mac');
  assert.equal(platform({userAgent:'Macintosh',platform:'MacIntel',maxTouchPoints:5}),'web');
  for(const ua of ['iPhone','Android','Linux','']) assert.equal(platform({userAgent:ua}),'web');
});
function release(version){const tag='macos-v'+version; const name=`CYViewer-macOS-v${version}.dmg`;return {tag_name:tag,draft:false,prerelease:false,assets:[{name,size:100,browser_download_url:`https://github.com/Kimmacaroni/CY_Viewer/releases/download/${tag}/${name}`}]};}
test('문자열 순서가 아닌 버전 순서, 미완성·시험 릴리스 제외',()=>{
  const incomplete=release('99.0.0');incomplete.assets=[];
  assert.equal(latest([release('1.9.0'),release('1.10.0'),{...release('2.0.0'),prerelease:true},incomplete],'mac').version,'1.10.0');
});
test('외부 다운로드 주소와 초안은 추천하지 않음',()=>{
  const bad=release('3.0.0');bad.assets[0].browser_download_url='https://example.com/fake.dmg';
  assert.equal(latest([bad,{...release('4.0.0'),draft:true}],'mac'),null);
});

const {resolveLanguage} = require('../site/download/language.js');
test('한국어 기기 언어, 영어 대체, 수동 선택', () => {
  assert.equal(resolveLanguage('system', ['ko-KR']), 'ko');
  assert.equal(resolveLanguage('system', ['ja-JP']), 'en');
  assert.equal(resolveLanguage('ko', ['en-US']), 'ko');
  assert.equal(resolveLanguage('en', ['ko-KR']), 'en');
});
