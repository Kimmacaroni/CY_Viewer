// Safari 표시 영역 API를 제어해 키보드/이동 시 호스트 배치를 검사한다. 실기기 에뮬레이터는 아니다.
const {chromium,webkit}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
(async()=>{
 const root=path.resolve(__dirname,'../macos_app/web');
 const server=http.createServer((req,res)=>{
  const name=req.url.split('?')[0];
  res.setHeader('content-type','text/html; charset=utf-8');
  if(name==='/')res.end('<link rel="stylesheet" href="pdf-picker.css"><script src="pdf-workbench-host.js"></script>');
  else if(name==='/pdf-workbench/index.html')res.end('<script>parent.postMessage({type:"pdfcraft:ready"},location.origin)</script>');
  else if(['/pdf-picker.css','/pdf-workbench-host.js'].includes(name)){
   res.setHeader('content-type',name.endsWith('.js')?'text/javascript':'text/css');res.end(fs.readFileSync(path.join(root,name)));
  }else res.writeHead(404).end();
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try{
  const kind=process.env.CY_TEST_BROWSER==='webkit'?webkit:chromium;
  browser=await kind.launch(kind===chromium?{executablePath:'/usr/bin/google-chrome',args:['--no-sandbox','--disable-dev-shm-usage']}:process.env.CY_WEBKIT?{executablePath:process.env.CY_WEBKIT}:{});
  const page=await browser.newPage({viewport:{width:900,height:700},hasTouch:true});
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  for(const supported of [true,false]){
   await page.evaluate(supported=>{
    const viewport=Object.assign(new EventTarget(),{width:900,height:700,offsetLeft:0,offsetTop:0});
    Object.defineProperty(window,'visualViewport',{configurable:true,value:supported?viewport:null});
    window.testViewport=viewport;
    window.cyOpenPdfWorkbench('test.pdf',new Uint8Array([37,80,68,70,45]));
   },supported);
   await page.getByText('원본은 유지됩니다. 작업실에서 저장한 뒤 다운로드하거나 CY뷰어에서 열어 주세요.',{exact:true}).waitFor();
   const frame=await page.locator('iframe').elementHandle();
   if(supported){
    for(const region of [{width:466,height:360,offsetLeft:0,offsetTop:120},{width:800,height:480,offsetLeft:16,offsetTop:24}]){
     await page.evaluate(region=>{Object.assign(window.testViewport,region);window.testViewport.dispatchEvent(new Event('resize'));window.testViewport.dispatchEvent(new Event('scroll'));},region);
     await page.waitForFunction(region=>{
      const r=document.querySelector('.cy-workbench').getBoundingClientRect();return r.width===region.width&&r.height===region.height&&r.x===region.offsetLeft&&r.y===region.offsetTop;
     },region);
     assert(await frame.evaluate(node=>node===document.querySelector('iframe')));
    }
   }else{
    const b=await page.locator('.cy-workbench').boundingBox();assert.equal(b.width,900);assert.equal(b.height,700);
   }
   await page.getByRole('button',{name:'닫기',exact:true}).tap();
   await page.locator('.cy-workbench').waitFor({state:'detached'});
   // 닫은 뒤 이벤트가 발생해도 창이 다시 나타나지 않는다.
   await page.evaluate(()=>{window.testViewport.dispatchEvent(new Event('resize'));window.dispatchEvent(new Event('resize'));});
   assert.equal(await page.locator('.cy-workbench').count(),0);
  }
  console.log(`${kind.name()}: 표시 영역 크기·오프셋·창 크기 대체·편집 창 유지·닫기 통과`);
 }finally{await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exit(1)});
