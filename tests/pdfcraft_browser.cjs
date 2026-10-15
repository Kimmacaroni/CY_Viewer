// 실제 브라우저 작업자와 독립 PDF 엔진을 함께 검사한다.
const {chromium,webkit}=require('playwright');
const fs=require('node:fs');const path=require('node:path');const os=require('node:os');const http=require('node:http');const {execFileSync}=require('node:child_process');const assert=require('node:assert/strict');
(async()=>{
 const root=path.resolve(__dirname,'..'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'cy-wasm-'));
 const python=process.env.CY_TEST_PYTHON||'python3';
 execFileSync(python,[path.join(__dirname,'pdfcraft_browser_verify.py'),'prepare',dir]);
 const assets=path.join(root,'macos_app','web');const methods=[];
 const server=http.createServer((req,res)=>{methods.push(req.method);if(req.url==='/'){res.setHeader('content-type','text/html');res.end('<script src="pdfcraft-host.js"></script>');return;}
 const file=path.resolve(assets,decodeURIComponent(req.url.split('?')[0]).slice(1));if(!file.startsWith(assets+path.sep)||!fs.existsSync(file)){res.writeHead(404);res.end();return;}
 res.setHeader('content-type',file.endsWith('.wasm')?'application/wasm':file.endsWith('.js')?'text/javascript':'text/plain');fs.createReadStream(file).pipe(res);});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 let browser;
 try{
 const engine=process.env.CY_TEST_BROWSER==='webkit'?webkit:chromium;
 browser=await engine.launch(engine===chromium?{executablePath:process.env.CY_CHROME||'/usr/bin/google-chrome',args:['--no-sandbox']}:process.env.CY_WEBKIT?{executablePath:process.env.CY_WEBKIT}:{});
 const page=await browser.newPage();await page.goto(`http://127.0.0.1:${server.address().port}/`);
 const inputs=Object.fromEntries(['source','added','restricted','signed','scaled'].map(name=>[name,fs.readFileSync(path.join(dir,name+'.pdf')).toString('base64')]));
 const result=await page.evaluate(async inputs=>{
  const decode=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0)), source=decode(inputs.source), before=Array.from(source);
  const run=(options={},password,bytes=source,extra=[])=>cyPdfcraftRun(JSON.stringify({...options,sources:[bytes,...extra].map((_,i)=>({path:`source-${i}.pdf`,title:'문서',password:i===0?password:null})),output:'result.pdf'}),[bytes,...extra]);
  const info=(await run({inspect:true})).report;if(info.pages!==4||info.encrypted)throw Error('문서 검사 오류');
  const edited=(await run({page_plan:[{index:3,rotation:90},{index:null},{index:0}]})).files[0];
  const metadata=(await run({metadata:{Title:'브라우저 제목',Author:'작성자'},bookmarks:[{action:'update',path:[0],title:'바꾼 이름',page:2},{action:'add',title:'마지막',page:4}]})).files[0];
  const merged=(await run({page_plan:[{index:2},{index:0}]},null,source,[decode(inputs.added)])).files[0];
  const parts=(await run({split_every:3})).files;
  const encrypted=(await run({new_password:'웹-암호'})).files[0];
  const changed=(await run({new_password:'changed'},'웹-암호',encrypted)).files[0];
  const removed=(await run({remove_password:true},'changed',changed)).files[0];
  const encryptedParts=(await run({split_every:2,new_password:'parts'},'웹-암호',encrypted)).files;
  const finished=(await run({finishing:{watermark:'DRAFT',header:'CY VIEWER',page_numbers:true,crop_mm:[2,3,4,5],background:[1,1,0.85],optimize:true}})).files[0];
  const scaled=(await run({finishing:{crop_mm:[2,3,4,5]}},null,decode(inputs.scaled))).files[0];
  const restored=(await run({finishing:{remove_marks:true,reset_crop:true}},null,finished)).files[0];
  const rejected=async action=>{let failed=false;try{const result=await action();failed=!!result.error;}catch(_){failed=true;}if(!failed)throw Error('잘못된 작업 허용');};
  await rejected(()=>run({remove_password:true},'wrong',encrypted));
  await rejected(()=>run({remove_password:true},'reader',decode(inputs.restricted)));
  await rejected(()=>run({},null,decode(inputs.signed)));
  for(const options of [{page_plan:[]},{page_plan:[{index:0},{index:0}]},{split_every:0},{finishing:{watermark:'한글'}},{finishing:{crop_mm:[100,100,100,100]}}])await rejected(()=>run(options));
  if(JSON.stringify(before)!==JSON.stringify(Array.from(source)))throw Error('원본 변경');
  return{scaled:Array.from(scaled),finished:Array.from(finished),restored:Array.from(restored),edited:Array.from(edited),metadata:Array.from(metadata),merged:Array.from(merged),parts:parts.map(p=>Array.from(p)),encrypted:Array.from(encrypted),changed:Array.from(changed),removed:Array.from(removed),encryptedParts:encryptedParts.map(p=>Array.from(p))};
 },inputs);
 fs.writeFileSync(path.join(dir,'results.json'),JSON.stringify(result));
 assert(methods.every(method=>method==='GET'),'문서 업로드 요청이 발생했습니다.');
 process.stdout.write(execFileSync(python,[path.join(__dirname,'pdfcraft_browser_verify.py'),'verify',dir]));
 }finally{if(browser)await browser.close();server.close();fs.rmSync(dir,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exit(1)});
