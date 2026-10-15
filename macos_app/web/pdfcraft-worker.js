// 창과 분리된 작업자에서 PdfCraft WASM을 실행한다.
self.onmessage = async ({ data }) => {
  try {
    importScripts('pdfcraft/cy_pdfcraft.js?engine=0.4.0');
    await wasm_bindgen({ module_or_path: 'pdfcraft/cy_pdfcraft_bg.wasm?engine=0.4.0' });
    const result = wasm_bindgen.process_pdf(data.request, data.sources);
    self.postMessage({ result }, result.files.map(bytes => bytes.buffer));
  } catch (error) {
    self.postMessage({ error: typeof error === 'string' ? error : 'PDF 처리 중 오류가 발생했습니다. 원본은 변경하지 않았습니다.' });
  }
};
