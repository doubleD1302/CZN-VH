import json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import android_sync as sync
HOME=Path(__file__).resolve().parents[1]
class SyncTests(unittest.TestCase):
 def test_version_no_ambiguity(self):
  self.assertEqual(sync.version_code('1.4.2'),10402)
  for bad in ['1.4','1.4.100','bad','1.3.0']:
   with self.assertRaises(ValueError):sync.version_code(bad)
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
if __name__=='__main__':unittest.main()
