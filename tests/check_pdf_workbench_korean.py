"""전체 원본 카탈로그·화면 문구·진단과 한국어 자리표시자 계약을 검증한다."""
from pathlib import Path
import json, re, subprocess, tempfile, os, sys
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

ROOT=Path(__file__).resolve().parent.parent
SOURCE=ROOT/'build/pdf-workbench/source'
I18N=SOURCE/'crates/ui-egui/src/i18n'
def entries(path):
    rows={}
    for number,line in enumerate(path.read_text(encoding='utf-8').splitlines(),1):
        if not line or line.startswith('#'):continue
        fields=line.split('\t')
        assert len(fields)==3,(str(path),number)
        c,s,t=fields
        assert (c,s) not in rows,(str(path),number,'중복')
        rows[c,s]=t
    return rows

def encode(s):return s.replace('\\','\\\\').replace('\n','\\n').replace('\t','\\t')
ko=entries(I18N/'ko.tsv')
required=set()
for p in I18N.glob('*.tsv'):
    if p.name!='ko.tsv':required.update(entries(p))
literal_count=0
for p in (SOURCE/'crates/ui-egui/src').rglob('*.rs'):
    if 'i18n' in p.parts:continue
    source=p.read_text(encoding='utf-8').split('#[cfg(test)]')[0]
    for m in re.finditer(r'(?:tl!\(|i18n::t\()\s*"((?:\\.|[^"\\])*)"',source):
        required.add(('',encode(json.loads('"'+m[1]+'"'))));literal_count+=1
error_keys=set()
for p in (SOURCE/'crates').glob('*/src/**/*.rs'):
    for m in re.finditer(r'#\[error\(\s*"((?:\\.|[^"\\])*)"',p.read_text(encoding='utf-8')):
        error_keys.add(('',encode(json.loads('"'+m[1]+'"'))))
required.update(error_keys)
commands=(SOURCE/'crates/engine/src/commands.rs').read_text(encoding='utf-8')
engine=(SOURCE/'crates/engine/src/lib.rs').read_text(encoding='utf-8')
for m in re.finditer(r'EditError::NotPermitted\("([^"\n]+)"\)',engine):required.add(('',m[1]))
for m in re.finditer(r'\bct?\("[^"\n]+",\s*"((?:\\.|[^"\\])*)"',commands):
    required.add(('',encode(json.loads('"'+m[1]+'"'))))
catalog=(SOURCE/'crates/engine/src/catalog.rs').read_text(encoding='utf-8')
for m in re.finditer(r'(?:\b(?:label|title):\s*|\b(?:item|menu_item)\()"((?:\\.|[^"\\])*)"',catalog):
    required.add(('',encode(json.loads('"'+m[1]+'"'))))
missing=required-ko.keys()
assert not missing,sorted(missing)
assert len(ko)>2700 and literal_count>1000
allowed={'PDF','PDF/A…','ZIP','URL','DN: ','+LOC','−LOC','ΔLOC','Ctrl','Shift','Delete','Esc','Home','End'}
unchanged=[]
for (c,s),t in ko.items():
    literal=re.sub(r'\{[^{}]*\}','',s)
    if s==t and re.search(r'[A-Za-z]{2}',literal) and s not in allowed:
        unchanged.append((c,s))
assert not unchanged,unchanged
# 코드 예시는 번역으로 실행 의미가 달라지면 안 된다.
example=ko['','JavaScript, e.g. getField("total").value']
assert 'getField("total").value' in example

# 실제 원본 파서로 복수형·줄임표·자리표시자와 진단 치환을 검사한다.
def quoted(path):return json.dumps(str(path),ensure_ascii=False)
probe=f'''mod i18n {{
    #[path={quoted(I18N/'catalog.rs')}] pub mod catalog;
    pub struct Lang;
    impl Lang {{ pub fn code(&self) -> &str {{ "ko" }} }}
    pub fn current() -> Lang {{ Lang }}
    pub fn t(s: &str) -> &str {{
        static C: std::sync::OnceLock<catalog::Catalog> = std::sync::OnceLock::new();
        C.get_or_init(|| catalog::Catalog::parse(include_str!({quoted(I18N/'ko.tsv')}),1).0).plain(s).unwrap_or(s)
    }}
    #[path={quoted(I18N/'cy_korean.rs')}] pub mod cy_korean;
}}
#[test] fn korean_catalog_is_valid() {{
    let (_, errors)=i18n::catalog::parse_entries(include_str!({quoted(I18N/'ko.tsv')}),1);
    assert!(errors.is_empty(),"{{errors:#?}}");
}}
#[test] fn korean_diagnostics_preserve_values() {{
    let value="C:/보고서/{{n}}.pdf";
    let translated=i18n::cy_korean::diagnostic(&format!("unsupported filter: {{value}}"));
    assert!(translated.contains("지원되지"));
    assert!(translated.contains(value));
    assert!(i18n::cy_korean::diagnostic("the password is wrong").contains("비밀번호"));
    assert!(i18n::cy_korean::diagnostic("unrecognised vendor error 9876").contains("기술 정보"));
}}
'''
with tempfile.TemporaryDirectory(prefix='cy-ko-check-') as tmp:
    rs=Path(tmp)/'catalog.rs';rs.write_text(probe,encoding='utf-8')
    binary=Path(tmp)/('catalog.exe' if os.name=='nt' else 'catalog')
    subprocess.run(['rustc','--edition=2024','--test',str(rs),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
print(f'한국어 {len(ko)}개 · 원본 전체 카탈로그/화면 키 {len(required)}개 · 진단 {len(error_keys)}개: 누락 0, 원본 파서·문서 값 보존 검사 통과')
