from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pdfcraft import parse_pages, save_copy

class PageSafetyTests(unittest.TestCase):
    def test_user_order_and_invalid_ranges(self):
        self.assertEqual(parse_pages('3, 1-2', 4), [3,1,2])
        for value in ['', '0', '5', '1,1', '3-1', '1-2-3', '1,', 'x', '９']:
            with self.assertRaises(ValueError): parse_pages(value, 4)
    def test_input_and_hardlink_are_protected(self):
        with tempfile.TemporaryDirectory() as folder:
            original = Path(folder) / 'original.pdf'
            original.write_bytes(b'original')
            alias = Path(folder) / 'alias.pdf'
            alias.hardlink_to(original)
            for path in [original, alias]:
                with self.assertRaises(ValueError): save_copy(b'new', path, [original])
            self.assertEqual(original.read_bytes(), b'original')
            result = Path(folder) / 'result.pdf'
            save_copy(b'new', result, [original])
            self.assertEqual(result.read_bytes(), b'new')
