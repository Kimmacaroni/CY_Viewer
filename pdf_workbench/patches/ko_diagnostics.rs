//! 고정 엔진의 진단 문구를 번역하되 파일명·값·기술 식별자는 보존한다.
const WORDINGS: &[&str] = include!("cy_error_templates.rs");

fn parts(template: &str) -> (Vec<String>, Vec<String>) {
    let mut text = String::new();
    let mut literals = Vec::new();
    let mut names = Vec::new();
    let mut chars = template.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '{' {
            if chars.peek() == Some(&'{') {
                chars.next();
                text.push('{');
                continue;
            }
            literals.push(std::mem::take(&mut text));
            let mut name = String::new();
            for c in chars.by_ref() {
                if c == '}' {
                    break;
                }
                name.push(c);
            }
            names.push(name);
        } else if c == '}' && chars.peek() == Some(&'}') {
            chars.next();
            text.push('}');
        } else {
            text.push(c);
        }
    }
    literals.push(text);
    (literals, names)
}

fn capture<'a>(message: &'a str, literals: &[String], values: &mut Vec<&'a str>) -> bool {
    let Some(rest) = message.strip_prefix(&literals[0]) else {
        return false;
    };
    if literals.len() == 1 {
        return rest.is_empty();
    }
    if literals.len() == 2 && literals[1].is_empty() {
        values.push(rest);
        return true;
    }
    let next = &literals[1];
    if next.is_empty() {
        return false;
    }
    for (end, _) in rest.match_indices(next) {
        values.push(&rest[..end]);
        if capture(&rest[end..], &literals[1..], values) {
            return true;
        }
        values.pop();
    }
    false
}

pub fn diagnostic(message: &str) -> String {
    if super::current().code() != "ko" {
        return message.to_owned();
    }
    let exact = super::t(message);
    if exact != message {
        return exact.to_owned();
    }
    for wording in WORDINGS {
        let (literals, names) = parts(wording);
        if names.is_empty() || literals.iter().all(String::is_empty) {
            continue;
        }
        let mut values = Vec::new();
        if !capture(message, &literals, &mut values) {
            continue;
        }
        let translated = super::t(wording);
        let (texts, holes) = parts(translated);
        let mut result = texts[0].clone();
        for (i, hole) in holes.iter().enumerate() {
            let Some(index) = names.iter().position(|name| name == hole) else {
                continue;
            };
            // 이 진단의 값은 문서 데이터가 아니라 엔진의 고정 권한 이름이다.
            let value = if wording.starts_with("the document's security settings don't allow ") {
                super::t(values[index])
            } else {
                values[index]
            };
            result.push_str(value);
            result.push_str(&texts[i + 1]);
        }
        return result;
    }
    if message.chars().any(|c| ('가'..='힣').contains(&c)) {
        return message.to_owned();
    }
    // 알 수 없는 OS/공급자 원문은 진단 손실을 막기 위해 한국어 안내 뒤에 보존한다.
    format!("작업을 완료하지 못했습니다. 파일과 설정을 확인해 주세요.\n기술 정보: {message}")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn document_values_are_not_translated_or_reinterpreted() {
        let (literals, _) = parts("cannot open {path}: {reason}");
        let mut values = Vec::new();
        assert!(capture(
            "cannot open C:/reports/{n}:final.pdf: permission denied",
            &literals,
            &mut values
        ));
        assert_eq!(values, ["C:/reports/{n}:final.pdf", "permission denied"]);
        // 문서 값의 중괄호는 번역 서식으로 다시 해석하지 않는다.
        assert!(values.join(": ").contains("{n}"));
    }
    #[test]
    fn escaped_braces_are_literal() {
        assert_eq!(
            parts("{{name}}: {value:?}"),
            (vec!["{name}: ".into(), "".into()], vec!["value:?".into()])
        );
    }
}
