// CSS 안전 영역을 주입해 시스템 상태 영역이 있는 화면을 검사한다. 실기기 검증과 구분한다.
const {chromium,webkit}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
(async()=>{
 const assets=path.resolve(__dirname,'../macos_app/build/web');
 const server=http.createServer((req,res)=>{
  const file=path.resolve(assets,decodeURIComponent(req.url.split('?')[0]).replace(/^\/CY_Viewer\//,'')||'index.html');
  if(!file.startsWith(assets+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404).end();return;}
  res.setHeader('content-type',({'.js':'text/javascript','.html':'text/html','.css':'text/css','.json':'application/json','.wasm':'application/wasm'})[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  const kind=process.env.CY_TEST_BROWSER==='webkit'?webkit:chromium;
  browser=await kind.launch(kind===chromium?{executablePath:'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']}:process.env.CY_WEBKIT?{executablePath:process.env.CY_WEBKIT}:{});
  for(const dark of [false,true]){
   const page=await browser.newPage({viewport:{width:1280,height:900},hasTouch:true,isMobile:true,locale:'ko-KR',colorScheme:dark?'dark':'light'});page.setDefaultTimeout(60000);
   await page.addInitScript(()=>Object.defineProperty(navigator,'standalone',{get:()=>true}));
   await page.goto(process.env.CY_SAFE_URL||`http://127.0.0.1:${server.address().port}/CY_Viewer/`);
   const picker=page.locator('input[type=file]');await picker.waitFor({state:'visible'});
   async function safe(top,right,bottom,left){
    await page.evaluate(({top,right,bottom,left})=>{for(const [k,v] of Object.entries({top,right,bottom,left}))document.documentElement.style.setProperty('--cy-safe-'+k,v+'px');},{top,right,bottom,left});
    await page.waitForTimeout(500);
   }
   async function inside(locator,region){const r=await locator.boundingBox();assert(r, '메뉴가 표시되어야 한다');assert(r.x>=region.left-1&&r.y>=region.top-1&&r.x+r.width<=region.width-region.right+1&&r.y+r.height<=region.height-region.bottom+1,JSON.stringify({r,region}));}
   await safe(30,112,24,16);
   await page.locator('flt-semantics-placeholder').dispatchEvent('click');
   await inside(page.getByRole('button',{name:'설치 방법',exact:true}),{top:30,right:112,bottom:24,left:16,width:1280,height:900});
   if(process.env.CY_SAFE_SCREENSHOT_DIR){fs.mkdirSync(process.env.CY_SAFE_SCREENSHOT_DIR,{recursive:true});await page.screenshot({path:path.join(process.env.CY_SAFE_SCREENSHOT_DIR,kind.name()+'-'+(dark?'dark':'light')+'-library.png')});}
   await inside(picker,{top:30,right:112,bottom:24,left:16,width:1280,height:900});
   // 기본 HTML 파일 입력의 터치 위치도 이동한 Flutter 위치와 일치해야 한다.
   const chooser=page.waitForEvent('filechooser');await picker.tap();await(await chooser).setFiles(path.resolve(__dirname,'../macos_app/test/fixtures/print-pages.pdf'));
   await picker.waitFor({state:'detached'});
   const tools=page.getByRole('button',{name:'PDF 도구',exact:true});await tools.waitFor();
   await inside(tools,{top:30,right:112,bottom:24,left:16,width:1280,height:900});await tools.tap();
   const close=page.getByRole('button',{name:'닫기',exact:true});await close.waitFor();
   await inside(close,{top:30,right:112,bottom:24,left:16,width:1280,height:900});
   await page.getByRole('tab',{name:'정보·책갈피',exact:true}).tap();
   await page.setViewportSize({width:466,height:678});await safe(48,0,34,0);
   await inside(close,{top:48,right:0,bottom:34,left:0,width:466,height:678});
   assert.equal(await page.getByRole('tab',{name:'정보·책갈피',exact:true}).getAttribute('aria-selected'),'true');
   await close.tap();await tools.waitFor();await inside(tools,{top:48,right:0,bottom:34,left:0,width:466,height:678});
   console.log(`${kind.name()} ${dark?'어두움':'밝음'}: 상태 영역·기본 파일 입력 터치·리더 메뉴·대화상자·회전 검사 통과`);
   await page.close();
  }
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1)});
