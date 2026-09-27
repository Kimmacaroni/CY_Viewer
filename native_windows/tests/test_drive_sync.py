import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from drive_sync import Drive, merge_reading, Conflict

class DriveTests(unittest.TestCase):
    def test_merge_preserves_other_device_and_removal(self):
        a={'marks':{'2':{'on':True,'at':10},'3':{'on':False,'at':30}},'page':{'n':8,'at':40}}
        b={'marks':{'4':{'on':True,'at':20},'3':{'on':True,'at':20}},'page':{'n':2,'at':20}}
        merged=merge_reading(a,b)
        self.assertEqual(merged,merge_reading(b,a))
        self.assertFalse(merged['marks']['3']['on'])
        self.assertEqual(merged['page']['n'],8)

    def test_existing_pdf_never_reuploaded(self):
        drive=Drive(); calls=[]
        def request(method,path,**kw):
            calls.append((method,path,kw))
            return {'files':[{'id':'f','name':'a.pdf'}]} if method=='GET' else {}
        drive.request=request
        self.assertEqual(drive.open('a.pdf',b'%PDF')['id'],'f')
        self.assertFalse(any('/upload/' in p for _,p,_ in calls))
        self.assertIn('cyHash',calls[0][2]['query']['q'])

    def test_hash_mismatch_rejected(self):
        drive=Drive();drive.request=lambda *a,**k:b'changed'
        with self.assertRaises(RuntimeError):drive.download({'id':'f','appProperties':{'cyHash':'old'}})

    def test_recent_requests_only_five(self):
        drive=Drive();seen=[]
        def request(*a,**kw):seen.append(kw);return {'files':[]}
        drive.request=request;drive.recent()
        self.assertEqual(seen[0]['query']['pageSize'],'5')

    def test_conflict_retried_and_failed_delta_retained(self):
        drive=Drive();calls=[]
        def request(method,*a,**kw):
            if method=='GET':return {'id':'f','description':'{}','_etag':'v1'}
            calls.append(kw)
            raise Conflict()
        drive.request=request
        with self.assertRaises(RuntimeError):drive.save({'id':'f'},{'marks':{'2':{'on':True,'at':20}}})
        self.assertEqual(len(calls),3)
        self.assertTrue(drive.pending['f']['marks']['2']['on'])
        self.assertEqual(calls[0]['etag'],'v1')
