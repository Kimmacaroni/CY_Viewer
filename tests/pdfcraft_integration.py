"""실제 PdfCraft 모듈의 결과를 독립 PDF 엔진으로 검증한다."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
import pymupdf

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'native_windows'))
from pdfcraft import compose_pdf, save_copy
HELPER = ROOT / 'build' / 'pdfcraft' / ('cy-pdfcraft.exe' if os.name == 'nt' else 'cy-pdfcraft')


def fixture(labels):
    doc = pymupdf.open()
    for label in labels:
        page = doc.new_page(width=300, height=400)
        page.insert_text((35, 50), label)
    doc.set_toc([[1, 'First', 1]])
    doc[0].add_highlight_annot(pymupdf.Rect(30, 35, 120, 55))
    widget = pymupdf.Widget()
    widget.field_name = 'name'
    widget.field_type = pymupdf.PDF_WIDGET_TYPE_TEXT
    widget.field_value = 'CY viewer'
    widget.rect = pymupdf.Rect(35, 80, 200, 110)
    doc[0].add_widget(widget)
    doc[0].insert_link({'kind': pymupdf.LINK_GOTO, 'from': pymupdf.Rect(30, 130, 90, 150), 'page': len(labels) - 1})
    result = doc.tobytes()
    doc.close()
    return result


class PdfcraftRoundTrips(unittest.TestCase):
    def test_reorder_merge_keeps_content_links_forms_annotations_and_original(self):
        original = fixture(['ALPHA', 'BETA', 'GAMMA'])
        with tempfile.TemporaryDirectory(prefix='CY 한글 경로 ') as folder:
            directory = Path(folder)
            added = directory / '추가 문서.pdf'
            added.write_bytes(fixture(['DELTA']))
            before = hashlib.sha256(added.read_bytes()).hexdigest()
            result = compose_pdf(original, '원본.pdf', '3,1-2', [added], HELPER)
            with pymupdf.open(stream=result, filetype='pdf') as out, pymupdf.open(stream=original, filetype='pdf') as source:
                self.assertEqual(len(out), 4)
                self.assertEqual([p.get_text().splitlines()[0] for p in out], ['GAMMA','ALPHA','BETA','DELTA'])
                for index, previous in enumerate([2,0,1]):
                    self.assertEqual(out[index].get_pixmap().samples, source[previous].get_pixmap().samples)
                self.assertEqual(out[1].get_links()[0]['page'], 0)
                self.assertEqual(len(list(out[1].annots())), 1)
                fields = [w.field_name for p in out for w in p.widgets()]
                self.assertEqual(len(fields), 2)
                self.assertEqual(len(set(fields)), 2)
                self.assertTrue(out.get_toc())
            self.assertEqual(hashlib.sha256(added.read_bytes()).hexdigest(), before)
            saved = directory / '결과.pdf'
            save_copy(result, saved, [added])
            self.assertEqual(saved.read_bytes(), result)
            with self.assertRaises(ValueError): save_copy(result, added, [added])

    def test_extraction_invalid_range_and_encryption_leave_inputs_untouched(self):
        original = fixture(['ONE', 'TWO', 'THREE'])
        result = compose_pdf(original, 'test.pdf', '2-3', [], HELPER)
        with pymupdf.open(stream=result, filetype='pdf') as out:
            self.assertEqual(len(out), 2)
            self.assertIn('TWO', out[0].get_text())
        for selection in ['0', '4', '1,1', '3-1']:
            with self.assertRaises(RuntimeError): compose_pdf(original, 'test.pdf', selection, [], HELPER)
        with pymupdf.open(stream=original, filetype='pdf') as doc:
            encrypted = doc.tobytes(encryption=pymupdf.PDF_ENCRYPT_AES_256, owner_pw='owner', user_pw='')
        with self.assertRaises(RuntimeError): compose_pdf(encrypted, 'secret.pdf', '1', [], HELPER)
        with self.assertRaises(RuntimeError): compose_pdf(b'not a pdf', 'broken.pdf', '1', [], HELPER)

    def test_helper_never_overwrites_input_or_existing_output(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'original.pdf'
            original = fixture(['ONE'])
            source.write_bytes(original)
            request = {'sources':[{'path':str(source),'title':'original','pages':'1'}], 'output':str(source)}
            run = subprocess.run([str(HELPER)], input=json.dumps(request).encode(), capture_output=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(source.read_bytes(), original)

if __name__ == '__main__': unittest.main()
