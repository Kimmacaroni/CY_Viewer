"""브라우저 WASM 산출물을 독립 PDF 엔진으로 검사한다."""
import json
from pathlib import Path
import sys
import pymupdf
from pdfcraft_integration import fixture
root = Path(sys.argv[2])
if sys.argv[1] == 'prepare':
    original = fixture(['ONE', 'TWO', 'THREE', 'FOUR'])
    (root / 'source.pdf').write_bytes(original)
    (root / 'added.pdf').write_bytes(fixture(['ADDED']))
    with pymupdf.open(stream=original, filetype='pdf') as doc:
        (root / 'restricted.pdf').write_bytes(doc.tobytes(encryption=pymupdf.PDF_ENCRYPT_AES_256, owner_pw='owner', user_pw='reader', permissions=pymupdf.PDF_PERM_PRINT))
        signature=doc.get_new_xref();doc.update_object(signature,'<< /Type /Sig /ByteRange [0 1 2 3] >>')
        (root/'signed.pdf').write_bytes(doc.tobytes(garbage=0))
else:
    data=json.loads((root/'results.json').read_text())
    with pymupdf.open(stream=bytes(data['edited']),filetype='pdf') as doc:
        assert len(doc)==3 and doc[0].rotation==90 and not doc[1].get_text()
        assert 'FOUR' in doc[0].get_text() and 'ONE' in doc[2].get_text()
        assert doc[2].get_links()[0]['page']==0
    with pymupdf.open(stream=bytes(data['metadata']),filetype='pdf') as doc:
        assert doc.metadata['title']=='브라우저 제목' and doc.metadata['author']=='작성자'
        assert doc.get_toc()==[[1,'바꾼 이름',2],[1,'마지막',4]]
    with pymupdf.open(stream=bytes(data['merged']),filetype='pdf') as doc:
        assert ['THREE','ONE','ADDED']==[page.get_text().splitlines()[0] for page in doc]
        assert len([w for p in doc for w in p.widgets()])==2
    for expected,part in zip([3,1],data['parts']):
        with pymupdf.open(stream=bytes(part),filetype='pdf') as doc: assert len(doc)==expected
    for name,password in [('encrypted','웹-암호'),('changed','changed')]:
        with pymupdf.open(stream=bytes(data[name]),filetype='pdf') as doc:
            assert doc.needs_pass and not doc.authenticate('wrong') and doc.authenticate(password)
            assert len(doc)==4 and '256-bit AES' in doc.metadata['encryption']
    with pymupdf.open(stream=bytes(data['removed']),filetype='pdf') as doc:assert not doc.needs_pass and len(doc)==4
    for part in data['encryptedParts']:
        with pymupdf.open(stream=bytes(part),filetype='pdf') as doc: assert doc.needs_pass and doc.authenticate('parts') and len(doc)==2
    print('브라우저 PdfCraft: 회전·삭제·빈 페이지·병합·분할·한글 정보·책갈피·암호·링크·폼·원본 보호 검사 통과')
