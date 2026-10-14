//! PdfCraft의 페이지 조직 엔진을 CY뷰어의 별도 저장 작업에 연결한다.
#![forbid(unsafe_code)]
use pdfcraft_cos::{Document, SaveOptions, write_full};
use pdfcraft_organize::{Combiner, page_count};
use serde::Deserialize;
use std::{
    collections::HashSet,
    fs,
    io::{self, Read, Write},
    path::PathBuf,
    sync::Arc,
};

const MAX_BYTES: u64 = 256 * 1024 * 1024;
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Source {
    path: PathBuf,
    title: String,
    pages: Option<String>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    sources: Vec<Source>,
    output: PathBuf,
}

fn selection(text: &str, count: usize) -> Result<Vec<usize>, String> {
    if text.trim().is_empty() || text.len() > 100_000 {
        return Err("페이지 범위를 입력하세요.".into());
    }
    let mut result = Vec::new();
    let mut seen = HashSet::new();
    for part in text.split(',') {
        let ends: Vec<_> = part.trim().split('-').collect();
        if ends.is_empty() || ends.len() > 2 {
            return Err("페이지 범위는 1-3, 5 형식으로 입력하세요.".into());
        }
        let parse = |s: &str| -> Result<usize, String> {
            let n = s
                .trim()
                .parse::<usize>()
                .map_err(|_| "페이지는 숫자로 입력하세요.")?;
            if n == 0 || n > count {
                return Err(format!("페이지는 1부터 {count}까지 선택하세요."));
            }
            Ok(n)
        };
        let first = parse(ends[0])?;
        let last = if ends.len() == 2 {
            parse(ends[1])?
        } else {
            first
        };
        if last < first {
            return Err("범위는 작은 페이지부터 입력하세요. 순서는 3, 1, 2처럼 지정하세요.".into());
        }
        for n in first..=last {
            if !seen.insert(n) {
                return Err("같은 페이지를 두 번 선택할 수 없습니다.".into());
            }
            result.push(n - 1);
            if result.len() > 100_000 {
                return Err("한 번에 선택할 수 있는 페이지가 너무 많습니다.".into());
            }
        }
    }
    Ok(result)
}

fn compose(request: Request) -> Result<usize, String> {
    if request.sources.is_empty() || request.sources.len() > 20 {
        return Err("PDF는 1개부터 20개까지 선택하세요.".into());
    }
    if request.output.exists() {
        return Err("저장할 임시 파일이 이미 있습니다.".into());
    }
    let mut combiner = Combiner::new();
    let mut expected = 0usize;
    let mut total_bytes = 0u64;
    for source in request.sources {
        let mut file =
            fs::File::open(&source.path).map_err(|e| format!("PDF를 읽을 수 없습니다: {e}"))?;
        let mut bytes = Vec::new();
        (&mut file)
            .take(MAX_BYTES + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        total_bytes += bytes.len() as u64;
        if bytes.len() as u64 > MAX_BYTES || total_bytes > 2 * MAX_BYTES {
            return Err("한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.".into());
        }
        let doc =
            Document::open(Arc::new(bytes)).map_err(|e| format!("PDF를 열 수 없습니다: {e}"))?;
        // 병합·추출 결과에서 암호나 서명을 조용히 제거하지 않는다.
        if doc.security().is_some() {
            return Err("암호화된 PDF는 페이지 구성에 사용할 수 없습니다.".into());
        }
        for (_, object) in doc.scan_objects_checked() {
            let object = object.map_err(|e| format!("PDF 구조를 확인할 수 없습니다: {e}"))?;
            if let Some(dict) = object.as_dict()
                && (dict.name(b"Type") == Some(b"Sig") || dict.contains(b"ByteRange"))
            {
                return Err("전자서명된 PDF는 페이지 구성에 사용할 수 없습니다.".into());
            }
        }
        let count = page_count(&doc).map_err(|e| e.to_string())?;
        let chosen = source
            .pages
            .as_deref()
            .map(|s| selection(s, count))
            .transpose()?;
        expected = expected
            .checked_add(chosen.as_ref().map_or(count, Vec::len))
            .ok_or("페이지가 너무 많습니다.")?;
        if expected == 0 || expected > 100_000 {
            return Err("전체 페이지 수는 1부터 100000까지 허용됩니다.".into());
        }
        combiner
            .add(&source.title, &doc, chosen.as_deref())
            .map_err(|e| e.to_string())?;
    }
    let out = combiner.finish().map_err(|e| e.to_string())?;
    let bytes = write_full(&out, &SaveOptions::default()).map_err(|e| e.to_string())?;
    if bytes.len() as u64 > 2 * MAX_BYTES {
        return Err("결과 PDF가 512MB를 넘습니다.".into());
    }
    let reopened = Document::open(Arc::new(bytes.clone())).map_err(|e| e.to_string())?;
    if page_count(&reopened).map_err(|e| e.to_string())? != expected {
        return Err("결과 PDF의 페이지 수가 일치하지 않습니다.".into());
    }
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&request.output)
        .map_err(|e| e.to_string())?;
    if let Err(e) = file.write_all(&bytes).and_then(|_| file.sync_all()) {
        drop(file);
        let _ = fs::remove_file(&request.output);
        return Err(e.to_string());
    }
    Ok(expected)
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("cy-pdfcraft 0.1.0 (PdfCraft d9607ec3)");
        return;
    }
    let result = std::panic::catch_unwind(|| -> Result<usize, String> {
        let mut json = String::new();
        io::stdin()
            .take(1024 * 1024 + 1)
            .read_to_string(&mut json)
            .map_err(|e| e.to_string())?;
        if json.len() > 1024 * 1024 {
            return Err("요청이 너무 큽니다.".into());
        }
        compose(serde_json::from_str(&json).map_err(|e| format!("요청 형식 오류: {e}"))?)
    });
    match result {
        Ok(Ok(pages)) => println!("{}", serde_json::json!({"pages": pages})),
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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_user_order_and_rejects_ambiguous_ranges() {
        assert_eq!(selection("3, 1-2", 4).unwrap(), vec![2, 0, 1]);
        for bad in [
            "",
            "0",
            "5",
            "1,1",
            "3-1",
            "1-2-3",
            "1,",
            "x",
            "999999999999999999999",
        ] {
            assert!(selection(bad, 4).is_err(), "{bad}");
        }
    }
}
