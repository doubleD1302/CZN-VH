import json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import app_package as app
import android_sync as sync

class AppPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name)
        self.source=self.home/'czn_android_patcher'
        for folder in ['lib','assets','android/app/src/main/res','android/app/src/main/assets']:(self.source/folder).mkdir(parents=True,exist_ok=True)
        (self.source/'pubspec.yaml').write_text('version: 1.6.7+10607')
        (self.source/'lib/main.dart').write_text('app')
        (self.source/'assets/background.png').write_bytes(b'image')
        (self.source/'android/app/src/main/res/icon.xml').write_text('icon')
    def test_each_ui_icon_native_or_dependency_change_invalidates_build(self):
        evidence={'full_app_update':True,'source':app.source_snapshot(self.source)}
        app.assert_current_source(self.home,evidence)
        for name in ['lib/main.dart','assets/background.png','android/app/src/main/res/icon.xml','pubspec.yaml']:
            path=self.source/name;old=path.read_bytes();path.write_bytes(old+b'changed')
            with self.assertRaisesRegex(RuntimeError,'đã đổi'):app.assert_current_source(self.home,evidence)
            path.write_bytes(old)
            app.assert_current_source(self.home,evidence)
    def test_private_keys_and_build_outputs_do_not_enter_snapshot(self):
        first=app.source_snapshot(self.source)
        for name in ['.signing/private.pk8','build/outputs.apk','android/local.properties']:
            path=self.source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'private')
        self.assertEqual(first,app.source_snapshot(self.source))
    def test_missing_source_does_not_allow_an_old_apk(self):
        with self.assertRaisesRegex(RuntimeError,'mã nguồn'):app.app_root(self.home/'missing')
    def test_release_version_must_advance_app_as_well_as_translation(self):
        with patch.object(sync,'fetch') as fetch:
            with self.assertRaises(ValueError):sync.validate_new_version('1.6.7',{'app_code':10607,'patch_code':10605,'patch_version':'1.6.5'})
            fetch.assert_not_called()
    def test_legacy_patch_only_preparation_is_blocked_before_network(self):
        preview={'schema':1,'version':'1.6.8','directory':str(self.home)}
        (self.home/'SYNC_PREVIEW.json').write_text(json.dumps(preview))
        with patch.object(sync,'api') as api,patch.object(sync,'check_updates') as check:
            with self.assertRaisesRegex(RuntimeError,'thiếu APK'):sync.publish(preview)
            api.assert_not_called();check.assert_not_called()

if __name__=='__main__':unittest.main()
