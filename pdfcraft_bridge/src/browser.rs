//! Web Worker 전용 메모리 입출력. 문서 바이트를 서버로 보내지 않는다.
use super::{Storage, process_json};
use js_sys::{Array, Object, Reflect, Uint8Array};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};
use wasm_bindgen::prelude::*;
struct MemoryStorage {
    inputs: BTreeMap<PathBuf, Vec<u8>>,
    outputs: BTreeMap<PathBuf, Vec<u8>>,
}
impl Storage for MemoryStorage {
    fn read(&mut self, path: &Path, _: u64) -> Result<Vec<u8>, String> {
        self.inputs
            .get_mut(path)
            .map(std::mem::take)
            .ok_or("입력 PDF가 없습니다.".into())
    }
    fn exists(&self, path: &Path) -> bool {
        self.inputs.contains_key(path) || self.outputs.contains_key(path)
    }
    fn write_new(&mut self, path: &Path, bytes: &[u8]) -> Result<(), String> {
        if self.exists(path) {
            return Err("저장할 임시 파일이 이미 있습니다.".into());
        }
        self.outputs.insert(path.into(), bytes.to_vec());
        Ok(())
    }
}
#[wasm_bindgen]
pub fn process_pdf(request: &str, sources: Array) -> Result<JsValue, JsValue> {
    let mut storage = MemoryStorage {
        inputs: BTreeMap::new(),
        outputs: BTreeMap::new(),
    };
    if sources.length() == 0 || sources.length() > 20 {
        return Err(JsValue::from_str("PDF는 1개부터 20개까지 선택하세요."));
    }
    let mut total: u64 = 0;
    for (i, source) in sources.iter().enumerate() {
        let bytes = source
            .dyn_into::<Uint8Array>()
            .map_err(|_| JsValue::from_str("PDF 입력 형식이 올바르지 않습니다."))?;
        total += u64::from(bytes.length());
        if bytes.length() > 256 * 1024 * 1024 || total > 512 * 1024 * 1024 {
            return Err(JsValue::from_str(
                "한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.",
            ));
        }
        storage
            .inputs
            .insert(format!("source-{i}.pdf").into(), bytes.to_vec());
    }
    let report = process_json(request, &mut storage).map_err(|e| JsValue::from_str(&e))?;
    let object = Object::new();
    Reflect::set(
        &object,
        &"report".into(),
        &js_sys::JSON::parse(&report.to_string())?,
    )?;
    let files = Array::new();
    if let Some(outputs) = report["files"].as_array() {
        for output in outputs {
            let key = PathBuf::from(output["path"].as_str().ok_or("결과 파일 경로 오류")?);
            let bytes = storage.outputs.remove(&key).ok_or("결과 PDF가 없습니다.")?;
            files.push(&Uint8Array::from(bytes.as_slice()));
        }
    }
    Reflect::set(&object, &"files".into(), &files)?;
    Ok(object.into())
}
