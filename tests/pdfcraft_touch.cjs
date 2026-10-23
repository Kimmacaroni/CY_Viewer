// 실제 iOS 홈 화면 실행은 실기기에서 별도로 확인한다.
// 여기서는 WebKit/Chrome 모바일 터치와 standalone 플래그 경로를 검사한다.
const {chromium,webkit}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
(async()=>{
 const assets=path.resolve(__dirname,'../macos_app/build/web');
 const server=http.createServer((req,res)=>{
  const file=path.resolve(assets,decodeURIComponent(req.url.split('?')[0]).replace(/^\/CY_Viewer\//,'')||'index.html');
  if(!file.startsWith(assets+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404).end();return;}
  res.setHeader('Content-Type',({'.js':'text/javascript','.wasm':'application/wasm','.html':'text/html','.json':'application/json','.css':'text/css'})[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  const kind=process.env.CY_TEST_BROWSER==='webkit'?webkit:chromium;
  browser=await kind.launch(kind===chromium?{executablePath:'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']}:process.env.CY_WEBKIT?{executablePath:process.env.CY_WEBKIT}:{});
  for(const standalone of [false,true]){
   const context=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true,locale:'ko-KR'});
   if(standalone)await context.addInitScript(()=>Object.defineProperty(navigator,'standalone',{get:()=>true}));
   const page=await context.newPage();page.setDefaultTimeout(60000);
   await page.goto(process.env.CY_TOUCH_URL||`http://127.0.0.1:${server.address().port}/CY_Viewer/`);
   const picker=page.locator('input[type=file]');await picker.waitFor({state:'visible'});
   // 합성 click 없이 파일 선택기가 실제 터치로 열리는지 확인한다.
   const chooser=page.waitForEvent('filechooser');await picker.tap();
   await (await chooser).setFiles(path.resolve(__dirname,'../macos_app/test/fixtures/print-pages.pdf'));
   await picker.waitFor({state:'detached'});
   // 접근성 트리로 렌더 완료를 기다린 뒤 실제 터치 이벤트를 보낸다.
   await page.locator('flt-semantics-placeholder').dispatchEvent('click');
   await page.getByRole('button',{name:'PDF 도구',exact:true}).tap();
   await page.getByRole('tab',{name:'페이지 편집',exact:true}).waitFor();
   await page.getByRole('tab',{name:'정보·책갈피',exact:true}).tap();
   await page.getByRole('textbox',{name:'제목',exact:true}).waitFor();
   const title=page.getByRole('textbox',{name:'제목',exact:true});
   await title.fill('듀오 화면 전환');
   for(const viewport of [{width:890,height:626},{width:466,height:678},{width:678,height:466},{width:390,height:844}]){
    await page.setViewportSize(viewport);
    await page.waitForTimeout(150);
    assert.equal(await title.inputValue(),'듀오 화면 전환');
    assert.equal(await page.getByRole('tab',{name:'정보·책갈피',exact:true}).getAttribute('aria-selected'),'true');
   }

   await page.getByRole('button',{name:'닫기',exact:true}).tap();
   await page.getByRole('button',{name:'PDF 도구',exact:true}).tap();
   await page.getByRole('tab',{name:'페이지 편집',exact:true}).waitFor();
   const main=await page.locator('script[src*="main.dart.js"]').getAttribute('src');
   const boot=await page.locator('script[src*="flutter_bootstrap.js"]').getAttribute('src');
   assert.equal(new URL(main,page.url()).searchParams.get('release'),new URL(boot,page.url()).searchParams.get('release'));
   console.log(`${kind.name()} standalone=${standalone}: 파일 선택·도구 열기·탭 전환·닫기·재열기 터치 및 캐시 버전 일치`);
   await context.close();
  }
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1)});
