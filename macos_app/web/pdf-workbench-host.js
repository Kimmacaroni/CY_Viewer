/* 원본의 전체 편집 UI와 CY뷰어 간 동일 출처 메모리 연결. PDF를 업로드하지 않는다. */
(() => {
  'use strict';
  let opened = false;
  window.cyOpenPdfWorkbench = (name, bytes) => new Promise((resolve, reject) => {
    if (opened) { reject(new Error('PDF 작업실이 이미 열려 있습니다.')); return; }
    if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length > 256 * 1024 * 1024) {
      reject(new Error('PDF 작업실에서는 256MB 이하 PDF를 열 수 있습니다.')); return;
    }
    opened = true;
    const previous = document.activeElement;
    const panel = document.createElement('section'); panel.className = 'cy-workbench';
    panel.setAttribute('role', 'dialog');panel.setAttribute('aria-modal', 'true');panel.setAttribute('aria-label', 'PDF 작업실');
    const toolbar=document.createElement('header'), title=document.createElement('strong'), close=document.createElement('button');
    title.textContent='PDF 작업실 · PdfCraft';close.textContent='닫기';close.type='button';toolbar.append(title,close);
    const note=document.createElement('p');note.className='cy-workbench-status';note.setAttribute('role','status');note.textContent='문서 사본을 준비하고 있습니다…';
    const actions=document.createElement('div');actions.className='cy-workbench-actions';
    const download=document.createElement('a');download.textContent='다운로드';download.hidden=true;
    const result=document.createElement('button');result.type='button';result.textContent='CY뷰어에서 열기';result.hidden=true;actions.append(download,result);
    const frame=document.createElement('iframe');frame.title='PDF 전체 편집 작업실';frame.src=new URL('pdf-workbench/index.html?host=parent',document.baseURI).href;
    panel.append(toolbar,note,actions,frame);
    const hidden=[...document.body.children].filter(e=>!['SCRIPT','STYLE'].includes(e.tagName)).map(e=>[e,e.inert]);
    for(const [element] of hidden)element.inert=true;
    let dirty=false,saved=null,url=null,downloaded=false,ready=false;
    function dispose(value){
      if((dirty||(saved&&!downloaded&&!value))&&!window.confirm('저장하지 않은 작업이 있습니다. PDF 작업실을 닫을까요?'))return;
      clearTimeout(timer);window.removeEventListener('message',receive);window.removeEventListener('beforeunload',unload);panel.remove();for(const [element,inert] of hidden)element.inert=inert;if(url)URL.revokeObjectURL(url);opened=false;previous?.focus();resolve(value);
    }
    function unload(e){if(dirty||(saved&&!downloaded)){e.preventDefault();e.returnValue='';}}
    close.addEventListener('click',()=>dispose(null));
    result.addEventListener('click',()=>dispose({bytes:saved}));
    download.addEventListener('click',()=>{downloaded=true;note.textContent='다운로드를 요청했습니다. 브라우저의 다운로드 목록을 확인하세요.';});
    function receive(e){
      if(e.origin!==location.origin||e.source!==frame.contentWindow||!e.data||typeof e.data!=='object')return;
      if(e.data.type==='pdfcraft:ready'&&!ready){ready=true;clearTimeout(timer);const copy=bytes.slice();frame.contentWindow.postMessage({type:'pdfcraft:open',name:String(name).slice(0,200),bytes:copy.buffer},location.origin,[copy.buffer]);note.textContent='원본은 유지됩니다. 작업실에서 저장한 뒤 다운로드하거나 CY뷰어에서 열어 주세요.';}
      if(e.data.type==='pdfcraft:dirty')dirty=e.data.dirty===true;
      if(e.data.type==='pdfcraft:failed'){clearTimeout(timer);note.textContent='PDF 작업실을 시작하지 못했습니다. 닫은 뒤 다시 시도해 주세요.';}
      if(e.data.type==='pdfcraft:save'){
        const data=e.data.bytes;
        if(!(data instanceof ArrayBuffer)||data.byteLength<5||data.byteLength>512*1024*1024)return;
        const copy=new Uint8Array(data);if(String.fromCharCode(...copy.subarray(0,5))!=='%PDF-')return;
        if(url)URL.revokeObjectURL(url);saved=copy;downloaded=false;url=URL.createObjectURL(new Blob([copy],{type:'application/pdf'}));
        download.href=url;download.download=String(e.data.name||'edited.pdf').replace(/[\\/\u0000-\u001f]/g,'_').slice(0,200);download.hidden=false;result.hidden=false;
        note.textContent='편집 결과가 준비됐습니다. 다운로드 버튼을 눌러 파일로 저장하세요.';
      }
    }
    const timer=setTimeout(()=>{if(!ready)note.textContent='PDF 작업실을 불러오는 데 시간이 걸립니다. 인터넷 연결을 확인하거나 닫은 뒤 다시 시도해 주세요.';},90000);
    window.addEventListener('message',receive);window.addEventListener('beforeunload',unload);document.body.append(panel);close.focus();
  });
})();
