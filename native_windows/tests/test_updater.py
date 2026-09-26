import hashlib
import io
from pathlib import Path
import shutil
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from updater import Update, checksum_for, download, installer_script, select_release, version_tuple


def release(version):
    tag = 'windows-v'+version
    prefix = f'https://github.com/Kimmacaroni/CY_Viewer/releases/download/{tag}/'
    return {'tag_name':tag, 'draft':False, 'prerelease':False, 'assets':[
        {'name':f'CYViewer-Setup-v{version}.exe','size':4,'browser_download_url':prefix+f'CYViewer-Setup-v{version}.exe'},
        {'name':f'SHA256SUMS-Windows-v{version}.txt','browser_download_url':prefix+f'SHA256SUMS-Windows-v{version}.txt'}]}


class UpdaterTests(unittest.TestCase):
    def test_only_newer_complete_official_release(self):
        trial=release('9.0.0'); trial['prerelease']=True
        bad=release('10.0.0'); bad['assets'][0]['browser_download_url']='https://example.com/a.exe'
        self.assertEqual(select_release([release('1.9.0'),release('1.10.0'),trial,bad], '1.2.0').version,'1.10.0')
        self.assertIsNone(select_release([release('1.2.0')],'1.2.0'))
        self.assertIsNone(select_release([release('1.1.0')],'1.2.0'))
    def test_installer_version_matches_app(self):
        import re
        from version import APP_VERSION
        script = Path(__file__).resolve().parents[2] / 'installer/CYViewer.iss'
        declared = re.search(r'MyAppVersion "([0-9.]+)"', script.read_text(encoding="utf-8"))[1]
        self.assertEqual(APP_VERSION, declared)
    def test_invalid_version(self):
        for value in ['1.2.x','1.2.3-beta','1.2.3.4']:
            with self.assertRaises(ValueError): version_tuple(value)
    def test_checksum_and_filename_required(self):
        with self.assertRaises(ValueError): checksum_for('a'*64+'  other.exe', 'setup.exe')
    def test_download_rejects_corruption_and_truncation(self):
        update=Update('2.0.0','https://example.test/file','https://example.test/hash',4,'setup.exe')
        digest=hashlib.sha256(b'good').hexdigest()
        for body in [b'bad!',b'bad',b'toolong']:
            def opener(url): return io.BytesIO((digest+'  setup.exe').encode() if url.endswith('hash') else body)
            with self.assertRaises(ValueError): download(update,lambda _:None,opener)
    def test_download_accepts_verified_file(self):
        update=Update('2.0.0','https://example.test/file','https://example.test/hash',4,'setup.exe')
        digest=hashlib.sha256(b'good').hexdigest()
        def opener(url): return io.BytesIO((digest+'  setup.exe').encode() if url.endswith('hash') else b'good')
        path=download(update,lambda _:None,opener)
        self.assertEqual(path.read_bytes(),b'good');shutil.rmtree(path.parent)
    def test_installer_waits_for_app_and_quotes_paths(self):
        script=installer_script(Path("C:/O'Brien/setup.exe"),Path('C:/Apps/CYViewer.exe'),123)
        self.assertIn('Wait-Process -Id 123',script)
        self.assertIn("O''Brien",script)
        self.assertIn('/NOCLOSEAPPLICATIONS',script)
        self.assertIn('$setup.ExitCode -eq 0',script)

if __name__ == '__main__': unittest.main()
