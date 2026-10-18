"""작업실에 실제 사본을 전달하고 종료 뒤 정리하는지 확인한다."""
from pathlib import Path
import sys, tempfile, threading, time, unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pdf_workbench

class WorkbenchTests(unittest.TestCase):
    def test_snapshot_is_separate_and_original_stays_unchanged(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);helper=root/'pdfcraft/cy-pdf-workbench.exe';helper.parent.mkdir();helper.touch()
            original=root/'document.pdf';original.write_bytes(b'original')
            done=threading.Event();inputs=[]
            class Process:
                def __init__(self,args,**kwargs):
                    inputs.append(Path(args[1]));self.snapshot=Path(args[1]).read_bytes()
                    self.assertion=self.snapshot==b'%PDF-edited-snapshot'
                def wait(self):done.wait(5)
            try:
                with patch.object(sys,'_MEIPASS',str(root),create=True),patch.object(pdf_workbench.subprocess,'Popen',side_effect=Process) as launch:
                    pdf_workbench.launch_workbench(b'%PDF-edited-snapshot','document.pdf')
                    source=inputs[0];self.assertNotEqual(source,original)
                    self.assertEqual(source.read_bytes(),b'%PDF-edited-snapshot')
                    self.assertEqual(original.read_bytes(),b'original')
                    self.assertEqual(Path(launch.call_args.args[0][0]),helper)
                    done.set()
                    for _ in range(100):
                        if not source.exists():break
                        time.sleep(.01)
                    self.assertFalse(source.exists())
            finally:done.set()
    def test_missing_component_does_not_create_a_copy(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(sys,'_MEIPASS',folder,create=True):
            with self.assertRaisesRegex(RuntimeError,'PDF 작업실 모듈'):
                pdf_workbench.launch_workbench(b'%PDF-test','test.pdf')

if __name__=='__main__':unittest.main()
