"""Execute the constructor runner guard; not Apple UIKit execution proof."""
import contextlib
import io
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


class SettingsConstructionRunnerContracts(unittest.TestCase):
    def constructor_launch_program(self):
        script = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        matches = re.findall(r'python3 - "\$DEVICE" "\$bundle" "\$mode" "\$marker" "\$RESULTS" <<\'PY\'\n(.*?)\nPY', script, re.S)
        self.assertEqual(len(matches), 1)
        return compile(matches[0], 'actual-constructor-runner', 'exec')

    def test_actual_constructor_runner_keeps_timeout_output_without_accepting_it(self):
        program = self.constructor_launch_program()
        marker = 'BASELINE_EXPECTED_FAILURE'
        for partial in ('SETTINGS_CHECKPOINT: entered\n' + marker + '\n',
                        b'SETTINGS_CHECKPOINT: entered\n', None):
            with self.subTest(partial=partial), tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
                root = Path(directory)
                results = root / 'results.txt'
                output = io.StringIO()
                timeout = subprocess.TimeoutExpired(['xcrun', 'simctl', 'launch'], 120, output=partial)
                diagnostics = subprocess.CompletedProcess(['log'], 0, 'ACTUAL_TEST_DIAGNOSTICS_READ\n')
                with mock.patch('sys.argv', ['-', 'owned-device', 'owned-bundle', '--expect-legacy-failure', marker, str(results)]), \
                     mock.patch('subprocess.run', side_effect=[timeout, diagnostics]) as run, \
                     mock.patch.object(Path, 'home', return_value=root), contextlib.redirect_stdout(output), \
                     self.assertRaises((SystemExit, subprocess.TimeoutExpired)) as stopped:
                    exec(program, {'__name__': '__main__'})
                exception = stopped.exception
                if isinstance(exception, subprocess.TimeoutExpired):
                    self.fail('actual runner discarded partial timeout output before diagnostic recovery')
                self.assertNotEqual(exception.code, 0)
                text = output.getvalue()
                self.assertIn('SETTINGS_CONSTRUCTION_LAUNCH_TIMEOUT: 120 seconds', text)
                self.assertIn('simctl launch exit: 124', text)
                self.assertIn('ACTUAL_TEST_DIAGNOSTICS_READ', text)
                if partial:
                    self.assertIn('SETTINGS_CHECKPOINT: entered', text)
                self.assertFalse(results.exists(), 'timeout must never append a successful result')
                self.assertEqual(run.call_count, 2)
                self.assertEqual(run.call_args_list[0].args[0], ['xcrun', 'simctl', 'launch', '--console',
                    '--terminate-running-process', 'owned-device', 'owned-bundle', '--expect-legacy-failure'])
                self.assertEqual(run.call_args_list[0].kwargs['timeout'], 120)

    def test_actual_constructor_runner_still_requires_transport_and_case_marker(self):
        program = self.constructor_launch_program()
        marker = 'BASELINE_EXPECTED_FAILURE'
        for status, console, accepted in [(0, marker + '\n', True), (0, 'transport only\n', False),
                                          (1, marker + '\n', False)]:
            with self.subTest(status=status, console=console), tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
                root = Path(directory)
                results = root / 'results.txt'
                launch = subprocess.CompletedProcess(['launch'], status, console)
                diagnostics = subprocess.CompletedProcess(['log'], 0, 'diagnostics\n')
                with mock.patch('sys.argv', ['-', 'owned-device', 'owned-bundle', '--expect-legacy-failure', marker, str(results)]), \
                     mock.patch('subprocess.run', side_effect=[launch, diagnostics]), \
                     mock.patch.object(Path, 'home', return_value=root), contextlib.redirect_stdout(io.StringIO()):
                    if accepted:
                        exec(program, {'__name__': '__main__'})
                        self.assertEqual(results.read_text(), console + '\n')
                    else:
                        with self.assertRaises(SystemExit):
                            exec(program, {'__name__': '__main__'})
                        self.assertFalse(results.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
