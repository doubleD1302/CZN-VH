"""ReplaceFileW retry regression tests using fake Windows API and temp files."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import types
import unittest
from unittest.mock import MagicMock, patch

from installer_core import atomic_bytes

HOME = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'nt', 'ReplaceFileW branch requires Windows')
class AtomicRetryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='czn-atomic-retry-test-')
        self.root = Path(self.temp.name)
        self.target = self.root / 'resource.bin'
        self.before = b'Original resource bytes'
        self.after = b'New validated resource bytes'
        self.target.write_bytes(self.before)
        self.current_error = 0
        self.paths = []

    def tearDown(self):
        self.temp.cleanup()

    def fake_api(self, errors):
        remaining = iter(errors)
        def replace(target, replacement, backup, flags, exclude, reserved):
            self.assertEqual(Path(target), self.target.resolve())
            self.assertIsNone(backup)
            self.assertEqual(flags, 0)
            self.assertIsNone(exclude)
            self.assertIsNone(reserved)
            replacement = Path(replacement)
            self.paths.append((str(target), str(replacement)))
            self.assertEqual(replacement.read_bytes(), self.after)
            error = next(remaining)
            self.current_error = error
            if error:
                # Transient errors leave BOTH names intact, as documented.
                self.assertTrue(replacement.exists())
                self.assertEqual(self.target.read_bytes(), self.before)
                return 0
            os.replace(replacement, self.target)
            return 1
        return types.SimpleNamespace(ReplaceFileW=MagicMock(side_effect=replace))

    def invoke(self, api, sleeper=None):
        sleeper = sleeper if sleeper is not None else MagicMock()
        with patch('ctypes.WinDLL', return_value=api), \
             patch('ctypes.get_last_error', side_effect=lambda:self.current_error), \
             patch('installer_core.time.sleep', sleeper):
            atomic_bytes(self.target, self.after)
        return sleeper

    def assert_clean(self):
        self.assertEqual(list(self.root.glob('*.tmp')), [])
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['resource.bin'])

    def test_01_transient_1175_then_success_same_names(self):
        api = self.fake_api([1175, 0])
        sleeper = self.invoke(api)
        self.assertEqual(api.ReplaceFileW.call_count, 2)
        self.assertEqual(len(set(self.paths)), 1)
        sleeper.assert_called_once_with(0.25)
        self.assertEqual(self.target.read_bytes(), self.after)
        self.assert_clean()

    def test_02_persistent_1175_exhausted_with_filename(self):
        api = self.fake_api([1175] * 8)
        sleeper = MagicMock()
        with self.assertRaises(OSError) as raised:
            self.invoke(api, sleeper)
        self.assertEqual(raised.exception.winerror, 1175)
        self.assertEqual(raised.exception.filename, str(self.target.resolve()))
        self.assertIn(self.target.name, str(raised.exception))
        self.assertEqual(api.ReplaceFileW.call_count, 8)
        self.assertEqual(len(set(self.paths)), 1)
        self.assertEqual(sleeper.call_count, 7)
        self.assertTrue(all(c.args == (0.25,) for c in sleeper.call_args_list))
        self.assertEqual(self.target.read_bytes(), self.before)
        self.assert_clean()

    def test_03_target_mtime_changes_abort_before_retry(self):
        api = self.fake_api([1175, 0])
        def change_target(_seconds):
            original = self.target.stat()
            os.utime(self.target, ns=(original.st_atime_ns, original.st_mtime_ns + 1000000000))
        with self.assertRaises((RuntimeError, OSError)):
            self.invoke(api, change_target)
        self.assertEqual(api.ReplaceFileW.call_count, 1)
        self.assertEqual(self.target.read_bytes(), self.before)
        self.assert_clean()

    def test_04_access_denied_5_is_not_retried(self):
        api = self.fake_api([5, 0])
        sleeper = MagicMock()
        with self.assertRaises(OSError) as raised:
            self.invoke(api, sleeper)
        self.assertEqual(raised.exception.winerror, 5)
        self.assertEqual(raised.exception.filename, str(self.target.resolve()))
        self.assertIn(self.target.name, str(raised.exception))
        self.assertEqual(api.ReplaceFileW.call_count, 1)
        sleeper.assert_not_called()
        self.assertEqual(self.target.read_bytes(), self.before)
        self.assert_clean()

    def test_05_sharing_and_lock_errors_retry(self):
        for code in (32, 33):
            with self.subTest(winerror=code):
                self.target.write_bytes(self.before)
                api = self.fake_api([code, 0])
                sleeper = self.invoke(api)
                self.assertEqual(api.ReplaceFileW.call_count, 2)
                sleeper.assert_called_once_with(0.25)
                self.assertEqual(self.target.read_bytes(), self.after)
                self.assert_clean()


if __name__ == '__main__':
    started = time.monotonic()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AtomicRetryTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = dict(schema=1, tests_run=result.testsRun, passed=result.wasSuccessful(),
        elapsed_seconds=round(time.monotonic()-started, 3), live_game_written=False,
        methodology='Mock ReplaceFileW; only tempfile target/replacement names are written; no OS privilege or live resource writes.',
        failures=[dict(test=str(t), traceback=v) for t,v in result.failures],
        errors=[dict(test=str(t), traceback=v) for t,v in result.errors],
        tools_sha256={name:hashlib.sha256((HOME/'tools'/name).read_bytes()).hexdigest()
                      for name in ('installer_core.py','test_atomic_retry.py')})
    # Avoid using the function under test to write its own evidence.
    path = HOME/'data/reports/CHUONG_1/TEST_ATOMIC_RETRY_REPORT.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    raise SystemExit(0 if result.wasSuccessful() else 1)
