"""Execute the cloud driver's exact native-harness completion-marker gate."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeAppDriverTests(unittest.TestCase):
    def test_zero_exit_without_marker_and_nonzero_with_marker_are_rejected(self):
        script = (ROOT / 'ci/open-app-smoke.sh').read_text()
        start = 'python3 - "$WORK/current-native-tests" "$RUNNER_TEMP/NATIVE_APP_TESTS.txt" <<\'PY\'\n'
        self.assertIn(start, script)
        driver = script.split(start, 1)[1].split('\nPY', 1)[0]
        with tempfile.TemporaryDirectory(prefix='taplock-native-gate-') as directory:
            root = Path(directory)
            runner, report = root / 'runner', root / 'result.txt'
            for output, status, success in [('', 0, False),
                    ('NATIVE_APP_RUNTIME_PASS: fixture completed', 1, False),
                    ('NATIVE_APP_RUNTIME_PASS: fixture completed', 0, True)]:
                with self.subTest(output=output, status=status):
                    runner.write_text('#!/usr/bin/env python3\n'
                                      + 'print(' + repr(output) + ')\n'
                                      + 'raise SystemExit(' + str(status) + ')\n')
                    runner.chmod(0o700)
                    if report.exists():
                        report.unlink()
                    result = subprocess.run([sys.executable, '-c', driver, str(runner), str(report)],
                                            capture_output=True, text=True, timeout=10,
                                            env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
                    self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
                    self.assertEqual(report.exists(), success)
                    if success:
                        self.assertIn('NATIVE_APP_RUNTIME_PASS: fixture completed', report.read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
