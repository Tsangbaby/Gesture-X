"""Authored UIKit contracts and real guard CLI on synthetic simctl input; NOT UIKit execution."""
import contextlib
import inspect
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
MODE = '--expect-system-mute-baseline-failure'
RED = 'SYSTEM_MUTE_SETTINGS_BASELINE_EXPECTED_FAILURE: original system-mute row is disabled'
GREEN = ('REFERENCE_SETTINGS_UIKIT_PASS: 10 assertions; ten single-value replacements; '
         'simulator fixture boundary only')


class SystemMuteCompletionGuardContracts(unittest.TestCase):
    def guard(self):
        return runpy.run_path(str(ROOT / 'ci/reference_settings_guard.py'))

    def require_opt_in(self, guard):
        parameter = inspect.signature(guard['validate_completed_suite']).parameters.get('system_mute')
        self.assertIsNotNone(parameter, 'Missing explicit fifth historical UIKit RED opt-in')
        self.assertIs(parameter.default, False)

    def actual_written_report(self):
        """Exercise the real CLI writer, substituting only simctl's transport result."""
        guard = self.guard()
        modes = [('--expect-reference-baseline-failure', guard['NEGATIVE']),
                 ('--expect-media-baseline-failure', guard['MEDIA_NEGATIVE']),
                 ('--expect-track-baseline-failure', guard['TRACK_NEGATIVE']),
                 ('--expect-flashlight-baseline-failure', guard['FLASHLIGHT_NEGATIVE']),
                 (MODE, RED), ('--expect-reference-fixed', GREEN)]
        with tempfile.TemporaryDirectory(prefix='system-mute-ui-writer-', dir=os.environ.get('TMPDIR')) as folder:
            report = Path(folder) / 'report.txt'
            report.write_text('REFERENCE_UIKIT_SOURCE_COMMIT: ' + SOURCE + '\n')
            for mode, marker in modes:
                result = SimpleNamespace(returncode=0, stdout='UIKit incidental log\n' + marker + '\n')
                with mock.patch('sys.argv', ['guard', 'fixture-device', 'fixture-bundle', mode, str(report)]), \
                        mock.patch('subprocess.run', return_value=result), contextlib.redirect_stdout(io.StringIO()):
                    guard['main']()
            return report.read_text(), modes

    def test_fifth_mode_requires_exact_marker_and_transport(self):
        validate = self.guard()['validate_completed_run']
        try:
            actual = validate(0, 'incidental UIKit log\n' + RED + '\n', MODE)
        except ValueError as error:
            self.fail('Missing fifth real UIKit historical mode: ' + str(error))
        self.assertEqual(actual, RED)
        for code, output in ((1, RED), (2, RED), (0, ''), (0, 'swiftc failed'),
                             (0, RED + '\n' + RED), (0, RED + ' '),
                             (0, 'prefix ' + RED), (0, RED.replace('system-mute', 'mute')),
                             (0, RED + '\nREFERENCE_SETTINGS_FAIL: interrupted'),
                             (0, RED + '\n' + GREEN)):
            with self.subTest(code=code, output=output), self.assertRaises(ValueError):
                validate(code, output, MODE)
        for mode in ('--expect-reference-fixed', '--expect-flashlight-baseline-failure'):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                validate(0, RED + '\n' + GREEN, mode)

    def test_real_writer_six_case_suite_requires_explicit_dependencies(self):
        guard = self.guard()
        self.require_opt_in(guard)
        report, modes = self.actual_written_report()
        validate = guard['validate_completed_suite']
        self.assertEqual(validate(report, SOURCE, media_tracks=True, flashlight=True, system_mute=True), GREEN)
        self.assertEqual(report.count('Transport exit: 0\n'), len(modes))
        for flags in ({}, {'system_mute': True}, {'system_mute': True, 'media_tracks': True},
                      {'system_mute': True, 'flashlight': True}, {'media_tracks': True, 'flashlight': True}):
            with self.subTest(flags=flags), self.assertRaises(ValueError):
                validate(report, SOURCE, **flags)

    def test_exact_paired_protocol_rejects_missing_duplicate_reordered_mixed_and_zero_completion(self):
        guard = self.guard()
        self.require_opt_in(guard)
        good, modes = self.actual_written_report()
        validate = lambda text, source=SOURCE: guard['validate_completed_suite'](
            text, source, media_tracks=True, flashlight=True, system_mute=True)
        self.assertEqual(validate(good), GREEN)
        fields = ['REFERENCE_UIKIT_SOURCE_COMMIT: ' + SOURCE]
        for mode, marker in modes:
            fields.extend(['Mode: ' + mode, marker, 'Verified terminal: ' + marker])
        for line in fields:
            for bad in (good.replace(line + '\n', '', 1), good + line + '\n'):
                with self.subTest(line=line), self.assertRaises(ValueError):
                    validate(bad)
        blocks = good.split('Mode: ')
        for index in range(1, len(blocks) - 1):
            swapped = blocks[:]
            swapped[index], swapped[index + 1] = swapped[index + 1], swapped[index]
            with self.subTest(swap=index), self.assertRaises(ValueError):
                validate('Mode: '.join(swapped))
        for index in range(len(modes)):
            lines = good.splitlines(keepends=True)
            location = [i for i, line in enumerate(lines) if line == 'Transport exit: 0\n'][index]
            for replacement in ('', 'Transport exit: 1\n', 'Transport exit: NaN\n'):
                broken = lines[:]
                broken[location] = replacement
                with self.subTest(transport=index, replacement=replacement), self.assertRaises(ValueError):
                    validate(''.join(broken))
        for bad in (good.replace(SOURCE, 'a' * 40),
                    good.replace('10 assertions', '0 assertions'),
                    good.replace('10 assertions', '-1 assertions'),
                    good.replace('10 assertions', 'NaN assertions'),
                    good.replace('ten single-value', 'nine single-value'),
                    good + 'Transport exit: 0\n',
                    good + 'REFERENCE_SETTINGS_FAIL: interrupted\n',
                    good + 'NATIVE_STARTUP_PASS: 10 executed production-startup/hook/attachment checks\n',
                    good.replace('Verified terminal: ' + RED, 'Verified terminal: ' + modes[3][1]),
                    good.replace('Mode: ' + MODE, 'Mode: --unknown'),
                    good.replace(RED, RED.replace('system-mute', 'ringer'))):
            with self.subTest(output=bad), self.assertRaises(ValueError):
                validate(bad)
        for source in ('', SOURCE[:-1], SOURCE + '0', 'ABCDEF0123' * 4, 'g' * 40):
            with self.subTest(source=source), self.assertRaises(ValueError):
                validate(good, source)

    def test_writer_never_attests_nonzero_transport_or_missing_completion(self):
        guard = self.guard()
        # Check support with an assertion before negative cases, not an unknown-mode false positive.
        self.assertIn('SYSTEM_MUTE_SETTINGS_BASELINE_EXPECTED_FAILURE:', guard['UI_TERMINAL_FIELDS'])
        for code, output in ((1, RED), (0, ''), (0, 'compile failed'),
                             (0, RED + '\n' + RED), (0, RED + '\n' + GREEN)):
            with tempfile.TemporaryDirectory(prefix='system-mute-ui-bad-', dir=os.environ.get('TMPDIR')) as folder:
                report = Path(folder) / 'report.txt'
                report.write_text('sentinel\n')
                with mock.patch('sys.argv', ['guard', 'device', 'bundle', MODE, str(report)]), \
                        mock.patch('subprocess.run', return_value=SimpleNamespace(returncode=code, stdout=output)), \
                        contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ValueError):
                    guard['main']()
                self.assertEqual(report.read_text(), 'sentinel\n')

    def test_real_suite_cli_requires_all_five_reds_current_and_ten_startup_checks(self):
        guard = self.guard()
        self.require_opt_in(guard)
        report, _ = self.actual_written_report()
        startup_marker = 'NATIVE_STARTUP_PASS: 10 executed production-startup/hook/attachment checks'
        with tempfile.TemporaryDirectory(prefix='system-mute-ui-cli-', dir=os.environ.get('TMPDIR')) as folder:
            ui, startup = Path(folder) / 'ui.txt', Path(folder) / 'startup.txt'
            ui.write_text(report)
            startup.write_text(startup_marker + '\n')
            base = [sys.executable, '-B', str(ROOT / 'ci/reference_settings_guard.py'),
                    '--validate-suite', str(ui), SOURCE, str(startup)]
            flags = ['--with-track-baseline', '--with-flashlight-baseline', '--with-system-mute-baseline']
            good = subprocess.run(base + flags, text=True, capture_output=True, timeout=10)
            self.assertEqual(good.returncode, 0, good.stderr)
            self.assertIn('five behavioral REDs', good.stdout)
            for bad in ('', startup_marker + '\n' + RED, startup_marker + '\n' + startup_marker,
                        startup_marker.replace(': 10 ', ': 0 '), startup_marker.replace(': 10 ', ': 9 '),
                        startup_marker + '\nNATIVE_STARTUP_FAIL: interrupted'):
                startup.write_text(bad)
                result = subprocess.run(base + flags, text=True, capture_output=True, timeout=10)
                with self.subTest(startup=bad):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('REFERENCE_SETTINGS_SUITE_PASS:', result.stdout)
            startup.write_text(startup_marker)
            for bad_flags in ([flags[2]], flags[1:], flags[::2], flags + [flags[2]], flags + ['--unknown']):
                result = subprocess.run(base + bad_flags, text=True, capture_output=True, timeout=10)
                with self.subTest(flags=bad_flags):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('REFERENCE_SETTINGS_SUITE_PASS:', result.stdout)


