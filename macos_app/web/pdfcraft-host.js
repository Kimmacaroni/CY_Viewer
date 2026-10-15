// PdfCraft를 별도 작업자에서 실행한다. 문서 바이트는 서버로 전송하지 않는다.
globalThis.cyPdfcraftRun = (request, sources) => new Promise((resolve, reject) => {
  const worker = new Worker(new URL('pdfcraft-worker.js?engine=0.4.0', document.baseURI));
  let finished = false;
  const finish = (error, value) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    worker.terminate();
    if (error) resolve({ error }); else resolve(value);
  };
  const timer = setTimeout(() => finish('PDF 처리 시간이 초과됐습니다. 원본은 변경하지 않았습니다.'), 180000);
  worker.onerror = () => finish('PDF 처리 모듈을 불러오지 못했습니다. 연결을 확인하고 다시 시도하세요.');
  worker.onmessage = ({ data }) => finish(data.error, data.result);
  // 원본의 ArrayBuffer를 분리하지 않고 작업용 사본만 전달한다.
  const copies = sources.map(source => Uint8Array.from(source));
  worker.postMessage({ request, sources: copies }, copies.map(bytes => bytes.buffer));
});
