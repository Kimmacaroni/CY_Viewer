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

    def test_palette_keeps_surfaces_distinct_and_text_readable(self):
        def luminance(color):
            rgb=[int(color[i:i+2],16)/255 for i in (1,3,5)]
            linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
            return sum(v*w for v,w in zip(linear,[.2126,.7152,.0722]))
        for dark in (False,True):
            colors=palette(dark)
            self.assertNotEqual(colors['canvas'],colors['surface'])
            for ink,background in [('ink','surface'),('muted','canvas'),('on_blue','blue'),('on_blue','blue_hover'),('on_blue','blue_pressed')]:
                a,b=sorted([luminance(colors[ink]),luminance(colors[background])])
                self.assertGreaterEqual((b+.05)/(a+.05),4.5)
