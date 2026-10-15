//! PdfCraft 문서 편집·보안 엔진을 CY뷰어의 로컬 도구에 연결한다.
#![forbid(unsafe_code)]
use pdfcraft_cos::{Algorithm, Document, NewEncryption, SaveOptions, write_full};
use pdfcraft_organize as org;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, HashSet},
    path::{Path, PathBuf},
    sync::Arc,
};
/// 네이티브 파일과 브라우저 메모리가 같은 편집 코드를 사용한다.
pub trait Storage {
    fn read(&mut self, path: &Path, limit: u64) -> Result<Vec<u8>, String>;
    fn exists(&self, path: &Path) -> bool;
    fn write_new(&mut self, path: &Path, bytes: &[u8]) -> Result<(), String>;
}

pub fn process_json(text: &str, storage: &mut impl Storage) -> Result<Value, String> {
    if text.len() > 1024 * 1024 {
        return Err("요청이 너무 큽니다.".into());
    }
    execute(
        serde_json::from_str(text).map_err(|_| "도구 요청 형식이 올바르지 않습니다.")?,
        storage,
    )
}

const MAX_BYTES: u64 = 256 * 1024 * 1024;
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Source {
    path: PathBuf,
    title: String,
    pages: Option<String>,
    password: Option<String>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PageStep {
    index: Option<usize>,
    #[serde(default)]
    rotation: i64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct BookmarkEdit {
    action: String,
    #[serde(default)]
    path: Vec<usize>,
    title: Option<String>,
    page: Option<usize>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    sources: Vec<Source>,
    output: PathBuf,
    #[serde(default)]
    inspect: bool,
    page_plan: Option<Vec<PageStep>>,
    metadata: Option<BTreeMap<String, String>>,
    #[serde(default)]
    bookmarks: Vec<BookmarkEdit>,
    split_every: Option<usize>,
    finishing: Option<Finishing>,
    new_password: Option<String>,
    #[serde(default)]
    remove_password: bool,
}
/// 새 파일 전체에 적용할 문서 마무리 설정. 기본은 변경 없음이다.
#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields)]
struct Finishing {
    watermark: Option<String>,
    header: Option<String>,
    footer: Option<String>,
    #[serde(default)]
    page_numbers: bool,
    crop_mm: Option<[f64; 4]>,
    #[serde(default)]
    reset_crop: bool,
    background: Option<[f64; 3]>,
    #[serde(default)]
    remove_marks: bool,
    #[serde(default)]
    optimize: bool,
}
fn finish_document(doc: &mut Document, f: &Finishing) -> Result<(), String> {
    use pdfcraft_edit as edit;
    let count = org::page_count(doc).map_err(|e| e.to_string())?;
    let pages: Vec<_> = (0..count).collect();
    // 이 upstream 표준 글꼴은 한글을 그리지 못한다. 물음표로 조용히 바꾸지 않는다.
    for text in [&f.watermark, &f.header, &f.footer].into_iter().flatten() {
        if text.contains("<<")
            || text.len() > 2000
            || !text.chars().all(|c| c == '\n' || (' '..='~').contains(&c))
        {
            return Err(
                "워터마크·머리말·꼬리말은 영문·숫자·기본 기호로 2000자 이내 입력하세요.".into(),
            );
        }
    }
    if f.reset_crop && f.crop_mm.is_some() {
        return Err("여백 자르기와 자르기 해제를 동시에 선택할 수 없습니다.".into());
    }
    if f.reset_crop {
        org::set_page_box(doc, &pages, org::PageBox::Crop, org::BoxSpec::Remove)
            .map_err(|e| e.to_string())?;
    }
    if let Some(mm) = f.crop_mm {
        if !mm
            .iter()
            .all(|v| v.is_finite() && *v >= 0.0 && *v <= 1000.0)
        {
            return Err("자르기 여백은 0~1000mm로 입력하세요.".into());
        }
        // 화면 입력 순서: 왼쪽·위·오른쪽·아래. PDF는 왼쪽·아래·오른쪽·위.
        let pt = [mm[0], mm[3], mm[2], mm[1]].map(|v| v * 72.0 / 25.4);
        org::set_page_box(doc, &pages, org::PageBox::Crop, org::BoxSpec::Margins(pt))
            .map_err(|e| format!("자르기 여백을 줄이세요: {e}"))?;
    }
    if f.remove_marks {
        for kind in [
            edit::MarkKind::Watermark,
            edit::MarkKind::HeaderFooter,
            edit::MarkKind::Background,
        ] {
            edit::remove_marks(doc, &pages, kind).map_err(|e| e.to_string())?;
        }
    }
    if let Some(color) = f.background {
        if !color
            .iter()
            .all(|v| v.is_finite() && (0.0..=1.0).contains(v))
        {
            return Err("배경색 값은 0부터 1까지 지정하세요.".into());
        }
        edit::add_background(
            doc,
            &pages,
            &edit::Background {
                color,
                ..Default::default()
            },
            true,
        )
        .map_err(|e| e.to_string())?;
    }
    if let Some(text) = &f.watermark {
        if text.trim().is_empty() {
            return Err("워터마크 문구를 입력하세요.".into());
        }
        edit::add_watermark(
            doc,
            &pages,
            &edit::Watermark {
                text: text.clone(),
                opacity: 0.25,
                ..Default::default()
            },
            true,
        )
        .map_err(|e| e.to_string())?;
    }
    if f.header.is_some() || f.footer.is_some() || f.page_numbers {
        let mut footer = f.footer.clone().unwrap_or_default();
        if f.page_numbers {
            if !footer.is_empty() {
                footer.push_str(" · ");
            }
            footer.push_str("<<1/n>>");
        }
        let mut text: [String; 6] = Default::default();
        text[1] = f.header.clone().unwrap_or_default();
        text[4] = footer;
        edit::add_header_footer(
            doc,
            &pages,
            &edit::HeaderFooter {
                text,
                font_size: 10.0,
                ..Default::default()
            },
            true,
            &edit::Context::default(),
        )
        .map_err(|e| e.to_string())?;
    }
    if f.optimize {
        pdfcraft_optimize::optimize(doc, &Default::default())
            .map_err(|e| format!("용량 최적화에 실패했습니다: {e}"))?;
    }
    Ok(())
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

fn load(source: &Source, total: &mut u64, storage: &mut impl Storage) -> Result<Document, String> {
    let bytes = storage.read(&source.path, MAX_BYTES + 1)?;
    *total += bytes.len() as u64;
    if bytes.len() as u64 > MAX_BYTES || *total > 2 * MAX_BYTES {
        return Err("한 파일은 256MB, 전체는 512MB까지 처리할 수 있습니다.".into());
    }
    Document::open_with_password(Arc::new(bytes), source.password.as_deref()).map_err(|e| match e {
        pdfcraft_cos::CosError::NeedsPassword => "현재 PDF의 암호를 입력하세요.".into(),
        pdfcraft_cos::CosError::WrongPassword => "현재 암호가 올바르지 않습니다.".into(),
        _ => format!("PDF를 열 수 없습니다: {e}"),
    })
}
fn signed(doc: &Document) -> Result<bool, String> {
    for (_, object) in doc.scan_objects_checked() {
        let object = object.map_err(|e| e.to_string())?;
        if let Some(d) = object.as_dict()
            && (d.name(b"Type") == Some(b"Sig") || d.contains(b"ByteRange"))
        {
            return Ok(true);
        }
    }
    Ok(false)
}
fn editable(doc: &mut Document, request: &Request) -> Result<(), String> {
    if signed(doc)? {
        return Err("전자서명된 PDF는 편집할 수 없습니다.".into());
    }
    if let Some(p) = doc.permissions() {
        if !p.owner {
            return Err("편집하려면 PDF의 소유자 암호를 입력하세요.".into());
        }
        if request.new_password.is_none() && !request.remove_password {
            return Err("암호 PDF는 새 암호 설정 또는 암호 해제를 선택하세요.".into());
        }
        doc.remove_encryption();
    }
    Ok(())
}
fn edit_bookmarks(doc: &mut Document, edits: &[BookmarkEdit]) -> Result<(), String> {
    if edits.len() > 2000 {
        return Err("책갈피 변경은 2000개까지 허용됩니다.".into());
    }
    let count = org::page_count(doc).map_err(|e| e.to_string())?;
    for edit in edits {
        if edit.action == "update" || edit.action == "add" {
            let title = edit
                .title
                .as_deref()
                .filter(|s| !s.trim().is_empty() && s.len() <= 4000)
                .ok_or("책갈피 이름을 입력하세요.")?;
            let page = edit
                .page
                .filter(|p| *p > 0 && *p <= count)
                .ok_or("책갈피 페이지가 문서 범위를 벗어났습니다.")?
                - 1;
            if edit.action == "update" {
                org::rename_bookmark(doc, &edit.path, title).map_err(|e| e.to_string())?;
                org::set_bookmark_page(doc, &edit.path, page).map_err(|e| e.to_string())?;
            } else {
                let index = org::bookmarks(doc)
                    .iter()
                    .filter(|b| b.path.len() == 1)
                    .count();
                org::add_bookmark(doc, &[], index, title, page).map_err(|e| e.to_string())?;
            }
        } else if edit.action != "delete" {
            return Err("알 수 없는 책갈피 작업입니다.".into());
        }
    }
    let mut removed: Vec<_> = edits
        .iter()
        .filter(|e| e.action == "delete")
        .map(|e| e.path.clone())
        .collect();
    removed.sort();
    removed.dedup();
    // 부모를 지우는 경우 그 자식 경로를 다시 지우지 않는다.
    let roots: Vec<_> = removed
        .iter()
        .filter(|p| {
            !removed
                .iter()
                .any(|a| a.len() < p.len() && p.starts_with(a))
        })
        .cloned()
        .collect();
    for path in roots.iter().rev() {
        org::delete_bookmark(doc, path).map_err(|e| e.to_string())?;
    }
    Ok(())
}
fn protect(doc: &mut Document, password: Option<&str>) -> Result<(), String> {
    if let Some(password) = password {
        if password.is_empty() || password.len() > 1024 {
            return Err("새 암호는 1~1024바이트로 입력하세요.".into());
        }
        let mut seed = [0; 32];
        getrandom::fill(&mut seed).map_err(|_| "암호화 난수를 만들 수 없습니다.")?;
        doc.set_encryption(&NewEncryption {
            algorithm: Algorithm::Aes256,
            user_password: password,
            owner_password: password,
            permissions: -4,
            encrypt_metadata: true,
            seed,
        })
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}
fn write_output(
    mut doc: Document,
    path: &Path,
    password: Option<&str>,
    total: &mut u64,
    storage: &mut impl Storage,
) -> Result<Value, String> {
    if storage.exists(path) {
        return Err("저장할 임시 파일이 이미 있습니다.".into());
    }
    protect(&mut doc, password)?;
    let count = org::page_count(&doc).map_err(|e| e.to_string())?;
    let bytes = write_full(&doc, &SaveOptions::default()).map_err(|e| e.to_string())?;
    *total += bytes.len() as u64;
    if *total > 2 * MAX_BYTES {
        return Err("결과 PDF가 512MB를 넘습니다.".into());
    }
    let reopened = Document::open_with_password(Arc::new(bytes.clone()), password)
        .map_err(|e| e.to_string())?;
    if org::page_count(&reopened).map_err(|e| e.to_string())? != count {
        return Err("결과 PDF의 페이지 수가 일치하지 않습니다.".into());
    }
    storage.write_new(path, &bytes)?;
    Ok(json!({"path":path,"pages":count,"encrypted":password.is_some()}))
}
fn execute(request: Request, storage: &mut impl Storage) -> Result<Value, String> {
    if request.sources.is_empty() || request.sources.len() > 20 {
        return Err("PDF는 1개부터 20개까지 선택하세요.".into());
    }
    if request.new_password.is_some() && request.remove_password {
        return Err("암호 설정과 해제를 동시에 선택할 수 없습니다.".into());
    }
    let mut total = 0;
    let first_source = request.sources.first().ok_or("PDF가 없습니다.")?;
    let mut first = load(first_source, &mut total, storage)?;
    let count = org::page_count(&first).map_err(|e| e.to_string())?;
    if request.inspect {
        return Ok(
            json!({"pages":count,"encrypted":first.security().is_some(),"owner":first.permissions().is_none_or(|p|p.owner),"signed":signed(&first)?,
   "metadata":org::INFO_KEYS.iter().map(|k|(k.to_string(),org::info(&first,k).unwrap_or_default())).collect::<BTreeMap<_,_>>(),
   "bookmarks":org::bookmarks(&first).iter().map(|b|json!({"path":b.path,"title":b.title,"page":b.page.map(|p|p+1)})).collect::<Vec<_>>() }),
        );
    }
    editable(&mut first, &request)?;
    edit_bookmarks(&mut first, &request.bookmarks)?;
    let info: BTreeMap<_, _> = org::INFO_KEYS
        .iter()
        .map(|k| (k.to_string(), org::info(&first, k).unwrap_or_default()))
        .collect();
    let legacy = first_source
        .pages
        .as_deref()
        .map(|s| {
            selection(s, count).map(|v| {
                v.into_iter()
                    .map(|index| PageStep {
                        index: Some(index),
                        rotation: 0,
                    })
                    .collect::<Vec<_>>()
            })
        })
        .transpose()?;
    let plan = request.page_plan.as_ref().or(legacy.as_ref());
    let mut seen = HashSet::new();
    if let Some(plan) = plan {
        if plan.is_empty() || plan.len() > 100000 {
            return Err("문서는 1~100000쪽을 유지해야 합니다.".into());
        }
        for step in plan {
            if step.rotation % 90 != 0 {
                return Err("회전은 90도 단위로 지정하세요.".into());
            }
            if let Some(i) = step.index
                && (i >= count || !seen.insert(i))
            {
                return Err("페이지 번호가 잘못되었거나 중복되었습니다.".into());
            }
        }
    }
    let mut out = if request.sources.len() == 1 && plan.is_none() {
        first.clone()
    } else {
        let chosen = plan.map(|p| p.iter().filter_map(|s| s.index).collect::<Vec<_>>());
        let mut combiner = org::Combiner::new();
        let mut added = false;
        if chosen.as_ref().is_none_or(|p| !p.is_empty()) {
            combiner
                .add(&first_source.title, &first, chosen.as_deref())
                .map_err(|e| e.to_string())?;
            added = true;
        }
        for source in request.sources.iter().skip(1) {
            let mut doc = load(source, &mut total, storage)?;
            editable(&mut doc, &request)?;
            let selected = source
                .pages
                .as_deref()
                .map(|s| selection(s, org::page_count(&doc).map_err(|e| e.to_string())?))
                .transpose()?;
            combiner
                .add(&source.title, &doc, selected.as_deref())
                .map_err(|e| e.to_string())?;
            added = true;
        }
        if added {
            combiner.finish().map_err(|e| e.to_string())?
        } else {
            Document::new_empty()
        }
    };
    if let Some(plan) = plan {
        for (at, step) in plan.iter().enumerate() {
            if step.index.is_none() {
                org::insert_blank_page(&mut out, at, 595.28, 841.89).map_err(|e| e.to_string())?;
            }
            if step.rotation != 0 {
                org::rotate_pages(&mut out, &[at], step.rotation).map_err(|e| e.to_string())?;
            }
        }
    }
    for (key, value) in request.metadata.as_ref().unwrap_or(&info) {
        if !org::INFO_KEYS.contains(&key.as_str()) || value.len() > 20000 {
            return Err("문서 정보 항목 또는 길이가 잘못되었습니다.".into());
        }
        org::set_info(&mut out, key, value).map_err(|e| e.to_string())?;
    }
    let count = org::page_count(&out).map_err(|e| e.to_string())?;
    if count == 0 || count > 100000 {
        return Err("문서는 1~100000쪽을 유지해야 합니다.".into());
    }
    if let Some(f) = &request.finishing {
        finish_document(&mut out, f)?;
    }
    let mut written = 0;
    let mut files = Vec::new();
    if let Some(every) = request.split_every {
        if every == 0 || count.div_ceil(every) > 500 {
            return Err("분할 간격은 1 이상, 결과 파일은 500개 이하로 지정하세요.".into());
        }
        for (i, range) in org::split_ranges(count, &org::SplitBy::PageCount(every))
            .iter()
            .enumerate()
        {
            let selected: Vec<_> = range.clone().collect();
            let label = format!("part-{:03}", i + 1);
            let mut part = org::combine_selected(&[(&label, &out, Some(selected.as_slice()))])
                .map_err(|e| e.to_string())?;
            for key in org::INFO_KEYS {
                if let Some(value) = org::info(&out, key) {
                    org::set_info(&mut part, key, &value).map_err(|e| e.to_string())?;
                }
            }
            let path = request
                .output
                .with_file_name(format!("part-{:03}.pdf", i + 1));
            files.push(write_output(
                part,
                &path,
                request.new_password.as_deref(),
                &mut written,
                storage,
            )?);
        }
    } else {
        files.push(write_output(
            out,
            &request.output,
            request.new_password.as_deref(),
            &mut written,
            storage,
        )?);
    }
    Ok(json!({"pages":count,"files":files}))
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

#[cfg(target_arch = "wasm32")]
mod browser;
