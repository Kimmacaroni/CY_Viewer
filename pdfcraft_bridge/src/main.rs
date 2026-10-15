//! 설치형 앱의 표준 입력과 파일 저장 경로.
use cy_pdfcraft::Storage;
use serde_json::Value;
use std::{
    fs,
    io::{self, Read, Write},
    path::Path,
};
struct DiskStorage;
impl Storage for DiskStorage {
    fn read(&mut self, path: &Path, limit: u64) -> Result<Vec<u8>, String> {
        let mut bytes = Vec::new();
        fs::File::open(path)
            .map_err(|e| format!("PDF를 읽을 수 없습니다: {e}"))?
            .take(limit)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        Ok(bytes)
    }
    fn exists(&self, path: &Path) -> bool {
        path.exists()
    }
    fn write_new(&mut self, path: &Path, bytes: &[u8]) -> Result<(), String> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|e| e.to_string())?;
        if let Err(e) = file.write_all(bytes).and_then(|_| file.sync_all()) {
            drop(file);
            let _ = fs::remove_file(path);
            return Err(e.to_string());
        }
        Ok(())
    }
}
fn main() {
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("cy-pdfcraft 0.4.0 (PdfCraft d9607ec3)");
        return;
    }
    let result = std::panic::catch_unwind(|| -> Result<Value, String> {
        let mut text = String::new();
        io::stdin()
            .take(1024 * 1024 + 1)
            .read_to_string(&mut text)
            .map_err(|e| e.to_string())?;
        if text.len() > 1024 * 1024 {
            return Err("요청이 너무 큽니다.".into());
        }
        cy_pdfcraft::process_json(&text, &mut DiskStorage)
    });
    match result {
        Ok(Ok(value)) => println!("{value}"),
        other => {
            let error = match other {
                Ok(Err(e)) => e,
                _ => "PDF 처리 중 오류가 발생했습니다. 원본은 변경하지 않았습니다.".into(),
            };
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}
