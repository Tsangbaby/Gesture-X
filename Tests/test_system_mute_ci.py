"""System-mute report/runner contracts. Synthetic inputs are NOT native execution."""
import contextlib
import io
import os
import re
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '1234567890' * 4
BASELINE = '0cc50fbd3e82c336f89394f80cb298aa150a1c70'
FAILURE = 'SYSTEM_MUTE_RUNTIME_FAIL: persisted systemMute action is unavailable'
CURRENT = ('SYSTEM_MUTE_RUNTIME_PASS: 17 assertions; mode=--current; '
           'actual production Swift/Objective-C fixtures, NOT handset ringer/HUD proof')


class SystemMuteProtocolContracts(unittest.TestCase):
    def guard(self):
        path = ROOT / 'ci/system_mute_guard.py'
        self.assertTrue(path.is_file(), 'Missing exact-source system-mute execution guard')
        return runpy.run_path(str(path))

    def report(self):
        g = self.guard()
        return '\n'.join(g['_header'](SOURCE) + [FAILURE, g['BASELINE_MARKER'], CURRENT, g['SUMMARY']]) + '\n'

    def test_native_completion_requires_precise_behavior_not_compiler_or_transport_status(self):
        g = self.guard()
        validate = g['validate_completed_run']
        self.assertEqual(validate(1, FAILURE + '\n', '--baseline'), g['BASELINE_MARKER'])
        self.assertEqual(validate(0, CURRENT + '\n', '--current'), CURRENT)
        for mode, code, text in (
            ('--baseline', 0, FAILURE + '\n'), ('--baseline', 2, FAILURE + '\n'),
            ('--baseline', 1, 'swiftc: unknown symbol\n'), ('--baseline', 1, ''),
            ('--current', 1, CURRENT + '\n'), ('--current', 0, ''),
            ('--current', 0, CURRENT + '\n' + CURRENT + '\n'),
            ('--current', 0, CURRENT.replace('17 assertions', '0 assertions') + '\n'),
            ('--current', 0, CURRENT.replace('17 assertions', '-1 assertions') + '\n'),
            ('--current', 0, CURRENT + '\r\n'), ('--current', 0, 'prefix ' + CURRENT + '\n'),
            ('--unknown', 0, CURRENT + '\n'),
        ):
            with self.subTest(mode=mode, code=code, text=text), self.assertRaises(ValueError):
                validate(code, text, mode)

    def test_suite_binds_exact_source_order_attestations_and_all_terminal_records(self):
        g = self.guard()
        good = self.report()
        self.assertEqual(g['validate_completed_suite'](good, SOURCE), g['SUMMARY'])
        lines = good.splitlines(keepends=True)
        for index, line in enumerate(lines):
            for bad in (''.join(lines[:index] + lines[index + 1:]), good + line,
                        ''.join(lines[:index] + [line + 'extra\n'] + lines[index + 1:])):
                with self.subTest(index=index, bad=bad), self.assertRaises(ValueError):
                    g['validate_completed_suite'](bad, SOURCE)
        for index in range(len(lines) - 1):
            swapped = lines[:]
            swapped[index], swapped[index + 1] = swapped[index + 1], swapped[index]
            with self.subTest(swap=index), self.assertRaises(ValueError):
                g['validate_completed_suite'](''.join(swapped), SOURCE)
        for bad in (good[:-1], good.replace('\n', '\r\n'), good.replace(SOURCE, 'f' * 40),
                    good.replace('17 assertions', '0 assertions'), good + 'SYSTEM_MUTE_RUNTIME_FAIL: interrupted\n'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                g['validate_completed_suite'](bad, SOURCE)
        for source in ('', SOURCE[:-1], SOURCE + '0', 'A' * 40, 'g' * 40):
            with self.subTest(source=source), self.assertRaises(ValueError):
                g['validate_completed_suite'](good, source)

    def test_actual_child_report_writer_reaches_complete_protocol_and_rejects_failure_without_append(self):
        g = self.guard()
        with tempfile.TemporaryDirectory(prefix='system-mute-protocol-', dir=os.environ.get('TMPDIR')) as directory:
            report = Path(directory) / 'report.txt'
            report.write_bytes(('\n'.join(g['_header'](SOURCE)) + '\n').encode())
            for mode, code, text in (('--baseline', 1, FAILURE + '\n'), ('--current', 0, CURRENT + '\n')):
                child = SimpleNamespace(returncode=code, stdout=text.encode())
                with mock.patch('subprocess.run', return_value=child), contextlib.redirect_stdout(io.StringIO()):
                    g['run_and_record']('synthetic-child-not-native', report, mode)
            self.assertEqual(g['complete_suite'](report, SOURCE), g['SUMMARY'])
            self.assertEqual(report.read_bytes().decode(), self.report())
            with self.assertRaises(ValueError):
                g['complete_suite'](report, SOURCE)
            before = report.read_bytes()
            with self.assertRaises(ValueError):
                g['run_and_record']('synthetic-child-not-native', report, '--current')
            self.assertEqual(report.read_bytes(), before)
            report.write_bytes(('\n'.join(g['_header'](SOURCE)) + '\n').encode())
            before = report.read_bytes()
            with mock.patch('subprocess.run', return_value=SimpleNamespace(returncode=0, stdout=FAILURE.encode())), self.assertRaises(ValueError):
                g['run_and_record']('synthetic-child-not-native', report, '--baseline')
            self.assertEqual(report.read_bytes(), before)

    def test_real_subprocess_writer_reports_modes_without_mistaking_synthetic_child_for_native(self):
        g = self.guard()
        with tempfile.TemporaryDirectory(prefix='system-mute-child-', dir=os.environ.get('TMPDIR')) as directory:
            folder = Path(directory)
            child = folder / 'synthetic-child'
            child.write_text('#!' + sys.executable + '\nimport sys\n'
                             'if sys.argv[1:] == ["--baseline"]:\n'
                             '    print(' + repr(FAILURE) + '); sys.exit(1)\n'
                             'if sys.argv[1:] == ["--current"]:\n'
                             '    print(' + repr(CURRENT) + '); sys.exit(0)\n'
                             'sys.exit(3)\n')
            child.chmod(0o700)
            report = folder / 'report.txt'
            report.write_bytes(('\n'.join(g['_header'](SOURCE)) + '\n').encode())
            with contextlib.redirect_stdout(io.StringIO()):
                g['run_and_record'](child, report, '--baseline')
                g['run_and_record'](child, report, '--current')
            self.assertEqual(g['complete_suite'](report, SOURCE), g['SUMMARY'])
            self.assertEqual(report.read_bytes().decode(), self.report())

    def test_true_baseline_preference_bytes_and_malformed_inputs_use_actual_byte_verifier(self):
        import json
        g = self.guard()
        manifest = json.loads((ROOT / 'Tests/system_mute_baseline.json').read_bytes())
        current = (ROOT / 'Shared/Preferences.swift').read_bytes().decode('utf-8')
        for hunk in reversed(manifest['hunks']['Shared/Preferences.swift']):
            self.assertEqual(current.count(hunk['after']), 1)
            current = current.replace(hunk['after'], hunk['before'])
        raw = current.encode('utf-8')
        self.assertEqual(g['verified_baseline_preferences'](ROOT, raw), raw)
        for altered in (raw + b' ', raw.replace(b'\n', b'\r\n'), raw.replace(b'case lock', b'case modifiedLock', 1), b''):
            with self.subTest(altered=altered[:70]), self.assertRaises(ValueError):
                g['verified_baseline_preferences'](ROOT, altered)
        with self.assertRaises(ValueError):
            g['verified_baseline_preferences'](ROOT, (ROOT / 'Shared/Preferences.swift').read_bytes())

    def test_class_name_rebinding_is_unique_and_byte_invertible(self):
        rebind = self.guard()['rebind_source']
        original = b'let name = "SBRingerControl"\r\n'
        result = rebind(original, b'"SBRingerControl"', b'"TLSystemMuteRingerFixture"')
        self.assertEqual(result.replace(b'"TLSystemMuteRingerFixture"', b'"SBRingerControl"'), original)
        for bad, old, new in ((original * 2, b'"SBRingerControl"', b'"Fixture"'),
                              (original, b'"Missing"', b'"Fixture"'),
                              (original + b'"Fixture"', b'"SBRingerControl"', b'"Fixture"'),
                              (original, b'', b'"Fixture"')):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                rebind(bad, old, new)

    def test_real_cli_validates_report_without_history_or_path(self):
        good = self.report()
        with tempfile.TemporaryDirectory(prefix='system-mute-cli-', dir=os.environ.get('TMPDIR')) as directory:
            report = Path(directory) / 'result.txt'
            report.write_bytes(good.encode())
            env = dict(os.environ, PATH='', PYTHONDONTWRITEBYTECODE='1')
            command = [sys.executable, '-B', str(ROOT / 'ci/system_mute_guard.py'), '--validate-suite', str(report), SOURCE]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, self.guard()['SUMMARY'] + '\n')
            report.write_bytes(good.replace('17 assertions', '0 assertions').encode())
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)

    def test_real_runner_refuses_non_darwin_before_tools_or_report_on_every_host(self):
        runner = ROOT / 'ci/system-mute-smoke.sh'
        self.assertTrue(runner.is_file(), 'Missing isolated Apple system-mute runner')
        with tempfile.TemporaryDirectory(prefix='system-mute-refusal-', dir=os.environ.get('TMPDIR')) as directory:
            folder = Path(directory)
            uname = folder / 'uname'
            uname.write_text('#!' + sys.executable + '\nprint("Linux")\n')
            uname.chmod(0o700)
            env = dict(os.environ, PATH=directory, RUNNER_TEMP=directory, CI='true', GITHUB_SHA=SOURCE)
            result = subprocess.run(['/bin/bash', str(runner)], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, 'system-mute smoke requires Darwin/Apple Swift; no native result produced\n')
            self.assertFalse((folder / 'SYSTEM_MUTE_TESTS.txt').exists())

    def test_runner_executes_baseline_then_current_then_complete_and_revalidation(self):
        path = ROOT / 'ci/system-mute-smoke.sh'
        self.assertTrue(path.is_file(), 'Missing isolated Apple system-mute runner')
        runner = path.read_text()
        self.assertIn('BASELINE=' + BASELINE, runner)
        for token in ('-DSYSTEM_MUTE_BASELINE', 'Tests/SystemMuteRuntimeTests.swift',
                      'Sources/PrivateAPI.swift', 'Shared/Preferences.swift', '--prepare-sources',
                      '--baseline', '--current', '--complete-suite', '--validate-suite'):
            self.assertIn(token, runner)
        self.assertLess(runner.index('--baseline'), runner.index('--current'))
        self.assertLess(runner.index('--current'), runner.index('--complete-suite'))
        self.assertLess(runner.index('--complete-suite'), runner.index('--validate-suite'))
        guard = (ROOT / 'ci/system_mute_guard.py').read_text()
        for token in ('Sources/SystemMuteAction.swift', 'Sources/LockAction.swift', 'Tests/system_mute_baseline.json',
                      'TLSystemMuteApplicationFixture', 'TLSystemMuteWorkspaceFixture',
                      'TLSystemMuteRingerFixture', 'TLSystemMuteLockFixture',
                      'Native compile/protocol input differs from source commit'):
            self.assertIn(token, guard)


