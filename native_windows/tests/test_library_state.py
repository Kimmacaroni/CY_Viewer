import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from recent_files import load_library, save_library, library_path
from design import palette

class LibraryStateTests(unittest.TestCase):
    def test_favorites_and_reading_position_survive_restart(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,{'APPDATA':directory}):
            state={'document.pdf':{'favorite':True,'page':7}}
            save_library(state)
            self.assertEqual(load_library(),state)
            library_path().write_text('not json',encoding='utf-8')
            self.assertEqual(load_library(),{})
            library_path().write_text('{"x":{"page":-3,"favorite":"yes"}}',encoding='utf-8')
            self.assertEqual(load_library(),{'x':{'page':1,'favorite':False}})

    def test_dark_palette_matches_shared_mac_tokens(self):
        dark=palette(True)
        self.assertEqual(dark['canvas'],'#10141C')
        self.assertEqual(dark['surface'],'#191F2A')
        self.assertEqual(dark['blue'],'#A9C5FF')
        self.assertEqual(palette()['canvas'],'#F4F6F9')
