"""Diagnostic-runner guard tests, not evidence of Apple/UIKit execution."""
import hashlib
import json
import os
import runpy
import subprocess
import sys
import tempfile
import time
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
            compiled = subprocess.run(['cc', '-std=c11', '-D_POSIX_C_SOURCE=200809L',
                                       '-D_DARWIN_C_SOURCE=1', str(source), '-o', str(binary)],
                                      capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0,
                'Native host probe compiler failed:\n' + compiled.stdout + compiled.stderr)
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

    def test_native_probe_compiler_failure_surfaces_stderr_before_any_execution(self):
        failure = subprocess.CompletedProcess(['cc'], 2, '', 'COMPILER_STDERR_MUST_SURVIVE')
        with mock.patch('subprocess.run', return_value=failure) as compiler:
            try:
                self.test_native_probe_actually_writes_identical_owned_json_to_both_channels()
            except AssertionError as error:
                self.assertIn('COMPILER_STDERR_MUST_SURVIVE', str(error))
            except Exception:
                self.fail('native compiler failure was not surfaced before trying to execute the binary')
            else:
                self.fail('native compiler failure was accepted')
            self.assertEqual(compiler.call_count, 1)

    def test_native_host_probe_enables_darwin_extensions_without_removing_nofollow(self):
        failure = subprocess.CompletedProcess(['cc'], 2, '', 'EXPECTED_COMPILE_STOP')
        with mock.patch('subprocess.run', return_value=failure) as compiler:
            with self.assertRaisesRegex(AssertionError, 'EXPECTED_COMPILE_STOP'):
                self.test_native_probe_actually_writes_identical_owned_json_to_both_channels()
        self.assertEqual(compiler.call_count, 1)
        arguments = compiler.call_args.args[0]
        self.assertIn('-D_DARWIN_C_SOURCE=1', arguments)
        self.assertIn('-D_POSIX_C_SOURCE=200809L', arguments)
        native_open = self.module()['NATIVE_PROBE'].split('int fd = open(', 1)[1].split(';', 1)[0]
        self.assertIn('O_NOFOLLOW', native_open)
        self.assertIn('O_CLOEXEC', native_open)

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

    def test_live_wait_probe_runs_before_timeout_without_changing_command_verdict(self):
        module = self.module()
        self.assertIn('wait_probe', module['CommandRunner'].run.__code__.co_varnames,
                      'Missing live command observer before timeout cancellation')
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            root = Path(directory)
            runner = module['CommandRunner'](root)
            observed = []
            def sample_wait(pid):
                observed.append((pid, time.monotonic()))
                (root / 'observer-started').write_text(str(pid))
                time.sleep(1.2)
            result = runner.run('observed-timeout-unit', [sys.executable, '-u', '-c',
                'import time; time.sleep(10)'], timeout=1, wait_probe=sample_wait, probe_after=0.1)
            self.assertEqual(result['status'], 124)
            self.assertEqual(result['timeout_seconds'], 1)
            self.assertTrue(result['wait_probe_invoked'])
            self.assertTrue(result['wait_probe_completed'])
            self.assertEqual(len(observed), 1)
            self.assertGreater(observed[0][0], 0)
            self.assertLess(result['command_elapsed_seconds'], 1.8)
            self.assertTrue((root / 'observer-started').is_file())

    def test_wait_probe_cancels_on_fast_exit_and_probe_error_does_not_override_timeout(self):
        module = self.module()
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            runner = module['CommandRunner'](Path(directory))
            callback = mock.Mock()
            fast = runner.run('fast-observer-unit', [sys.executable, '-c', 'pass'],
                timeout=3, wait_probe=callback, probe_after=2)
            self.assertEqual(fast['status'], 0)
            self.assertFalse(fast['wait_probe_invoked'])
            callback.assert_not_called()
            def failing_probe(pid):
                raise RuntimeError('expected observer rejection')
            blocked = runner.run('failing-observer-unit', [sys.executable, '-c',
                'import time; time.sleep(10)'], timeout=0.5, wait_probe=failing_probe, probe_after=0.05)
            self.assertEqual(blocked['status'], 124)
            self.assertTrue(blocked['wait_probe_completed'])
            self.assertIn('expected observer rejection', blocked['wait_probe_error'])

    def test_runtime_inventory_is_launched_once_with_30_second_bound_and_live_probe(self):
        module = self.module()
        self.assertIn('runtime_inventory_once', module, 'Missing runtime-inventory live observation')
        runner = mock.Mock()
        runner.run.return_value = {'status': 124, 'timed_out': True}
        observed = module['runtime_inventory_once'](runner)
        self.assertEqual(observed['status'], 124)
        runner.run.assert_called_once()
        call = runner.run.call_args
        self.assertEqual(call.args, ('runtimes', ['xcrun', 'simctl', 'list', 'runtimes', '--json']))
        self.assertEqual(call.kwargs['timeout'], 30)
        self.assertLess(call.kwargs['probe_after'], 30)
        self.assertTrue(callable(call.kwargs['wait_probe']))

    def test_runtime_wait_collection_samples_client_and_only_matching_service(self):
        module = self.module()
        self.assertIn('collect_runtime_wait_evidence', module, 'Missing service/stack evidence collector')
        process_list = ('4242 1 S 00:10 /Applications/Xcode.app/Contents/Developer/usr/bin/simctl list runtimes --json\n'
            '5100 1 S 00:08 /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Resources/bin/com.apple.CoreSimulator.CoreSimulatorService\n'
            '6100 1 S 00:08 /usr/bin/unrelated CoreSimulatorService\n')
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            runner = mock.Mock()
            runner.directory = Path(directory)
            runner.run.side_effect = lambda label, argv, **kw: dict(status=0,
                stdout=process_list if argv[0] == 'ps' else '', log=str(Path(directory) / (label + '.log')))
            module['collect_runtime_wait_evidence'](runner, 4242)
            commands = [call.args[1] for call in runner.run.call_args_list]
            samples = [argv for argv in commands if argv[0] == '/usr/bin/sample']
            self.assertEqual([argv[1] for argv in samples], ['4242', '5100'])
            self.assertIn(['launchctl', 'list'], commands)
            self.assertTrue(any(argv[:2] == ['/usr/bin/log', 'show'] for argv in commands))
            self.assertFalse(any(argv[0] in ('killall', 'pkill', 'launchd') or
                'kickstart' in argv or 'shutdown' in argv or 'boot' in argv for argv in commands))
            self.assertTrue((Path(directory) / 'runtimes-wait-services.json').is_file())

    def test_runtime_only_mode_stops_at_inventory_boundary_for_success_and_timeout(self):
        module = self.module()
        for status in (0, 124):
            with self.subTest(status=status), tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
                root = Path(directory)
                runner = mock.Mock()
                runner.directory = root / 'settings-startup-diagnostic'
                source = 'a' * 40  # Unit fixture only; real cloud mode verifies checkout HEAD.
                runner.checked.side_effect = lambda label, argv, **kw: source if label == 'head' else ''
                runner.run.side_effect = lambda label, argv, **kw: dict(status=status if label == 'runtimes' else 0,
                    stdout='{"runtimes": []}' if label == 'runtimes' and status == 0 else '', timed_out=status == 124)
                namespace = module['execute_runtime_wait_diagnostic'].__globals__
                with mock.patch.dict(os.environ, RUNNER_TEMP=directory, GITHUB_SHA=source,
                     GITHUB_RUN_ID='unit-fixture', GITHUB_RUN_ATTEMPT='1'), \
                     mock.patch('platform.system', return_value='Darwin'), \
                     mock.patch.dict(namespace, CommandRunner=lambda path: runner), \
                     mock.patch('builtins.print'):
                    actual = module['execute_runtime_wait_diagnostic']()
                self.assertEqual(actual, 0 if status == 0 else 1)
                report = json.loads((runner.directory / 'RESULT.json').read_text())
                self.assertEqual(report['runtime_inventory_completed'], status == 0)
                self.assertEqual(report['apps_executed'], [])
                self.assertEqual(report['runtime_timeout_seconds'], 30)
                calls = [call.args[1] for call in runner.run.call_args_list]
                simulator_calls = [argv for argv in calls if argv[:2] == ['xcrun', 'simctl']]
                self.assertEqual(simulator_calls, [['xcrun', 'simctl', 'list', 'runtimes', '--json']])

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
        commands = '\n'.join(step.get('run', '') for step in steps)
        self.assertIn('python3 -B ci/settings_startup_diagnostic.py --execute --runtime-wait-only', commands)
        self.assertIn('mkdir -p "$RUNNER_TEMP/settings-startup-diagnostic"', commands)
        self.assertIn('tee "$RUNNER_TEMP/settings-startup-diagnostic/guard-tests.log"', commands)
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
