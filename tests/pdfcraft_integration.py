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
from pdfcraft import compose_pdf, save_copy, tools_request
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
        with pymupdf.open(stream=original, filetype='pdf') as doc:
            signature = doc.get_new_xref()
            doc.update_object(signature, '<< /Type /Sig /ByteRange [0 1 2 3] >>')
            signed = doc.tobytes(garbage=0)
        with self.assertRaises(RuntimeError): compose_pdf(signed, 'signed.pdf', '1', [], HELPER)

    def test_helper_never_overwrites_input_or_existing_output(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'original.pdf'
            original = fixture(['ONE'])
            source.write_bytes(original)
            request = {'sources':[{'path':str(source),'title':'original','pages':'1'}], 'output':str(source)}
            run = subprocess.run([str(HELPER)], input=json.dumps(request).encode(), capture_output=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(source.read_bytes(), original)

class PdfcraftWorkbenchTests(unittest.TestCase):
    def setUp(self):
        self.source = fixture(['ONE', 'TWO', 'THREE', 'FOUR'])

    def test_page_editing_rotation_blank_delete_and_destination_mapping(self):
        options = {'page_plan': [{'index': 3, 'rotation': 90}, {'index': None, 'rotation': 0}, {'index': 0, 'rotation': 180}]}
        _, data = tools_request(self.source, '원본', options, helper=HELPER)
        with pymupdf.open(stream=data, filetype='pdf') as out:
            self.assertEqual(len(out), 3)
            self.assertIn('FOUR', out[0].get_text())
            self.assertEqual(out[1].get_text(), '')
            self.assertIn('ONE', out[2].get_text())
            self.assertEqual([p.rotation for p in out], [90, 0, 180])
            self.assertEqual(out[2].get_links()[0]['page'], 0)
            self.assertTrue(any(row[1] == 'First' and row[2] == 3 for row in out.get_toc()))

    def test_metadata_and_actual_outline_edits(self):
        info, _ = tools_request(self.source, '원본', {'inspect': True}, helper=HELPER)
        self.assertEqual(info['bookmarks'][0]['title'], 'First')
        _, data = tools_request(self.source, '원본', {
            'metadata': {'Title': '한글 제목', 'Author': '작성자', 'Subject': '주제', 'Keywords': '검색어'},
            'bookmarks': [{'action': 'update', 'path': [0], 'title': '수정한 책갈피', 'page': 2}, {'action': 'add', 'title': '마지막 장', 'page': 4}],
        }, helper=HELPER)
        with pymupdf.open(stream=data, filetype='pdf') as out:
            self.assertEqual(out.metadata['title'], '한글 제목')
            self.assertEqual(out.metadata['author'], '작성자')
            self.assertEqual(out.get_toc(), [[1, '수정한 책갈피', 2], [1, '마지막 장', 4]])
        _, removed = tools_request(data, '원본', {'bookmarks': [{'action': 'delete', 'path': [0]}]}, helper=HELPER)
        with pymupdf.open(stream=removed, filetype='pdf') as out:
            self.assertEqual(out.get_toc(), [[1, '마지막 장', 4]])

    def test_split_zip_is_reopenable_and_preserves_pages(self):
        import zipfile, io
        report, data = tools_request(self.source, '원본', {'split_every': 3}, helper=HELPER)
        self.assertEqual(report['pages'], 4)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            self.assertEqual(archive.namelist(), ['part-001.pdf', 'part-002.pdf'])
            counts = []
            for name in archive.namelist():
                with pymupdf.open(stream=archive.read(name), filetype='pdf') as out:
                    counts.append(len(out))
            self.assertEqual(counts, [3, 1])
            with pymupdf.open(stream=archive.read('part-001.pdf'), filetype='pdf') as first:
                self.assertIn('ONE', first[0].get_text())
                self.assertTrue(any(row[1] == 'First' for row in first.get_toc()))
            with pymupdf.open(stream=archive.read('part-002.pdf'), filetype='pdf') as last:
                self.assertIn('FOUR', last[0].get_text())

    def test_aes256_password_change_remove_and_encrypted_split(self):
        import zipfile, io
        _, encrypted = tools_request(self.source, '원본', {'new_password': '한글-암호-123'}, helper=HELPER)
        with pymupdf.open(stream=encrypted, filetype='pdf') as doc:
            self.assertTrue(doc.needs_pass)
            self.assertFalse(doc.authenticate('wrong'))
            self.assertTrue(doc.authenticate('한글-암호-123'))
            self.assertIn('256-bit AES', doc.metadata['encryption'])
            self.assertIn('ONE', doc[0].get_text())
        with self.assertRaises(RuntimeError): tools_request(encrypted, '잠금', {'remove_password': True}, 'wrong', HELPER)
        with self.assertRaises(RuntimeError): tools_request(encrypted, '잠금', {}, '한글-암호-123', HELPER)
        _, changed = tools_request(encrypted, '잠금', {'new_password': 'changed'}, '한글-암호-123', HELPER)
        with pymupdf.open(stream=changed, filetype='pdf') as doc:
            self.assertFalse(doc.authenticate('한글-암호-123'))
            self.assertTrue(doc.authenticate('changed'))
        _, plain = tools_request(changed, '잠금', {'remove_password': True}, 'changed', HELPER)
        with pymupdf.open(stream=plain, filetype='pdf') as doc:
            self.assertFalse(doc.needs_pass)
            self.assertIn('FOUR', doc[3].get_text())
        _, zipped = tools_request(encrypted, '잠금', {'split_every': 2, 'new_password': 'parts'}, '한글-암호-123', HELPER)
        with zipfile.ZipFile(io.BytesIO(zipped)) as archive:
            for name in archive.namelist():
                with pymupdf.open(stream=archive.read(name), filetype='pdf') as doc:
                    self.assertTrue(doc.needs_pass)
                    self.assertTrue(doc.authenticate('parts'))
                    self.assertEqual(len(doc), 2)

    def test_finishing_marks_crop_numbering_reset_and_original(self):
        before = hashlib.sha256(self.source).hexdigest()
        _, data = tools_request(self.source, '마무리', {'finishing': {'watermark': 'DRAFT', 'header': 'CY VIEWER', 'footer': 'CONFIDENTIAL', 'page_numbers': True, 'crop_mm': [2, 3, 4, 5], 'background': [1, 1, 0.85]}}, helper=HELPER)
        with pymupdf.open(stream=data, filetype='pdf') as out:
            for i, page in enumerate(out):
                self.assertIn('DRAFT', page.get_text())
                self.assertIn('CY VIEWER', page.get_text())
                self.assertIn(f'{i+1}/4', page.get_text())
                self.assertAlmostEqual(page.rect.width, 300 - 6 * 72 / 25.4, places=3)
                self.assertAlmostEqual(page.rect.height, 400 - 8 * 72 / 25.4, places=3)
            self.assertTrue(out[0].get_links())
            self.assertEqual(len(list(out[0].widgets())), 1)
        _, restored = tools_request(data, '해제', {'finishing': {'remove_marks': True, 'reset_crop': True}}, helper=HELPER)
        with pymupdf.open(stream=restored, filetype='pdf') as out, pymupdf.open(stream=self.source, filetype='pdf') as source:
            for i, page in enumerate(out):
                self.assertNotIn('DRAFT', page.get_text())
                self.assertEqual(page.rect, source[i].rect)
                self.assertEqual(page.get_pixmap().samples, source[i].get_pixmap().samples)
        self.assertEqual(hashlib.sha256(self.source).hexdigest(), before)
        for finishing in [{'crop_mm': [100,100,100,100]}, {'crop_mm': [-1,0,0,0]}, {'watermark': '한글'}, {'watermark': ''}, {'header': '<<yyyy-mm-dd>>'}, {'background': [2,0,0]}]:
            with self.assertRaises(RuntimeError): tools_request(self.source, '거부', {'finishing': finishing}, helper=HELPER)

    def test_image_optimization_retains_text_and_reduces_large_image(self):
        import random
        with pymupdf.open(stream=self.source, filetype='pdf') as doc:
            pix = pymupdf.Pixmap(pymupdf.csRGB, 1200, 1200, random.Random(7).randbytes(1200*1200*3), False)
            doc[1].insert_image(pymupdf.Rect(0, 100, 300, 400), pixmap=pix)
            original = doc.tobytes()
        _, data = tools_request(original, '최적화', {'finishing': {'optimize': True}}, helper=HELPER)
        self.assertLess(len(data), len(original))
        with pymupdf.open(stream=data, filetype='pdf') as out:
            self.assertEqual(len(out), 4)
            self.assertIn('TWO', out[1].get_text())
            image = out.extract_image(out[1].get_images()[0][0])
            self.assertLess(image['width'], 1200)
            self.assertTrue(out[0].get_links())
            self.assertEqual(len(list(out[0].widgets())), 1)

    def test_owner_permission_and_invalid_edits_are_enforced(self):
        with pymupdf.open(stream=self.source, filetype='pdf') as doc:
            restricted = doc.tobytes(encryption=pymupdf.PDF_ENCRYPT_AES_256, owner_pw='owner', user_pw='reader', permissions=pymupdf.PDF_PERM_PRINT)
        info, _ = tools_request(restricted, '제한', {'inspect': True}, 'reader', HELPER)
        self.assertFalse(info['owner'])
        with self.assertRaises(RuntimeError): tools_request(restricted, '제한', {'remove_password': True}, 'reader', HELPER)
        for options in [{'page_plan': []}, {'page_plan': [{'index': 99}]}, {'page_plan': [{'index': 0}, {'index': 0}]}, {'split_every': 0}, {'bookmarks': [{'action':'add','title':'','page':1}]}]:
            with self.assertRaises(RuntimeError): tools_request(self.source, '원본', options, helper=HELPER)

if __name__ == '__main__': unittest.main()
