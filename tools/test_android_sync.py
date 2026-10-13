import json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import android_sync as sync
HOME=Path(__file__).resolve().parents[1]
class SyncTests(unittest.TestCase):
 def test_version_no_ambiguity(self):
  self.assertEqual(sync.version_code('1.4.2'),10402)
  for alias in ['1.5','1.5.0.','v1.5.0','  V01.05.00  ','1.5.']:
   self.assertEqual(sync.normalize_version(alias),'1.5.0')
   self.assertEqual(sync.version_code(alias),10500)
  for bad in ['1.4.100','bad','1.3.0','1.5..','1.5.0.1','1..5','-1.5.0','1.5 beta','1,5','999999999.0.0']:
   with self.assertRaises(ValueError):sync.version_code(bad)
 def test_suggestion_avoids_app_only_tag(self):
  self.assertEqual(sync.suggested_version({'patch_code':10402,'app_code':10501}),'1.5.2')
  self.assertEqual(sync.suggested_version({'patch_code':10599,'app_code':10501}),'1.6.0')
 def test_used_app_only_tag_has_specific_error(self):
  with patch.object(sync,'fetch',return_value=b'{}'):
   with self.assertRaisesRegex(ValueError,'đã có release'):sync.validate_new_version('1.5.2',{'patch_code':10402,'patch_version':'1.4.2','app_code':10501})
 def test_older_version_rejected_before_tag_request(self):
  with patch.object(sync,'fetch') as fetch:
   with self.assertRaisesRegex(ValueError,'cao hơn'):sync.validate_new_version('1.4.2',{'patch_code':10402,'patch_version':'1.4.2','app_code':10501})
   fetch.assert_not_called()
 def test_unused_alias_is_normalized_for_filename_tag_and_code(self):
  import urllib.error
  with patch.object(sync,'fetch',side_effect=urllib.error.HTTPError('https://fixture',404,'missing',{},None)):
   self.assertEqual(sync.validate_new_version('1.5.2.',{'patch_code':10402,'patch_version':'1.4.2','app_code':10501}),('1.5.2',10502))
 @unittest.skipUnless((HOME/'czn_android_patcher/.signing/update-private.pk8').is_file(),'Khóa ký CZN chỉ có trên máy phát hành; không đưa vào CI.')
 def test_signature_roundtrip_and_altered_metadata_rejected(self):
  with tempfile.TemporaryDirectory() as temp:
   raw=Path(temp)/'channel.json';raw.write_text('{"schema":1,"notice":{"enabled":true,"body":"Thử thông báo"}}',encoding='utf-8')
   envelope=sync.sign_metadata(raw,HOME/'czn_android_patcher/.signing/update-private.pk8')
   self.assertEqual(sync.verify_metadata(envelope),json.loads(raw.read_text('utf-8')))
   value=json.loads(envelope);value['signed']=value['signed'][:-5]+'AAAAA'
   with self.assertRaises((RuntimeError,ValueError)):sync.verify_metadata(json.dumps(value).encode())
 def test_changed_preview_never_accesses_github(self):
  with tempfile.TemporaryDirectory() as temp:
   out=Path(temp);preview={'directory':str(out),'version':'1.4.2'};(out/'SYNC_PREVIEW.json').write_text(json.dumps(preview))
   preview['version']='1.4.3'
   with patch.object(sync,'api') as api:
    with self.assertRaises(RuntimeError):sync.publish(preview)
    api.assert_not_called()
 def test_changed_asset_never_accesses_github(self):
  with tempfile.TemporaryDirectory() as temp:
   out=Path(temp);names=['CZN_Android_v1.4.2.cznpatch','channel.json','HUONG_DAN_ANDROID.txt','SHA256SUMS.txt'];hashes={}
   for name in names:(out/name).write_bytes(b'original');hashes[name]=sync.digest(out/name)
   preview={'directory':str(out),'version':'1.4.2','asset_hashes':hashes};(out/'SYNC_PREVIEW.json').write_text(json.dumps(preview));(out/names[0]).write_bytes(b'changed')
   with patch.object(sync,'api') as api:
    with self.assertRaises(RuntimeError):sync.publish(preview)
    api.assert_not_called()
 def test_source_only_prepare_uses_builder_not_live_game(self):
  # Real fixture package is checked separately. This verifies failure guard runs before build.
  with tempfile.TemporaryDirectory() as temp:
   from unittest.mock import Mock
   inst=Mock();inst.data=Path(temp);(inst.data/'journal.json').write_text('{}')
   with self.assertRaises(RuntimeError):sync.prepare(inst,'1.4.2','notice','body','key')
   inst.build.assert_not_called()
 def test_retry_uses_saved_id_not_draft_tag_endpoint(self):
  with tempfile.TemporaryDirectory() as temp:
   out=Path(temp);(out/'PUBLISH_STATE.json').write_text('{"release_id":123}')
   with patch.object(sync,'api',return_value={'id':123,'draft':True,'tag_name':'android-v1.4.2'}) as api:
    self.assertEqual(sync.draft_for('fixture',{'tag':'android-v1.4.2'},out)['id'],123)
    api.assert_called_once_with('fixture','/releases/123')
 def test_retry_rejects_a_different_tag_before_upload(self):
  with tempfile.TemporaryDirectory() as temp:
   out=Path(temp);(out/'PUBLISH_STATE.json').write_text('{"release_id":123}')
   with patch.object(sync,'api',return_value={'id':123,'draft':True,'tag_name':'unrelated'}):
    with self.assertRaises(RuntimeError):sync.draft_for('fixture',{'tag':'android-v1.4.2'},out)
if __name__=='__main__':unittest.main()