class SystemMuteUIKitSourceContracts(unittest.TestCase):
    """Linux source/selector checks only; cloud Mac must execute Swift/UIKit."""
    def test_current_matrix_rejects_aliases_and_pins_original_system_mute_slot_and_action(self):
        app = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertIn('let currentBasicKinds: [String: String] = [', app,
                      'Ten identities alone must not allow two basics to alias one action')
        mapping = app.split('let currentBasicKinds: [String: String] = [', 1)[1].split(']', 1)[0]
        self.assertEqual(dict(re.findall(r'"([A-Z_]+)": "([a-zA-Z]+)"', mapping)), {
            'SYSTEM_SCREENSHOT': 'screenshot', 'SYSTEM_CONTROLCENTER': 'controlCenter',
            'SYSTEM_COVER': 'notificationCenter', 'SYSTEM_LOCKSCREEN': 'lock',
            'SYSTEM_SWITCHER': 'appSwitcher', 'PLAYPAUSE_MEDIA': 'playPause',
            'PREVIOUS_MEDIA': 'previousTrack', 'NEXT_MEDIA': 'nextTrack',
            'TOGGLE_FLASHLIGHT': 'flashlight', 'SYSTEM_MUTE': 'systemMute'})
        for token in ('implementedEntries.allSatisfy', 'currentBasicKinds[id] == kind',
                      'systemMuteEntry["referenceSlot"] as? Int == 32',
                      'systemMuteEntry["referenceActionNumber"] as? Int == 50',
                      'systemMuteEntry["image"] as? String == "bell.slash"'):
            self.assertIn(token, app)

    def test_fifth_historical_row_is_forced_inert_before_unique_terminal(self):
        app = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertIn(MODE, app, 'Real UIKit harness lacks fifth historical mode')
        start = app.index('if ProcessInfo.processInfo.arguments.contains("' + MODE + '")')
        body = app[start:app.index('\n        checkBasic(basicTable', start)]
        for token in ('find(basicTable, id: "SYSTEM_MUTE")', '"系统静音"',
                      'checkInert(basicTable, systemMute, nav)', 'nav.topViewController === basic', RED):
            self.assertIn(token, body)
        self.assertLess(body.index('checkInert('), body.index('finish('))
        inert = app.split('private func checkInert(', 1)[1].split('\n    private func ', 1)[0]
        for token in ('!target.isUserInteractionEnabled', 'target.selectionStyle == .none',
                      'target.accessibilityTraits.contains(.notEnabled)', 'tap(table, path)',
                      'samePreferences(before)', 'zip(nav.viewControllers, stack)',
                      'presentedViewController === presented'):
            self.assertIn(token, inert)
        self.assertIn('table.delegate?.tableView?(table, didSelectRowAt: path)', app)

    def test_current_ten_identity_matrix_search_checkmarks_and_bidirectional_app_replacements(self):
        app = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertIn('let expectedBasicCount = 10', app, 'Current UIKit must exercise ten basics')
        self.assertIn('#elseif SYSTEM_MUTE_BASELINE\n        let expectedBasicCount = 9', app)
        self.assertIn('#elseif FLASHLIGHT_BASELINE\n        let expectedBasicCount = 8', app)
        self.assertRegex(app, r'#if REFERENCE_SETTINGS_CURRENT \|\| SYSTEM_MUTE_BASELINE\s+case "flashlight": return \.flashlight\s+#endif')
        self.assertRegex(app, r'#if REFERENCE_SETTINGS_CURRENT\s+case "systemMute": return \.systemMute\s+#endif')
        identity = app.split('let currentBasicIdentities: Set<String> = [', 1)[1].split(']', 1)[0]
        self.assertEqual(set(re.findall(r'"([A-Z_]+)"', identity)), {
            'SYSTEM_SCREENSHOT', 'SYSTEM_CONTROLCENTER', 'SYSTEM_COVER', 'SYSTEM_LOCKSCREEN',
            'SYSTEM_SWITCHER', 'PLAYPAUSE_MEDIA', 'PREVIOUS_MEDIA', 'NEXT_MEDIA',
            'TOGGLE_FLASHLIGHT', 'SYSTEM_MUTE'})
        self.assertIn('entries.count == 68 && implementedEntries.count == expectedBasicCount', app)
        search = app.split('let searchSnapshot = preferences()', 1)[1].split('// Refresh', 1)[0]
        self.assertIn('"系统静音"', search)
        self.assertIn('samePreferences(searchSnapshot)', search)
        self.assertIn('for entry in implementedEntries {', app)
        replacements = app.split('let previousActions = actions', 1)[1]
        for token in ('for enabled in [false, true]', 'for entry in implementedEntries {',
                      'selected: .openApp(id)', 'selected: action', '["kind": kind]',
                      '["kind": "openApp", "bundleIdentifier": id]',
                      'App-to-basic replacement is not a single value',
                      'basic-to-App replacement is not a single record',
                      'basic-to-App picker retained an old App checkmark',
                      'replacement App checkmark missing or not exclusive',
                      'App replacement changed enable state'):
            self.assertIn(token, replacements)
        completions = [line for line in app.splitlines() if 'self.finish("REFERENCE_SETTINGS_UIKIT_PASS:' in line]
        self.assertEqual(len(completions), 1)
        self.assertIn('ten single-value replacements', completions[0])
        self.assertNotIn('nine single-value replacements', app)

    def test_runner_fetches_exact_eight_baseline_inputs_and_verifies_the_27_digest_manifest(self):
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        self.assertIn('Tests/system_mute_baseline.json', runner, 'Missing exact 0.1.12 source-byte gate')
        for token in ("assert frozen['baseline'] == '0cc50fbd3e82c336f89394f80cb298aa150a1c70'",
                      "assert len(frozen['frozen']) == 27",
                      'git -C "$ROOT" fetch --no-tags --depth=1 origin "$SYSTEM_MUTE_SETTINGS_BASELINE"',
                      'git -C "$ROOT" show "$SYSTEM_MUTE_SETTINGS_BASELINE:$path"',
                      "assert len(paths) == 8", "frozen['frozen'][relative]",
                      'SYSTEM_MUTE_UIKIT_BASELINE_BYTES_VERIFIED:'):
            self.assertIn(token, runner)
        loop = runner.split('SYSTEM_MUTE_UI="$WORK/accepted-0112-ui"', 1)[1].split('; do', 1)[0]
        old_loop = runner.split('FLASHLIGHT_UI="$WORK/accepted-0111-ui"', 1)[1].split('; do', 1)[0]
        paths = lambda text: text.split('for path in ', 1)[1].replace('\\\n', ' ').split()
        self.assertEqual(paths(loop), paths(old_loop))
        self.assertEqual(len(paths(loop)), 8)
        self.assertIn('Preferences/Resources/SettingsReference.json', paths(loop))
        blocks = re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)", runner, re.S)
        verifier = next(block for block in blocks if 'SYSTEM_MUTE_UIKIT_BASELINE_BYTES_VERIFIED:' in block)
        self.assertIn("hashlib.sha256(path.read_bytes()).hexdigest() == frozen['frozen'][relative]", verifier)
        self.assertIn("assert len(frozen['frozen']) == 27", verifier)
        self.assertNotIn('system_mute_baseline import', verifier)
        cases = re.findall(r'^run_reference_case .*$', runner, re.M)
        self.assertEqual([line.split()[2] for line in cases], [
            'reference-baseline', 'media-baseline', 'track-baseline', 'flashlight-baseline',
            'system-mute-baseline', 'reference-fixed'])
        self.assertIn('run_reference_case "$SYSTEM_MUTE_UI" system-mute-baseline ' + MODE, runner)

    def test_actual_baseline_byte_gate_rejects_missing_drift_wrong_schema_and_path_substitution(self):
        import hashlib
        import json
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        blocks = re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)", runner, re.S)
        verifier = next(block for block in blocks if 'SYSTEM_MUTE_UIKIT_BASELINE_BYTES_VERIFIED:' in block)
        manifest = json.loads((ROOT / 'Tests/system_mute_baseline.json').read_bytes())
        loop = runner.split('SYSTEM_MUTE_UI="$WORK/accepted-0112-ui"', 1)[1].split('; do', 1)[0]
        paths = loop.split('for path in ', 1)[1].replace('\\\n', ' ').split()
        self.assertEqual(len(paths), 8)

        def baseline_bytes(relative):
            text = (ROOT / relative).read_bytes().decode('utf-8')
            for hunk in reversed(manifest['hunks'].get(relative, [])):
                self.assertEqual(text.count(hunk['after']), 1)
                text = text.replace(hunk['after'], hunk['before'])
            raw = text.encode('utf-8')
            self.assertEqual(hashlib.sha256(raw).hexdigest(), manifest['frozen'][relative])
            return raw

        with tempfile.TemporaryDirectory(prefix='system-mute-ui-byte-gate-', dir=os.environ.get('TMPDIR')) as folder:
            accepted, report = Path(folder) / 'accepted', Path(folder) / 'report.txt'
            originals = {relative: baseline_bytes(relative) for relative in paths}
            for relative, raw in originals.items():
                target = accepted / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
            command = [sys.executable, '-B', '-', str(accepted), str(ROOT), str(report)]

            def execute():
                report.unlink(missing_ok=True)
                return subprocess.run(command, input=verifier, capture_output=True, text=True, timeout=10)

            good = execute()
            self.assertEqual(good.returncode, 0, good.stderr)
            metadata = report.read_text()
            self.assertEqual(metadata, 'SYSTEM_MUTE_UIKIT_BASELINE_BYTES_VERIFIED: '
                             'eight exact accepted 0.1.12 source/resource inputs\n')
            suite, _ = SystemMuteCompletionGuardContracts().actual_written_report()
            first, rest = suite.split('\n', 1)
            guard = runpy.run_path(str(ROOT / 'ci/reference_settings_guard.py'))
            self.assertEqual(guard['validate_completed_suite'](first + '\n' + metadata + rest, SOURCE,
                             media_tracks=True, flashlight=True, system_mute=True), GREEN)
            for relative, raw in originals.items():
                target = accepted / relative
                for missing in (False, True):
                    if missing:
                        target.unlink()
                    else:
                        target.write_bytes(raw + b'\n// unrelated bytes\n')
                    bad = execute()
                    with self.subTest(relative=relative, missing=missing):
                        self.assertNotEqual(bad.returncode, 0)
                        self.assertIn('AssertionError', bad.stderr)
                        self.assertFalse(report.exists())
                    target.write_bytes(raw)
            resource = 'Preferences/Resources/SettingsReference.json'
            (accepted / resource).write_bytes((ROOT / resource).read_bytes())
            wrong_schema = execute()
            self.assertNotEqual(wrong_schema.returncode, 0)
            self.assertFalse(report.exists())
            (accepted / resource).write_bytes(originals[resource])
            # Same count and individually valid frozen digest is not sufficient:
            # the compile inputs must be exactly the eight declared paths.
            replaced = accepted / paths[0]
            replaced.unlink()
            alternate = accepted / 'Sources/LockAction.swift'
            alternate.parent.mkdir(parents=True, exist_ok=True)
            alternate.write_bytes(baseline_bytes('Sources/LockAction.swift'))
            substituted = execute()
            self.assertNotEqual(substituted.returncode, 0, 'Byte attestation accepted an unrelated frozen input in place of a compile input')
            self.assertIn('AssertionError', substituted.stderr)
            self.assertFalse(report.exists())

    def test_real_bash_selector_preserves_four_old_modes_and_uses_baseline_own_resource(self):
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        selection = runner.split('run_reference_case() {', 1)[1].split('    python3 - "$app/Info.plist"', 1)[0]
        self.assertIn('[ "$label" = system-mute-baseline ]', selection)
        self.assertIn('cp "$source_root/Preferences/Resources/SettingsReference.json"', selection)
        self.assertIn('compile_flag=-DSYSTEM_MUTE_BASELINE', selection)
        start = runner.index('    local compile_flag=-DREFERENCE_SETTINGS_CURRENT')
        end = runner.index('    python3 - "$app/Info.plist"', start)
        labels = ('reference-baseline', 'media-baseline', 'track-baseline', 'flashlight-baseline',
                  'system-mute-baseline', 'reference-fixed')
        script = ('set -euo pipefail\nchoose() {\nlocal label="$1"\n' + runner[start:end] +
                  'printf "%s\\n" "$compile_flag"\n}\n' + '\n'.join('choose ' + label for label in labels))
        result = subprocess.run(['bash', '-c', script], text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['-DMEDIA_PLAY_PAUSE_UNAVAILABLE'] * 2 + [
            '-DMEDIA_TRACKS_UNAVAILABLE', '-DFLASHLIGHT_BASELINE', '-DSYSTEM_MUTE_BASELINE',
            '-DREFERENCE_SETTINGS_CURRENT'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
