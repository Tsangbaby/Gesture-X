"""Diagnostic-runner guard tests, not evidence of Apple/UIKit execution."""
import hashlib
import json
import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'a' * 40
TOKEN = 'b' * 32


class SettingsStartupDiagnosticContracts(unittest.TestCase):
    def module(self):
        path = ROOT / 'ci/settings_startup_diagnostic.py'
        self.assertTrue(path.is_file(), 'Missing bounded Settings startup diagnostic')
        return runpy.run_path(str(path))

    def events(self, kind):
        phases = {
            'control': ('native-constructor', 'main-entered', 'before-UIApplicationMain',
                        'didFinishLaunching', 'control-ui-attached', 'control-pass'),
            'baseline': ('native-constructor', 'main-entered', 'before-UIApplicationMain',
                         'didFinishLaunching', 'before-legacy-checks', 'before-TLConstructDetail',
                         'after-TLConstructDetail', 'baseline-expected-failure'),
        }[kind]
        return [dict(schemaVersion=1, source_commit=SOURCE, run_token=TOKEN,
                     seq=i, phase=phase, pid=123, monotonic_ns=i)
                for i, phase in enumerate(phases, 1)]

    def inputs(self, kind):
        events = self.events(kind)
        ledger = ''.join(json.dumps(row) + '\n' for row in events)
        console = ''.join('SETTINGS_STARTUP_EVENT: ' + json.dumps(row) + '\n' for row in events)
        console += ('SETTINGS_STARTUP_CONTROL_PASS\n' if kind == 'control' else
                    'BASELINE_EXPECTED_FAILURE: -[TapLockSettingsController initForContentSize:]: unrecognized selector\n')
        return console, ledger

    def test_00_owned_observations_do_not_override_transport_or_terminal_failure(self):
        observe = self.module()['observe_case']
        for kind in ('control', 'baseline'):
            console, ledger = self.inputs(kind)
            good = observe(kind, 0, console, ledger, SOURCE, TOKEN)
            self.assertTrue(good['completed'])
            self.assertEqual(good['last_owned_phase'], self.events(kind)[-1]['phase'])
            for status, stdout, filetext in (
                (124, console, ledger), (1, console, ledger), (0, '', ledger),
                (0, console, ''), (0, console + console, ledger),
                (0, console + 'SETTINGS_CONSTRUCTION_FAIL: unrelated failure\n', ledger),
                (0, console, ledger.replace(TOKEN, 'c' * 32)),
                (0, console, ledger.replace(SOURCE, 'c' * 40)),
                (0, console, ledger + ledger),
            ):
                with self.subTest(kind=kind, status=status, console_bytes=len(stdout)):
                    result = observe(kind, status, stdout, filetext, SOURCE, TOKEN)
                    self.assertFalse(result['completed'])
            missing = observe(kind, 124, '', '', SOURCE, TOKEN)
            self.assertIsNone(missing['last_owned_phase'])
            self.assertIn('not proof', missing['limit'])

    def test_instrumentation_is_reversible_and_keeps_all_historical_assertions(self):
        module = self.module()
        self.assertIn('instrument_harness', module, 'Missing exact reversible instrumentation')
        original = (ROOT / 'Tests/SettingsConstructionApp.swift').read_text()
        instrumented, hunks = module['instrument_harness'](original)
        self.assertNotIn('@main\n', instrumented)
        self.assertIn('TLSDRecord("before-TLConstructDetail")', instrumented)
        self.assertIn('TLSDRecord("after-TLConstructDetail")', instrumented)
        self.assertIn('TLSDRecord("baseline-expected-failure")', instrumented)
        restored = instrumented
        for before, after in reversed(hunks):
            if after:
                self.assertEqual(restored.count(after), 1)
                restored = restored.replace(after, before, 1)
            else:
                restored = restored.replace('final class SettingsConstructionApp:',
                                            '@main\nfinal class SettingsConstructionApp:', 1)
        self.assertEqual(restored, original)
        with self.assertRaises(ValueError):
            module['instrument_harness'](original + '\n// unauthorized drift\n')

    def test_native_probe_actually_writes_identical_owned_json_to_both_channels(self):
        module = self.module()
        self.assertIn('NATIVE_PROBE', module, 'Missing executable native checkpoint probe')
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            root = Path(directory)
            source = root / 'probe.c'
            source.write_text(module['NATIVE_PROBE'] + '\nint main(void) { TLSDRecord("main-entered"); return 0; }\n')
            binary = root / 'probe'
            subprocess.run(['cc', '-std=c11', '-D_POSIX_C_SOURCE=200809L', str(source), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=30)
            home = root / 'valid-home'
            home.mkdir()
            env = dict(os.environ, HOME=str(home), SETTINGS_DIAGNOSTIC_SOURCE=SOURCE,
                       SETTINGS_DIAGNOSTIC_TOKEN=TOKEN)
            completed = subprocess.run([str(binary)], env=env, check=True, capture_output=True, text=True, timeout=5)
            file = home / 'Documents/SettingsStartup.jsonl'
            records = module['owned_events'](file.read_text(), SOURCE, TOKEN)
            console_records = module['owned_events']('\n'.join(
                row[len(module['PREFIX']):] for row in completed.stdout.splitlines()), SOURCE, TOKEN)
            self.assertEqual(records, console_records)
            self.assertEqual([row['phase'] for row in records], ['native-constructor', 'main-entered'])
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            badhome = root / 'bad-home'
            badhome.mkdir()
            env.update(HOME=str(badhome), SETTINGS_DIAGNOSTIC_TOKEN='invalid-token')
            rejected = subprocess.run([str(binary)], env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(rejected.stdout, '')
            self.assertIn('invalid identity', rejected.stderr)
            self.assertFalse((badhome / 'Documents/SettingsStartup.jsonl').exists())

    def test_launch_is_one_exact_console_transport_with_original_120_second_bound(self):
        module = self.module()
        self.assertIn('launch_once', module, 'Missing single-attempt launch boundary')
        recorder = mock.Mock()
        recorder.run.return_value = {'status': 124}
        env = dict(SIMCTL_CHILD_SETTINGS_DIAGNOSTIC_SOURCE=SOURCE,
                   SIMCTL_CHILD_SETTINGS_DIAGNOSTIC_TOKEN=TOKEN)
        result = module['launch_once'](recorder, 'baseline', 'owned-device',
                                       'com.tsangbaby.taplock.constructor-baseline',
                                       '--expect-legacy-failure', env)
        self.assertEqual(result['status'], 124)
        recorder.run.assert_called_once_with('baseline-launch', [
            'xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
            'owned-device', 'com.tsangbaby.taplock.constructor-baseline', '--expect-legacy-failure'],
            timeout=120, env=env)

    def test_real_command_timeout_retains_live_file_output_and_never_reports_success(self):
        module = self.module()
        self.assertIn('CommandRunner', module, 'Missing bounded output-preserving command runner')
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            runner = module['CommandRunner'](Path(directory))
            result = runner.run('timeout-unit', [sys.executable, '-u', '-c',
                'import time; print("REAL_BEFORE_TIMEOUT", flush=True); time.sleep(10)'], timeout=2)
            self.assertEqual(result['status'], 124)
            self.assertTrue(result['timed_out'])
            self.assertIn('REAL_BEFORE_TIMEOUT', result['stdout'])
            self.assertIn('REAL_BEFORE_TIMEOUT', Path(result['log']).read_text())
            recorded = json.loads((Path(directory) / 'commands.jsonl').read_text())
            self.assertEqual(recorded['status'], 124)

    def test_only_new_diagnostic_branch_can_run_and_original_build_gate_is_unchanged(self):
        path = ROOT / '.github/workflows/settings-startup-diagnostic.yml'
        self.assertTrue(path.is_file(), 'Missing isolated push-only diagnostic workflow')
        workflow = json.loads(path.read_text())
        self.assertEqual(workflow['on'], {'push': {'branches': ['ci/settings-startup-8271e08'],
            'paths': ['.github/workflows/settings-startup-diagnostic.yml',
                      'ci/settings_startup_diagnostic.py', 'Tests/SettingsStartupControl.swift',
                      'Tests/test_settings_startup_diagnostic.py']}})
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        self.assertEqual(set(workflow['jobs']), {'settings-startup-diagnostic'})
        job = workflow['jobs']['settings-startup-diagnostic']
        self.assertEqual(job['runs-on'], 'macos-15')
        self.assertLessEqual(job['timeout-minutes'], 12)
        self.assertEqual(job['env']['DEVELOPER_DIR'], '/Applications/Xcode_16.4.app/Contents/Developer')
        steps = job['steps']
        self.assertIn('python3 -B ci/settings_startup_diagnostic.py --execute',
                      '\n'.join(step.get('run', '') for step in steps))
        serialized = json.dumps(workflow)
        for forbidden in ('ci/build.sh', 'bottom-gesture', 'brew install', 'workflow_dispatch', 'continue-on-error'):
            self.assertNotIn(forbidden, serialized)
        upload = next(step for step in steps if step.get('uses', '').startswith('actions/upload-artifact@'))
        self.assertEqual(upload['if'], 'always()')
        self.assertEqual(upload['with']['if-no-files-found'], 'error')
        self.assertIn('${{ github.sha }}', upload['with']['name'])
        self.assertIn('${{ github.run_attempt }}', upload['with']['name'])
        frozen = {
            '.github/workflows/build.yml': '15366d667af8280858521de4a5b3cd977e5c2432b25ddd922f00f95bdb0d5057',
            'ci/settings-construction-smoke.sh': '6d3c4cc4af60fd198841631fffea7e91865eb301c440694be67db3a4da43e34d',
            'Tests/SettingsConstructionApp.swift': '43a8f1b497f7524f1196cc3ac0bdd4d240449a265f945d2e3530983be80a40d6',
            'Tests/SettingsConstructionFixture.m': 'eaddcd80b619b1c396778ccd92d15a9bee895d8ec6b63b3640da23c1c1d8c4b2',
            'Tests/SettingsConstructionFixture.h': '49c08931a133ab27ea2ecce84edcbe4002a8ff6188074011a5231caf4cb353f7',
        }
        for relative, digest in frozen.items():
            self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), digest, relative)


if __name__ == '__main__':
    unittest.main(verbosity=2)
