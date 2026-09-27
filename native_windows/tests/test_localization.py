import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cy_localization as language

class LanguageTests(unittest.TestCase):
    def test_language_persistence_and_corrupt_settings(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'APPDATA': directory}):
            self.assertEqual(language.load_mode(), 'system')
            language.save_mode('en')
            self.assertEqual(language.load_mode(), 'en')
            language.settings_path().write_text('broken', encoding='utf-8')
            self.assertEqual(language.load_mode(), 'system')
            with self.assertRaises(ValueError): language.save_mode('invalid')

    def test_translation_and_argument_preservation(self):
        with patch.object(language, 'LANGUAGE', 'en'):
            self.assertEqual(language.tr('PDF 열기'), 'Open PDF')
            self.assertEqual(language.tr('{0} 페이지', '{1}'), 'Page {1}')
        with patch.object(language, 'LANGUAGE', 'ko'):
            self.assertEqual(language.tr('{0} 페이지', 2), '2 페이지')
