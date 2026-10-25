"""Executable report protocol tests; these are not Apple Swift execution."""
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUARD_PATH = ROOT / 'ci/flashlight_guard.py'


def load_guard():
    if not GUARD_PATH.is_file():
        raise AssertionError('exact-source flashlight report guard is not implemented')
    spec = importlib.util.spec_from_file_location('flashlight_guard_under_test', GUARD_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FlashlightReportTests(unittest.TestCase):
    def test_exact_current_completion(self):
        guard = load_guard()
        line = ('FLASHLIGHT_RUNTIME_PASS: 23 assertions; mode=--current; '
                'actual production Swift/Objective-C fixtures, NOT hardware effect proof')
        self.assertEqual(guard.validate_completed_run(0, line + '\n', '--current'), line)

    def setUp(self):
        self.guard = load_guard()
        self.source = '0123456789abcdef0123456789abcdef01234567'
        self.current = ('FLASHLIGHT_RUNTIME_PASS: 23 assertions; mode=--current; '
                        'actual production Swift/Objective-C fixtures, NOT hardware effect proof')

    def report(self):
        return '\n'.join([
            'FLASHLIGHT_SOURCE_COMMIT: ' + self.source,
            *self.guard.ATTESTATIONS,
            self.guard.BASELINE_FAILURE,
            self.guard.BASELINE_MARKER,
            self.current,
            self.guard.SUMMARY,
        ]) + '\n'

    def test_exact_behavioral_baseline_red(self):
        self.assertEqual(self.guard.validate_completed_run(
            1, 'FLASHLIGHT_RUNTIME_FAIL: persisted flashlight action is unavailable\n', '--baseline'),
            self.guard.BASELINE_MARKER)

    def test_baseline_requires_exact_assertion_not_compile_or_crash(self):
        for code in (0, 2, -6, 127):
            with self.subTest(code=code), self.assertRaises(ValueError):
                self.guard.validate_completed_run(code, self.guard.BASELINE_FAILURE + '\n', '--baseline')
        for output in ('', 'compiler error\n', self.current + '\n',
                       self.guard.BASELINE_FAILURE, self.guard.BASELINE_FAILURE + '\nextra\n'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                self.guard.validate_completed_run(1, output, '--baseline')

    def test_current_rejects_nonzero_empty_wrong_mode_and_zero_assertions(self):
        for code, output, mode in (
            (1, self.current + '\n', '--current'), (0, '', '--current'),
            (0, self.current + '\n', '--baseline'), (0, self.current + '\n', '--other'),
            (0, self.current.replace('23 assertions', '0 assertions') + '\n', '--current'),
            (0, self.current.replace('23 assertions', '01 assertions') + '\n', '--current'),
            (0, self.current + '\n' + self.current + '\n', '--current'),
            (0, self.current + '\nextra\n', '--current'),
            (0, ' ' + self.current + '\n', '--current'),
            (0, self.current + '\r\n', '--current'),
            (0, self.current, '--current'),
        ):
            with self.subTest(code=code, output=output, mode=mode), self.assertRaises(ValueError):
                self.guard.validate_completed_run(code, output, mode)

    def test_exact_complete_suite(self):
        self.assertEqual(self.guard.validate_completed_suite(self.report(), self.source), self.guard.SUMMARY)

    def test_every_missing_duplicate_and_reordered_record_fails(self):
        lines = self.report().splitlines()
        for index in range(len(lines)):
            for edited in (lines[:index] + lines[index + 1:],
                           lines[:index] + [lines[index]] + lines[index:]):
                with self.subTest(index=index, edited=edited), self.assertRaises(ValueError):
                    self.guard.validate_completed_suite('\n'.join(edited) + '\n', self.source)
        for index in range(len(lines) - 1):
            edited = lines.copy()
            edited[index], edited[index + 1] = edited[index + 1], edited[index]
            with self.subTest(swap=index), self.assertRaises(ValueError):
                self.guard.validate_completed_suite('\n'.join(edited) + '\n', self.source)

    def test_suite_rejects_sha_prefix_collision_and_unrecognized_lines(self):
        for source in (self.source[:-1], self.source + '0', self.source.upper(), 'f' * 40):
            with self.subTest(source=source), self.assertRaises(ValueError):
                self.guard.validate_completed_suite(self.report(), source)
        for extra in ('noise', 'FLASHLIGHT_SOURCE_COMMIT_EXTRA: ' + self.source,
                      'FLASHLIGHT_RUNTIME_PASS_EXTRA: 1', 'FLASHLIGHT_BASELINE_UNEXPECTED_SUCCESS',
                      self.guard.ATTESTATIONS[0] + ' suffix'):
            for report in (extra + '\n' + self.report(), self.report() + extra + '\n'):
                with self.subTest(extra=extra), self.assertRaises(ValueError):
                    self.guard.validate_completed_suite(report, self.source)
        for report in (self.report() + '\n', self.report().replace('\n', '\r\n'),
                       self.report().replace('mode=--current', 'mode=--baseline'),
                       self.report().replace('23 assertions', '0 assertions'),
                       self.report().replace(self.guard.BASELINE_FAILURE, self.guard.ATTESTATIONS[0])):
            with self.subTest(report=report), self.assertRaises(ValueError):
                self.guard.validate_completed_suite(report, self.source)

    def test_real_writer_and_cli_end_to_end(self):
        # This child is a protocol adversary, never claimed to execute Swift.
        with tempfile.TemporaryDirectory(prefix='flashlight-protocol-') as directory:
            folder = Path(directory)
            child = folder / 'protocol-child'
            child.write_text('#!' + sys.executable + '\nimport sys\n'
                             'if sys.argv[1] == "--baseline":\n'
                             ' print(' + repr(self.guard.BASELINE_FAILURE) + ')\n sys.exit(1)\n'
                             'print(' + repr(self.current) + ')\n')
            child.chmod(0o700)
            report = folder / 'report.txt'
            report.write_text('\n'.join(['FLASHLIGHT_SOURCE_COMMIT: ' + self.source,
                                         *self.guard.ATTESTATIONS]) + '\n')
            for mode in ('--baseline', '--current'):
                completed = subprocess.run([sys.executable, '-B', str(GUARD_PATH),
                                            str(child), str(report), mode], capture_output=True, text=True)
                self.assertEqual(completed.returncode, 0, completed.stderr)
            completed = subprocess.run([sys.executable, '-B', str(GUARD_PATH), '--complete-suite',
                                        str(report), self.source], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(report.read_text(), self.report())
            completed = subprocess.run([sys.executable, '-B', str(GUARD_PATH), '--validate-suite',
                                        str(report), self.source], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(completed.stdout, self.guard.SUMMARY + '\n')
            # The real writer refuses accidental duplicate invocations.
            previous = report.read_bytes()
            completed = subprocess.run([sys.executable, '-B', str(GUARD_PATH), str(child),
                                        str(report), '--current'], capture_output=True, text=True)
            self.assertNotEqual(completed.returncode, 0)
            self.assertEqual(report.read_bytes(), previous)

    def test_real_writer_rejects_prefix_collision_before_appending(self):
        with tempfile.TemporaryDirectory(prefix='flashlight-protocol-') as directory:
            folder = Path(directory)
            report = folder / 'report.txt'
            header = '\n'.join(['FLASHLIGHT_SOURCE_COMMIT: ' + self.source,
                                *self.guard.ATTESTATIONS, self.guard.BASELINE_FAILURE,
                                self.guard.BASELINE_MARKER]) + '\n'
            child = folder / 'protocol-child'
            for output, code in ((self.current + '_EXTRA\n', 0), (self.current + '\n', 1),
                                 (self.current + '\n' + self.current + '\n', 0), ('', 0),
                                 (self.current.replace('23 assertions', '0 assertions') + '\n', 0)):
                report.write_text(header)
                child.write_text('#!' + sys.executable + '\nimport sys\n'
                                 'sys.stdout.write(' + repr(output) + ')\nsys.exit(' + str(code) + ')\n')
                child.chmod(0o700)
                completed = subprocess.run([sys.executable, '-B', str(GUARD_PATH), str(child),
                                            str(report), '--current'], capture_output=True, text=True)
                with self.subTest(output=output, code=code):
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertEqual(report.read_text(), header)


class FlashlightSourceBindingTests(unittest.TestCase):
    def setUp(self):
        self.guard = load_guard()

    def test_counted_literal_rebinding_preserves_all_other_bytes(self):
        for relative, original, replacement in (
            ('Sources/LockAction.swift', b'"SBLockScreenManager"', b'"TLFlashlightLockManagerFixture"'),
            ('Sources/FlashlightAction.swift', b'"SBUIFlashlightController"', b'"TLFlashlightControllerFixture"'),
        ):
            raw = (ROOT / relative).read_bytes()
            self.assertEqual(raw.count(original), 1)
            rebound = self.guard.rebind_source(raw, original, replacement)
            self.assertEqual(rebound.replace(replacement, original), raw)
            self.assertEqual(rebound.count(replacement), 1)
            self.assertNotIn(original, rebound)

    def test_rebinding_rejects_missing_repeated_and_precollided_identity(self):
        for raw in (b'no lookup', b'"Old" "Old"', b'"Old" "New"'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                self.guard.rebind_source(raw, b'"Old"', b'"New"')

    def test_source_checks_run_in_candidate_only_checkout_without_path(self):
        with tempfile.TemporaryDirectory(prefix='flashlight-candidate-only-') as directory:
            candidate = Path(directory)
            for relative in (
                'Tests/test_flashlight_ci.py', 'Tests/flashlight_baseline.py',
                'Tests/flashlight_baseline.json', 'Shared/Preferences.swift',
                'Tests/system_mute_baseline.py', 'Tests/system_mute_baseline.json',
                'ci/flashlight_guard.py', 'ci/flashlight-smoke.sh',
            ):
                target = candidate / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((ROOT / relative).read_bytes())
            self.assertFalse((candidate / '.git').exists())
            names = (
                'test_real_baseline_bytes_match_history_owned_oracle',
                'test_runner_rejects_linux_before_writing_native_report',
            )
            result = subprocess.run(
                [str(Path(sys.executable).resolve()), '-B', '-m', 'unittest', '-v',
                 *('test_flashlight_ci.FlashlightSourceBindingTests.' + name for name in names)],
                cwd=candidate / 'Tests',
                env={**os.environ, 'PATH': '', 'PYTHONPATH': str(candidate / 'Tests')},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Ran 2 tests', result.stderr)
            self.assertNotIn('skipped', result.stderr.lower())

    def test_real_baseline_bytes_match_history_owned_oracle(self):
        from system_mute_baseline import accepted_flashlight_source as accepted_source

        # The exact inverse verifies the inherited digest without Git history.
        # Independent git-show verification remains in native source preparation.
        raw = accepted_source('Shared/Preferences.swift').encode('utf-8')
        self.assertEqual(self.guard.verified_baseline_preferences(ROOT, raw), raw)
        with self.assertRaises(ValueError):
            self.guard.verified_baseline_preferences(ROOT, raw + b'\n// accidental edit\n')

    def test_runner_rejects_linux_before_writing_native_report(self):
        runner = ROOT / 'ci/flashlight-smoke.sh'
        self.assertTrue(runner.is_file(), 'Darwin-only flashlight runner is not implemented')
        syntax = subprocess.run(['/bin/bash', '-n', str(runner)], capture_output=True, text=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        with tempfile.TemporaryDirectory(prefix='flashlight-linux-refusal-') as directory:
            # Exercise the real refusal gate on every host, never the Apple path.
            tools = Path(directory) / 'bin'
            tools.mkdir()
            uname = tools / 'uname'
            uname.write_text('#!' + str(Path(sys.executable).resolve()) + '\nprint("Linux")\n')
            uname.chmod(0o700)
            result = subprocess.run(
                ['/bin/bash', str(runner)],
                env={**os.environ, 'PATH': str(tools), 'RUNNER_TEMP': directory},
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr,
                             'flashlight smoke requires Darwin/Apple Swift; no native result produced\n')
            self.assertFalse((Path(directory) / 'FLASHLIGHT_TESTS.txt').exists())


if __name__ == '__main__':
    unittest.main()
