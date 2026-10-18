// 실제 CY 진입점 → 원본 전체 UI → 새 주석·양식·본문 → 저장·독립 검사·리더 복귀.
const {chromium,webkit}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),os=require('node:os'),assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
(async()=>{
 const root=path.resolve(__dirname,'..'),assets=path.join(root,'macos_app/build/web');
 const temp=fs.mkdtempSync(path.join(os.tmpdir(),'cy-workbench-test-'));
 const types={'.js':'text/javascript; charset=utf-8','.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.wasm':'application/wasm','.json':'application/json'};
 const server=http.createServer((req,res)=>{const relative=decodeURIComponent(req.url.split('?')[0]).replace(/^\/CY_Viewer\//,'');const file=path.resolve(assets,relative||'index.html');if(!file.startsWith(assets+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404).end();return;}res.setHeader('content-type',types[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  const kind=process.env.CY_TEST_BROWSER==='webkit'?webkit:chromium;
  browser=await kind.launch(kind===chromium?{executablePath:process.env.CY_CHROME||'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']}:process.env.CY_WEBKIT?{executablePath:process.env.CY_WEBKIT}:{});
  const page=await browser.newPage({locale:'ko-KR',viewport:{width:1360,height:1000},hasTouch:true});page.setDefaultTimeout(120000);
  await page.goto(process.env.CY_WORKBENCH_URL||`http://127.0.0.1:${server.address().port}/CY_Viewer/`);
  await page.locator('input[type=file]').setInputFiles(path.join(root,'macos_app/test/fixtures/print-pages.pdf'));
  await page.locator('flt-semantics-placeholder').dispatchEvent('click');
  await page.getByRole('button',{name:'PDF 도구',exact:true}).click();
  await page.evaluate(()=>{window.cyWorkbenchTest=[];window.addEventListener('message',e=>{if(e.origin===location.origin&&e.data?.type?.startsWith('pdfcraft:'))window.cyWorkbenchTest.push({type:e.data.type,version:e.data.version});});});
  await page.getByRole('button',{name:'전체 PDF 작업실',exact:true}).click();
  await page.getByText('원본은 유지됩니다. 작업실에서 저장한 뒤 다운로드하거나 CY뷰어에서 열어 주세요.',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>window.cyWorkbenchTest.find(e=>e.type==='pdfcraft:ready')?.version),'0.9.0');
  const frame=page.frameLocator('.cy-workbench iframe'),canvas=frame.locator('canvas');
  await canvas.click({position:{x:600,y:350}});await page.waitForTimeout(1500);
  const modifier=await canvas.evaluate(()=>/(Mac|iPhone|iPad)/.test(navigator.userAgent)?'Meta':'Control');
  async function command(query){await canvas.press(modifier+'+k');await canvas.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));await page.keyboard.insertText(query);await page.waitForTimeout(250);await page.keyboard.press('Enter');await page.waitForTimeout(300);}
  await command('스티커 메모 추가');await canvas.click({position:{x:650,y:330}});await page.keyboard.insertText('한글 주석 저장 확인');await page.keyboard.press(modifier+'+Enter');await page.waitForTimeout(300);
  await command('텍스트 필드 추가');
  const box=await canvas.boundingBox();await page.mouse.move(box.x+450,box.y+480);await page.mouse.down();await page.waitForTimeout(150);await page.mouse.move(box.x+650,box.y+520,{steps:8});await page.waitForTimeout(150);await page.mouse.up();await page.waitForTimeout(500);
  await command('텍스트 추가');await canvas.click({position:{x:480,y:600}});await page.keyboard.type('CY ported body text');await canvas.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  // 원본 UI의 텍스트 완료(✓)를 눌러 본문 편집을 확정한다.
  await canvas.click({position:{x:684,y:612}});await page.waitForTimeout(300);
  await canvas.press(modifier+'+s');
  const link=page.getByRole('link',{name:'다운로드',exact:true});await link.waitFor();
  const pending=page.waitForEvent('download');await link.click();await(await pending).saveAs(path.join(temp,'full-workbench.pdf'));
  execFileSync(process.env.CY_TEST_PYTHON||'python3',['-c',`
import pymupdf,sys
with pymupdf.open(sys.argv[1]) as d:
 assert len(d)==4
 comments=[a.info.get('content') for p in d for a in p.annots() or []]
 assert '한글 주석 저장 확인' in comments, comments
 widgets=[w for p in d for w in p.widgets() or []]
 assert any(w.field_type_string=='Text' for w in widgets), [(w.field_name,w.field_type_string) for w in widgets]
 assert any('CY ported body text' in p.get_text() for p in d), [p.get_text() for p in d]
`,path.join(temp,'full-workbench.pdf')]);
  await page.screenshot({path:path.join(temp,'full-workbench.png')});
  if(process.env.CY_KOREAN_SCREENSHOTS){
   await command('환경설정');await page.screenshot({path:path.join(temp,'korean-preferences.png')});await canvas.press('Escape');
  }
  await page.setViewportSize({width:390,height:844});await page.waitForTimeout(500);
  const small=await canvas.boundingBox();assert(small.width<=390&&small.width>250);
  await page.screenshot({path:path.join(temp,'full-workbench-390.png')});
  await page.getByRole('button',{name:'CY뷰어에서 열기',exact:true}).tap();
  await page.locator('.cy-workbench').waitFor({state:'detached'});
  await page.getByRole('button',{name:'PDF 도구',exact:true}).waitFor();
  console.log(`${kind.name()} 전체 작업실: 한국어 도구 검색·한글 주석·양식 필드·본문 추가·다운로드·독립 PDF 검사·390px·리더 복귀 통과`);
 }catch(error){console.error(error);throw error;}finally{await browser?.close();server.close();if(process.env.CY_WORKBENCH_KEEP)console.log('검사 산출물:',temp);else fs.rmSync(temp,{recursive:true,force:true});}
})().catch(()=>{process.exit(1)});
