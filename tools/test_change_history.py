import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import change_history as history
import android_sync as sync
from installer_core import write_json

class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name);self.catalog=self.home/'data/translations.json'
        self.channel={'patch_version':'1.4.2','patch_sha256':'fixture-sha','patch_code':10402,'patch_size':1}
    def row(self,value='Bản dịch',identity='id'):
        return {'id':identity,'source_ja':'日本語','text_vi':value,'category':'Giao diện'}
    def save(self,*rows):
        write_json(self.catalog,{'schema':1,'entries':list(rows)})
    def baseline(self,value='日本語',snapshot=None):
        history.acknowledge(self.home,snapshot or {'values':{'text':{'id':value},'story':{}}},self.channel,
                            {'public_verified':True,'bundle_sha256':'fixture-sha'})
    def count_events(self):
        db=history.connect(self.home)
        try:return db.execute('SELECT COUNT(*) FROM events').fetchone()[0]
        finally:db.close()
    def test_existing_inventory_does_not_invent_completion_history(self):
        self.catalog.parent.mkdir();self.catalog.write_text(json.dumps({'entries':[self.row()]}),encoding='utf-8')
        history.capture(self.home)
        self.assertEqual(self.count_events(),0)
        self.baseline()
        self.assertEqual(len(history.changes_since_publication(self.home)['changes']),1)
    def test_import_records_before_after_hash_once(self):
        self.save(self.row());self.save(self.row('Sửa bản dịch'))
        history.capture(self.home);history.capture(self.home)
        self.assertEqual(self.count_events(),2)
        db=history.connect(self.home)
        try:
            before,after,bh,ah=db.execute('SELECT before_row,after_row,before_sha256,after_sha256 FROM events ORDER BY sequence DESC LIMIT 1').fetchone()
            self.assertEqual(json.loads(before)['text_vi'],'Bản dịch')
            self.assertEqual(json.loads(after)['text_vi'],'Sửa bản dịch')
            self.assertEqual(bh,history.sha(before.encode()));self.assertEqual(ah,history.sha(after.encode()))
        finally:db.close()
    def test_direct_catalog_edits_are_captured_next_scan(self):
        self.save(self.row());self.catalog.write_text(json.dumps({'entries':[self.row('Agent sửa trực tiếp')]}),encoding='utf-8')
        self.assertEqual(history.capture(self.home)['text'],1)
        self.assertEqual(self.count_events(),2)
    def test_failed_write_keeps_old_catalog_and_never_logs_new_completion(self):
        self.save(self.row())
        def fail(path,data):raise OSError('disk full')
        with self.assertRaises(OSError):history.tracked_write(self.catalog,json.dumps({'entries':[self.row('Không ghi được')]}).encode(),fail)
        self.assertEqual(self.count_events(),1)
        self.assertEqual(json.loads(self.catalog.read_text('utf-8'))['entries'][0]['text_vi'],'Bản dịch')
    def test_duplicate_proposal_fails_before_replacing_catalog(self):
        self.save(self.row());before=self.catalog.read_bytes()
        with self.assertRaises(ValueError):self.save(self.row('Sai'),self.row('Sai'))
        self.assertEqual(self.catalog.read_bytes(),before)
        self.assertEqual(self.count_events(),1)
    def test_post_write_interruption_recovers_from_old_observation(self):
        self.save(self.row())
        # The process stops after atomic catalog write but before history finalization.
        self.catalog.write_text(json.dumps({'entries':[self.row('Khôi phục dấu vết')]}),encoding='utf-8')
        history.capture(self.home)
        self.assertEqual(self.count_events(),2)
    def test_failed_or_draft_publication_never_clears_pending(self):
        self.save(self.row());self.baseline()
        with self.assertRaises(ValueError):history.acknowledge(self.home,{'values':{'text':{'id':'Bản dịch'},'story':{}}},self.channel,{'public_verified':False,'bundle_sha256':'fixture-sha'})
        self.assertEqual(len(history.changes_since_publication(self.home)['changes']),1)
    def test_only_frozen_bundle_is_acknowledged_later_catalog_edit_stays_pending(self):
        self.save(self.row());self.baseline()
        frozen={'values':{'text':{'id':'Bản dịch'},'story':{}},'eligible':{'text':['id'],'story':[]}}
        self.save(self.row('Sửa sau khi dựng'))
        self.baseline(snapshot=frozen)
        changes=history.changes_since_publication(self.home)['changes']
        self.assertEqual(len(changes),1);self.assertEqual(changes[0]['before'],'Bản dịch');self.assertEqual(changes[0]['after'],'Sửa sau khi dựng')
    def test_unapplied_and_rejected_rows_not_in_release_notice(self):
        self.save(self.row(),self.row('Bản sai nguồn','rejected'));self.baseline()
        frozen={'values':{'text':{'id':'Bản dịch','rejected':'JP của game mới'},'story':{}},'eligible':{'text':['id'],'story':[]}}
        result=history.changes_since_publication(self.home,frozen)
        self.assertEqual([r['id'] for r in result['changes']],['id'])
        self.baseline(snapshot=frozen)
        self.assertEqual([r['id'] for r in history.changes_since_publication(self.home)['changes']],['rejected'])
    def test_removal_is_announced_only_if_payload_reverts_actual_published_translation(self):
        self.save(self.row());self.baseline('Bản dịch');self.save()
        frozen={'values':{'text':{'id':'日本語'},'story':{}},'eligible':{'text':[],'story':[]}}
        self.assertEqual(history.changes_since_publication(self.home,frozen)['changes'][0]['kind'],'removed')
        frozen['values']['text']['id']='JP mới'
        self.assertEqual(history.changes_since_publication(self.home,frozen)['changes'],[])
    def test_no_baseline_does_not_claim_all_rows_are_new(self):
        self.save(self.row())
        with self.assertRaisesRegex(RuntimeError,'gói nền'):history.changes_since_publication(self.home)
    def test_app_only_update_does_not_consume_pending_catalog(self):
        self.save(self.row());self.baseline()
        from publish_android_release import app_only_channel
        baseline=dict(self.channel,schema=1,type='channel',app_code=10501)
        result=app_only_channel(baseline,'1.5.2',10502,'https://fixture',123,'apk-sha')
        self.assertEqual(result['patch_sha256'],baseline['patch_sha256'])
        self.assertEqual(len(history.changes_since_publication(self.home)['changes']),1)
    def test_public_verification_failure_does_not_acknowledge(self):
        self.save(self.row());self.baseline()
        preview={'directory':str(self.home),'tag':'android-v1.5.2'}
        with patch.object(sync,'check_updates',return_value={'patch_sha256':'different'}):
            with self.assertRaises(RuntimeError):sync.finalize_publication(preview,self.channel,42,'fixture')
        self.assertEqual(len(history.changes_since_publication(self.home)['changes']),1)
    def test_evidence_receipt_records_real_hash_even_when_no_new_edit(self):
        self.save(self.row());proof=self.home/'audit.json';proof.write_text('{}')
        history.capture(self.home,'Hoàn tất đợt A',[proof])
        db=history.connect(self.home)
        try:
            contexts=[json.loads(r[0]) for r in db.execute('SELECT context FROM captures')]
            self.assertTrue(any(c.get('evidence',[{}])[0].get('sha256')==history.sha(b'{}') for c in contexts if c.get('evidence')))
        finally:db.close()
    def publication_fixture(self):
        self.save(self.row());self.baseline()
        out=self.home/'release';out.mkdir()
        names=['CZN_Android_v1.5.2.cznpatch','channel.json','HUONG_DAN_ANDROID.txt','SHA256SUMS.txt']
        for name in names:(out/name).write_bytes(b'fixture')
        frozen={'values':{'text':{'id':'Bản dịch'},'story':{}},'eligible':{'text':['id'],'story':[]}}
        (out/'TRANSLATION_SNAPSHOT.json').write_text(json.dumps(frozen),encoding='utf-8')
        (out/'UNPUBLISHED_CHANGES.json').write_text('{}')
        channel=dict(self.channel,patch_version='1.5.2',patch_code=10502,patch_sha256=sync.digest(out/names[0]))
        preview={'home':str(self.home),'directory':str(out),'version':'1.5.2','code':10502,'tag':'android-v1.5.2',
                 'asset_hashes':{n:sync.digest(out/n) for n in names},'app':{},
                 'translation_snapshot_sha256':sync.digest(out/'TRANSLATION_SNAPSHOT.json'),
                 'unpublished_changes_sha256':sync.digest(out/'UNPUBLISHED_CHANGES.json')}
        release={'id':42,'tag_name':preview['tag'],'draft':False,'prerelease':False,'html_url':'https://fixture/release',
                 'assets':[{'name':n,'size':(out/n).stat().st_size,'digest':'sha256:'+h} for n,h in preview['asset_hashes'].items()]}
        (out/'SYNC_PREVIEW.json').write_text(json.dumps(preview))
        return out,channel,preview,release
    def test_asset_verification_failure_keeps_pending(self):
        out,channel,preview,release=self.publication_fixture()
        release['assets'][0]['digest']='sha256:wrong'
        with patch.object(sync,'check_updates',return_value=channel),patch.object(sync,'api',return_value=release):
            with self.assertRaises(RuntimeError):sync.finalize_publication(preview,channel,42,'fixture')
        self.assertEqual(len(history.changes_since_publication(self.home)['changes']),1)
    def test_retry_promoted_release_verifies_without_second_upload_and_keeps_later_edit(self):
        out,channel,preview,release=self.publication_fixture()
        (out/'PUBLISH_STATE.json').write_text(json.dumps({'release_id':42,'url':release['html_url'],'state':'uploading'}))
        self.save(self.row('Sửa tiếp sau khi dựng'))
        with patch.object(sync,'check_updates',return_value=channel),patch.object(sync,'verify_metadata',return_value=channel),patch.object(sync,'credentials',return_value='fixture'),patch.object(sync,'api',return_value=release) as api:
            result=sync.publish(preview)
            self.assertEqual(result['state'],'verified')
            api.assert_called_once_with('fixture','/releases/42')
        pending=history.changes_since_publication(self.home)['changes']
        self.assertEqual(len(pending),1);self.assertEqual(pending[0]['after'],'Sửa tiếp sau khi dựng')

if __name__=='__main__':unittest.main()