class SystemMutePipelineContracts(unittest.TestCase):
    def test_existing_root_hide_only_workflow_executes_and_retains_new_native_proof(self):
        import json
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_bytes())
        self.assertEqual(workflow['on']['push']['branches'], ['main'])
        self.assertEqual(set(workflow['jobs']), {'roothide'})
        steps = workflow['jobs']['roothide']['steps']
        native = next(s['run'] for s in steps if s['name'] == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/system-mute-smoke.sh', native)
        self.assertIn('python3 -B ci/system_mute_guard.py --validate-suite "$RUNNER_TEMP/SYSTEM_MUTE_TESTS.txt" "$GITHUB_SHA"', native)
        ui = next(s['run'] for s in steps if s['name'] == 'Settings constructor regression (iOS Simulator fixture)')
        self.assertIn('--with-track-baseline --with-flashlight-baseline --with-system-mute-baseline', ui)
        package = next(s['run'] for s in steps if s['name'] == 'Compile and package RootHide')
        self.assertIn('cp "$RUNNER_TEMP/SYSTEM_MUTE_TESTS.txt" "$OUT_DIR/SYSTEM_MUTE_TESTS.txt"', package)

    def test_package_rejects_new_fixture_or_ringer_provider_in_settings(self):
        verifier = (ROOT / 'ci/verify_package.py').read_text()
        for token in ('"SystemMuteRuntimeTests"', 'b"TLSystemMute"', 'b"SYSTEM_MUTE_RUNTIME_"',
                      'b"activateRingerHUDFromMuteSwitch:"', 'System mute provider leaked into Settings binary'):
            self.assertIn(token, verifier)


if __name__ == '__main__':
    unittest.main(verbosity=2)
