// 빌드된 웹앱에서 파일 추가·편집·다운로드·결과 열기를 직접 실행한다.
const {chromium,webkit}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),os=require('node:os'),assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
(async()=>{
 const root=path.resolve(__dirname,'..'),assets=path.join(root,'macos_app/build/web'),fixture=path.join(root,'macos_app/test/fixtures/print-pages.pdf');
 const temp=fs.mkdtempSync(path.join(os.tmpdir(),'cy-pdf-ui-')),python=process.env.CY_TEST_PYTHON||'python3';
 const types={'.js':'text/javascript','.wasm':'application/wasm','.html':'text/html','.json':'application/json','.css':'text/css','.png':'image/png'};
 const server=http.createServer((req,res)=>{const relative=decodeURIComponent(req.url.split('?')[0]).replace(/^\/CY_Viewer\//,'');const file=path.resolve(assets,relative||'index.html');if(!file.startsWith(assets+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}res.setHeader('content-type',types[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  const kind=process.env.CY_TEST_BROWSER==='webkit'?webkit:chromium;
  browser=await kind.launch(kind===chromium?{executablePath:process.env.CY_CHROME||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']}:process.env.CY_WEBKIT?{executablePath:process.env.CY_WEBKIT}:{});
  const page=await browser.newPage({locale:'ko-KR',viewport:{width:1000,height:850}});page.setDefaultTimeout(Number(process.env.CY_UI_TIMEOUT||40000));
  await page.goto(`http://127.0.0.1:${server.address().port}/CY_Viewer/`);
  await page.locator('input[type=file]').waitFor({state:'attached'});await page.locator('input[type=file]').setInputFiles(fixture);
  await page.locator('flt-semantics-placeholder').waitFor();await page.locator('flt-semantics-placeholder').dispatchEvent('click');
  const tools=page.getByRole('button',{name:'PDF 도구',exact:true});await tools.click();
  await page.getByRole('tab',{name:'페이지 편집',exact:true}).waitFor();
  let lastDownloadUrl=null;
  async function prepare(name){await page.getByRole('button',{name:'파일 준비',exact:true}).click();const link=page.getByRole('link',{name:'다운로드',exact:true});try{await page.waitForFunction(previous=>{const link=document.querySelector('a[download]');return link&&link.href!==previous;},lastDownloadUrl);await link.waitFor();lastDownloadUrl=await link.getAttribute('href');}catch(error){console.log('준비 오류 상태:',(await page.locator('body').innerText()).replaceAll('ui-secret','[시험 암호]'));await page.screenshot({path:'/tmp/cy-pdfcraft-ui-error.png'});throw error;}const pending=page.waitForEvent('download');await link.click();const download=await pending;await download.saveAs(path.join(temp,name));console.log(name+' 다운로드 확인');}
  async function field(label,value){const node=page.getByRole('textbox',{name:label,exact:true});await node.click();await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));await node.fill(value);await page.evaluate(()=>new Promise(requestAnimationFrame));}
  await page.getByRole('checkbox').first().click();await page.getByRole('button',{name:'오른쪽 회전',exact:true}).click();await prepare('rotated.pdf');
  await page.getByRole('tab',{name:'정보·책갈피',exact:true}).click();await field('제목','browser-title');
  await page.getByRole('button',{name:'책갈피 추가',exact:true}).scrollIntoViewIfNeeded();await page.getByRole('button',{name:'책갈피 추가',exact:true}).click();
  await field('책갈피 이름','browser-bookmark');await field('원본 쪽','2');await prepare('metadata.pdf');
  await page.getByRole('tab',{name:'합치기·분할',exact:true}).click();await page.locator('input[type=file][aria-label="합칠 PDF 추가"]').setInputFiles(fixture);
  await page.getByRole('button',{name:'선택 제거',exact:true}).waitFor();
  await prepare('merged.pdf');await page.getByRole('switch',{name:/PDF 분할/}).click();await prepare('split.zip');
  await page.getByRole('switch',{name:/PDF 분할/}).click();await page.getByRole('tab',{name:'보안',exact:true}).click();
  await page.getByRole('button',{name:/암호 변경 안 함/}).click();await page.getByLabel('새 암호 설정',{exact:true}).last().click();
  await field('새 암호','ui-secret');await field('새 암호 확인','ui-secret');await prepare('encrypted.pdf');
  execFileSync(python,['-c',`
import pymupdf,sys,zipfile
from pathlib import Path
p=Path(sys.argv[1])
with pymupdf.open(p/'rotated.pdf') as d: assert len(d)==4 and d[0].rotation==90
with pymupdf.open(p/'metadata.pdf') as d: assert d.metadata['title']=='browser-title' and any(row[1]=='browser-bookmark' and row[2]==2 for row in d.get_toc())
with pymupdf.open(p/'merged.pdf') as d:
 assert len(d)==8 and d[0].rotation==90 and d[4].rotation==0, (len(d), [page.rotation for page in d])
with zipfile.ZipFile(p/'split.zip') as z:
 assert len(z.namelist())==8
 for name in z.namelist():
  with pymupdf.open(stream=z.read(name),filetype='pdf') as d: assert len(d)==1
with pymupdf.open(p/'encrypted.pdf') as d: assert d.needs_pass and d.authenticate('ui-secret') and len(d)==8
`,temp]);
  await page.getByRole('button',{name:'결과 열기',exact:true}).click();await page.getByRole('textbox',{name:'현재 PDF 암호',exact:true}).waitFor();
  await field('현재 PDF 암호','wrong');await page.getByRole('button',{name:'문서 열기',exact:true}).click();await page.waitForFunction(()=>document.body.innerText.includes('현재 암호가 올바르지 않습니다.')); 
  await field('현재 PDF 암호','ui-secret');await page.getByRole('button',{name:'문서 열기',exact:true}).click();
  try {await page.waitForFunction(()=>document.body.innerText.includes('1 / 8')||Array.from(document.querySelectorAll('[aria-label]')).some(e=>e.getAttribute('aria-label')==='1 / 8'));}catch(error){console.log('결과 열기 상태:',await page.locator('body').innerText());await page.screenshot({path:'/tmp/cy-pdfcraft-ui-open-error.png'});throw error;}
  await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'PDF 도구',exact:true}).click();await page.getByRole('tab',{name:'보안',exact:true}).click();
  assert(await page.getByRole('button',{name:'파일 준비',exact:true}).isVisible());

  console.log(`${process.env.CY_TEST_BROWSER||'chromium'} 웹 PDF 도구: 회전·정보·책갈피·추가 PDF·분할 ZIP·암호 다운로드·결과 재입력·390px 검사 통과`);
 }finally{if(browser)await browser.close();server.close();if(!process.env.CY_UI_KEEP_FILES)fs.rmSync(temp,{recursive:true,force:true});else console.log(temp);}
})().catch(error=>{console.error(error);process.exit(1)});
