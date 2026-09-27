import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import recent_files

class RecentFilesTests(unittest.TestCase):
    def test_five_mru_and_reopen_without_deleting_original(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'APPDATA': directory}):
            paths = [Path(directory)/f'{i}.pdf' for i in range(7)]
            for path in paths:
                path.write_bytes(b'%PDF-1.7')
                recent_files.remember(path)
            self.assertEqual(recent_files.load_recent(), [str(p.resolve()) for p in reversed(paths[-5:])])
            recent_files.remember(paths[3])
            saved = recent_files.load_recent()
            self.assertEqual(saved[0], str(paths[3].resolve()))
            self.assertEqual(len(saved), 5)
            self.assertEqual(len(set(saved)), 5)
            self.assertTrue(paths[0].exists())

    def test_corrupt_and_invalid_values(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'APPDATA': directory}):
            path=recent_files.store_path(); path.parent.mkdir()
            for value in ['broken', '{}', 'null', '[1, {}, null]']:
                path.write_text(value, encoding='utf-8')
                self.assertEqual(recent_files.load_recent(), [])
