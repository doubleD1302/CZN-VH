import unittest
from publish_android_release import app_only_channel

class AppOnlyReleaseTest(unittest.TestCase):
    def setUp(self):
        self.baseline = dict(schema=1,type='channel',patch_version='1.4.2',patch_code=10402,
            patch_url='https://example.com/old.cznpatch',patch_size=14197410,
            patch_sha256='a'*64,app_version='1.4.2',app_code=10402)
    def test_app_upgrade_retains_every_patch_field(self):
        result=app_only_channel(self.baseline,'1.5.1',10501,'https://example.com/new.apk',70000000,'b'*64)
        for key in self.baseline:
            if key.startswith('patch_'):self.assertEqual(result[key],self.baseline[key])
        self.assertEqual(result['app_code'],10501)
        self.assertEqual(self.baseline['app_code'],10402)
    def test_reject_equal_or_lower_app_versions(self):
        for code in [10402,10401]:
            with self.assertRaises(ValueError):
                app_only_channel(self.baseline,'1.4.2',code,'https://example.com/new.apk',1,'b'*64)
    def test_reject_unsigned_wrong_type_descriptor(self):
        for field,value in [('schema',2),('type','release')]:
            with self.assertRaises(ValueError):
                app_only_channel({**self.baseline,field:value},'1.5.1',10501,'https://example.com/new.apk',1,'b'*64)

if __name__ == '__main__':unittest.main()
