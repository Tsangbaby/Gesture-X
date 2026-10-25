"""Authored UIKit source contracts and synthetic guard inputs, NOT Apple execution."""
import ast
import contextlib
import inspect
import io
import json
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
FLASHLIGHT_MODE = '--expect-flashlight-baseline-failure'
FLASHLIGHT_RED = 'FLASHLIGHT_SETTINGS_BASELINE_EXPECTED_FAILURE: original flashlight row is disabled'


class FlashlightCompletionGuardContracts(unittest.TestCase):
    def guard(self):
        return runpy.run_path(str(ROOT / 'ci/reference_settings_guard.py'))

    def test_flashlight_baseline_requires_its_exact_behavioral_marker_and_transport(self):
        validate = self.guard()['validate_completed_run']
        try:
            result = validate(0, 'UIKit incidental log\n' + FLASHLIGHT_RED + '\n', FLASHLIGHT_MODE)
        except ValueError as error:
            self.fail('The fourth real UIKit historical mode is not implemented: ' + str(error))
        self.assertEqual(result, FLASHLIGHT_RED)
        for code, bad in ((1, FLASHLIGHT_RED), (2, FLASHLIGHT_RED), (0, ''),
                          (0, 'swiftc compilation failed'),
                          (0, FLASHLIGHT_RED + '\n' + FLASHLIGHT_RED),
                          (0, FLASHLIGHT_RED + '\nREFERENCE_SETTINGS_FAIL: interrupted'),
                          (0, FLASHLIGHT_RED.replace('flashlight', 'play/pause')),
                          (0, 'prefix ' + FLASHLIGHT_RED),
                          (0, FLASHLIGHT_RED + ' ')):
            with self.subTest(code=code, output=bad), self.assertRaises(ValueError):
                validate(code, bad, FLASHLIGHT_MODE)

    def actual_written_report(self, source='1234567890' * 4):
        """Feed synthetic simctl results through the REAL per-case CLI writer."""
        g = self.guard()
        modes = [('--expect-reference-baseline-failure', g['NEGATIVE']),
                 ('--expect-media-baseline-failure', g['MEDIA_NEGATIVE']),
                 ('--expect-track-baseline-failure', g['TRACK_NEGATIVE']),
                 (FLASHLIGHT_MODE, FLASHLIGHT_RED),
                 ('--expect-reference-fixed', 'REFERENCE_SETTINGS_UIKIT_PASS: 9 assertions; '
                  'nine single-value replacements; simulator fixture boundary only')]
        with tempfile.TemporaryDirectory(prefix='flashlight-ui-writer-', dir=os.environ.get('TMPDIR')) as folder:
            report = Path(folder) / 'report.txt'
            report.write_text('REFERENCE_UIKIT_SOURCE_COMMIT: ' + source + '\n')
            for mode, marker in modes:
                argv = ['guard', 'fixture-device', 'fixture-bundle', mode, str(report)]
                result = SimpleNamespace(returncode=0, stdout='UIKit incidental log\n' + marker + '\n')
                with mock.patch('sys.argv', argv), mock.patch('subprocess.run', return_value=result), contextlib.redirect_stdout(io.StringIO()):
                    g['main']()
            return report.read_text(), modes

    def test_actual_writer_four_red_suite_has_explicit_default_false_flag(self):
        g = self.guard()
        validate = g['validate_completed_suite']
        self.assertIn('flashlight', inspect.signature(validate).parameters,
                      'Missing explicit opt-in fourth historical UIKit RED suite')
        self.assertIs(inspect.signature(validate).parameters['flashlight'].default, False)
        report, modes = self.actual_written_report()
        self.assertEqual(validate(report, '1234567890' * 4, media_tracks=True, flashlight=True), modes[-1][1])
        self.assertEqual(report.count('Transport exit: 0\n'), 5,
                         'Real writer must retain successful simctl transport per case')
        with self.assertRaises(ValueError):
            validate(report, '1234567890' * 4, media_tracks=True)
        with self.assertRaises(ValueError):
            validate(report, '1234567890' * 4, flashlight=True)

    def test_full_suite_parser_rejects_missing_duplicate_reordered_wrong_source_and_mixed_records(self):
        validate = self.guard()['validate_completed_suite']
        self.assertIn('flashlight', inspect.signature(validate).parameters)
        good, modes = self.actual_written_report()
        source = '1234567890' * 4
        check = lambda output, sha=source: validate(output, sha, media_tracks=True, flashlight=True)
        self.assertEqual(check(good), modes[-1][1])
        # Every terminal, mode, verified echo and transport field is mandatory,
        # unique, correctly paired, and ordered, including the last current case.
        required = ['REFERENCE_UIKIT_SOURCE_COMMIT: ' + source]
        for mode, marker in modes:
            required.extend(['Mode: ' + mode, marker, 'Verified terminal: ' + marker])
        for line in required:
            for bad in (good.replace(line + '\n', '', 1), good + line + '\n'):
                with self.subTest(line=line, output=bad), self.assertRaises(ValueError):
                    check(bad)
        blocks = good.split('Mode: ')
        for index in range(1, len(blocks) - 1):
            swapped = blocks[:]
            swapped[index], swapped[index + 1] = swapped[index + 1], swapped[index]
            with self.subTest(swap=index), self.assertRaises(ValueError):
                check('Mode: '.join(swapped))
        for bad in (good.replace(source, 'a' * 40),
                    good.replace(': 9 assertions', ': 0 assertions'),
                    good.replace(': 9 assertions', ': -1 assertions'),
                    good.replace(': 9 assertions', ': NaN assertions'),
                    good.replace('Transport exit: 0\n', '', 1),
                    good + 'Transport exit: 0\n',
                    good.replace('Transport exit: 0', 'Transport exit: 1', 1),
                    good.replace('Transport exit: 0', 'Transport exit: NaN', 1),
                    good + 'REFERENCE_SETTINGS_FAIL: interrupted\n',
                    good + 'NATIVE_STARTUP_PASS: 10 executed production-startup/hook/attachment checks\n',
                    good.replace(FLASHLIGHT_RED, FLASHLIGHT_RED.replace('flashlight', 'torch')),
                    good.replace('Verified terminal: ' + FLASHLIGHT_RED,
                                 'Verified terminal: ' + modes[1][1]),
                    good.replace('Mode: ' + FLASHLIGHT_MODE, 'Mode: --unknown')):
            with self.subTest(output=bad), self.assertRaises(ValueError):
                check(bad)
        for wrong_source in ('', 'ABCDEF0123' * 4, source[:-1], source + '0', 'g' * 40):
            with self.subTest(source=wrong_source), self.assertRaises(ValueError):
                check(good, wrong_source)

    def test_real_cli_requires_four_reds_current_and_exact_ten_startup_checks(self):
        report, _ = self.actual_written_report()
        source = '1234567890' * 4
        marker = 'NATIVE_STARTUP_PASS: 10 executed production-startup/hook/attachment checks'
        with tempfile.TemporaryDirectory(prefix='flashlight-ui-cli-', dir=os.environ.get('TMPDIR')) as folder:
            ui, startup = Path(folder) / 'ui.txt', Path(folder) / 'startup.txt'
            ui.write_text(report)
            command = [sys.executable, '-B', str(ROOT / 'ci/reference_settings_guard.py'),
                       '--validate-suite', str(ui), source, str(startup),
                       '--with-track-baseline', '--with-flashlight-baseline']
            startup.write_text(marker + '\nBoundary: fixture, NOT handset injection\n')
            result = subprocess.run(command, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('four behavioral REDs', result.stdout)
            for bad in ('', marker + '\n' + marker, marker.replace(': 10 ', ': 0 '),
                        marker.replace(': 10 ', ': 9 '), marker.replace(': 10 ', ': 11 '),
                        marker + '\nNATIVE_STARTUP_FAIL: interrupted',
                        marker + '\n' + FLASHLIGHT_RED):
                startup.write_text(bad)
                failed = subprocess.run(command, text=True, capture_output=True, timeout=10)
                with self.subTest(startup=bad):
                    self.assertNotEqual(failed.returncode, 0)
                    self.assertNotIn('REFERENCE_SETTINGS_SUITE_PASS:', failed.stdout)
            startup.write_text(marker)
            for flags in (['--with-flashlight-baseline'], ['--with-track-baseline'] * 2,
                          ['--with-track-baseline', '--unknown'],
                          ['--with-track-baseline', '--with-flashlight-baseline'] * 2):
                failed = subprocess.run(command[:7] + flags, text=True, capture_output=True, timeout=10)
                with self.subTest(flags=flags):
                    self.assertNotEqual(failed.returncode, 0)

    def test_writer_rejects_nonzero_transport_even_with_exact_flashlight_marker(self):
        g = self.guard()
        for code, output in ((1, FLASHLIGHT_RED), (0, ''), (0, 'compile failed'),
                             (0, FLASHLIGHT_RED + '\n' + FLASHLIGHT_RED),
                             (0, FLASHLIGHT_RED + '\nREFERENCE_SETTINGS_FAIL: interrupted')):
            with tempfile.TemporaryDirectory(prefix='flashlight-ui-bad-writer-', dir=os.environ.get('TMPDIR')) as folder:
                report = Path(folder) / 'report.txt'
                report.write_text('sentinel\n')
                argv = ['guard', 'fixture-device', 'fixture-bundle', FLASHLIGHT_MODE, str(report)]
                with mock.patch('sys.argv', argv), mock.patch('subprocess.run', return_value=SimpleNamespace(
                        returncode=code, stdout=output)), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ValueError):
                    g['main']()
                self.assertEqual(report.read_text(), 'sentinel\n')

    def test_legacy_default_and_track_only_simple_suite_semantics_remain_unchanged(self):
        g = self.guard()
        source = '1234567890' * 4
        current = 'REFERENCE_SETTINGS_UIKIT_PASS: 1 assertions; legacy guard input; simulator fixture boundary only'
        for tracks in (False, True):
            lines = ['REFERENCE_UIKIT_SOURCE_COMMIT: ' + source, g['NEGATIVE'], g['MEDIA_NEGATIVE']]
            if tracks:
                lines.append(g['TRACK_NEGATIVE'])
            lines.append(current)
            self.assertEqual(g['validate_completed_suite']('\n'.join(lines), source, media_tracks=tracks), current)
        startup = 'NATIVE_STARTUP_PASS: 1 executed production-startup/hook/attachment checks'
        self.assertEqual(g['validate_startup_report'](startup), startup)


class FlashlightUIKitSourceContracts(unittest.TestCase):
    """These Linux checks prove authored wiring only; Swift/UIKit remains unexecuted."""
    def test_same_uikit_harness_forces_inert_original_flashlight_delegate_before_fourth_red(self):
        app = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertIn(FLASHLIGHT_MODE, app, 'The real harness lacks the fourth historical UI mode')
        start = app.index('if ProcessInfo.processInfo.arguments.contains("' + FLASHLIGHT_MODE + '")')
        end = app.index('\n        checkBasic(basicTable', start)
        body = app[start:end]
        for token in ('find(basicTable, id: "TOGGLE_FLASHLIGHT")',
                      'checkInert(basicTable, flashlight, nav)',
                      'nav.topViewController === basic', FLASHLIGHT_RED):
            self.assertIn(token, body)
        self.assertLess(body.index('checkInert('), body.index('finish('))
        inert = app.split('private func checkInert(', 1)[1].split('\n    private func ', 1)[0]
        for token in ('!target.isUserInteractionEnabled', 'target.selectionStyle == .none',
                      'target.accessibilityTraits.contains(.notEnabled)', 'tap(table, path)',
                      'samePreferences(before)', 'zip(nav.viewControllers, stack)',
                      'presentedViewController === presented'):
            self.assertIn(token, inert)
        self.assertIn('table.delegate?.tableView?(table, didSelectRowAt: path)', app)
        for marker in ('REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE:',
                       'MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE:', 'MEDIA_TRACKS_SETTINGS_BASELINE_EXPECTED_FAILURE:'):
            self.assertIn(marker, app)

    def test_current_ten_identity_set_and_bidirectional_app_replacements_cover_every_basic_row(self):
        app = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertIn('let expectedBasicCount = 10', app, 'Current UIKit must expect all ten basics')
        self.assertRegex(app, r'#if REFERENCE_SETTINGS_CURRENT \|\| SYSTEM_MUTE_BASELINE\s+case "flashlight": return \.flashlight\s+#endif')
        self.assertIn('#elseif FLASHLIGHT_BASELINE\n        let expectedBasicCount = 8', app)
        self.assertIn('let implementedEntries = entries.filter { $0["available"] as? Bool == true }', app)
        identity = app.split('let currentBasicIdentities: Set<String> = [', 1)[1].split(']', 1)[0]
        self.assertEqual(set(re.findall(r'"([A-Z_]+)"', identity)), {
            'SYSTEM_SCREENSHOT', 'SYSTEM_CONTROLCENTER', 'SYSTEM_COVER', 'SYSTEM_LOCKSCREEN',
            'SYSTEM_SWITCHER', 'PLAYPAUSE_MEDIA', 'PREVIOUS_MEDIA', 'NEXT_MEDIA', 'TOGGLE_FLASHLIGHT', 'SYSTEM_MUTE'})
        self.assertIn('Set(implementedEntries.compactMap { $0["id"] as? String }) == currentBasicIdentities', app)
        self.assertIn('for entry in implementedEntries {', app)
        self.assertIn('for entry in implementedEntries {', app.split('let previousActions = actions', 1)[1])
        self.assertNotIn('eight single-value replacements', app)
        self.assertIn('ten single-value replacements', app)
        for token in ('"开关手电"', 'basic selection did not replace the single value',
                      'basic checkmark not exclusive/current', 'Home summary did not refresh',
                      'App-to-basic replacement is not a single value',
                      'basic-to-App replacement is not a single record',
                      'App replacement changed enable state', 'Home App summary did not refresh'):
            self.assertIn(token, app)

    def test_runner_fetches_and_verifies_baseline_resource_without_new_closed_schema(self):
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        self.assertIn('Tests/flashlight_baseline.json', runner, 'Runner must bind old UI to its own frozen manifest')
        for token in ('925df18141606b75f71c77ddd998ad2baa237efe',
                      'git -C "$ROOT" fetch --no-tags --depth=1 origin "$FLASHLIGHT_SETTINGS_BASELINE"',
                      'git -C "$ROOT" show "$FLASHLIGHT_SETTINGS_BASELINE:$path"',
                      'assert len(frozen[\'frozen\']) == 26',
                      'FLASHLIGHT_UIKIT_BASELINE_BYTES_VERIFIED:',
                      'run_reference_case "$FLASHLIGHT_UI" flashlight-baseline ' + FLASHLIGHT_MODE):
            self.assertIn(token, runner)
        selection = runner.split('run_reference_case() {', 1)[1].split('    python3 - "$app/Info.plist"', 1)[0]
        self.assertIn('[ "$label" = flashlight-baseline ]', selection)
        self.assertIn('cp "$source_root/Preferences/Resources/SettingsReference.json"', selection)
        self.assertIn('compile_flag=-DFLASHLIGHT_BASELINE', selection)
        cases = re.findall(r'^run_reference_case .*$', runner, re.M)
        self.assertEqual([line.split()[2] for line in cases],
                         ['reference-baseline', 'media-baseline', 'track-baseline', 'flashlight-baseline',
                          'system-mute-baseline', 'reference-fixed'])
        self.assertLess(runner.index(cases[-1]), runner.index('bash "$ROOT/ci/native-startup-smoke.sh"'))
        # Exercise the actual bash feature selector; no xcrun/Apple invocation.
        start = runner.index('    local compile_flag=-DREFERENCE_SETTINGS_CURRENT')
        end = runner.index('    python3 - "$app/Info.plist"', start)
        script = ('set -euo pipefail\nchoose() {\nlocal label="$1"\n' + runner[start:end] +
                  'printf "%s\\n" "$compile_flag"\n}\n' +
                  '\n'.join('choose ' + label for label in
                            ('reference-baseline', 'media-baseline', 'track-baseline', 'flashlight-baseline', 'reference-fixed')))
        result = subprocess.run(['bash', '-c', script], text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['-DMEDIA_PLAY_PAUSE_UNAVAILABLE'] * 2 +
                         ['-DMEDIA_TRACKS_UNAVAILABLE', '-DFLASHLIGHT_BASELINE', '-DREFERENCE_SETTINGS_CURRENT'])

    def test_actual_runner_byte_verifier_accepts_only_the_eight_frozen_baseline_inputs(self):
        from system_mute_baseline import accepted_flashlight_source as accepted_source
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        blocks = re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)", runner, re.S)
        verifier = next(block for block in blocks if 'FLASHLIGHT_UIKIT_BASELINE_BYTES_VERIFIED:' in block)
        manifest = json.loads((ROOT / 'Tests/flashlight_baseline.json').read_bytes())
        self.assertEqual(manifest['baseline'], '925df18141606b75f71c77ddd998ad2baa237efe')
        self.assertEqual(len(manifest['frozen']), 26)
        loop = runner.split('FLASHLIGHT_UI="$WORK/accepted-0111-ui"', 1)[1].split('; do', 1)[0]
        relative_paths = loop.split('for path in ', 1)[1].replace('\\\n', ' ').split()
        self.assertEqual(len(relative_paths), 8)
        self.assertIn('Preferences/Resources/SettingsReference.json', relative_paths)
        with tempfile.TemporaryDirectory(prefix='flashlight-ui-frozen-', dir=os.environ.get('TMPDIR')) as folder:
            accepted, report = Path(folder) / 'accepted', Path(folder) / 'report.txt'
            originals = {}
            for relative in relative_paths:
                # The full source suite runs before runner fetches on shallow
                # CI. Use the exact digest-checked inverse, never assume that
                # the old commit is already present in the checkout.
                data = accepted_source(relative).encode('utf-8')
                originals[relative] = data
                target = accepted / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            command = [sys.executable, '-B', '-', str(accepted), str(ROOT), str(report)]
            verified = subprocess.run(command, input=verifier, text=True, capture_output=True, timeout=10)
            self.assertEqual(verified.returncode, 0, verified.stderr)
            self.assertEqual(report.read_text(), 'FLASHLIGHT_UIKIT_BASELINE_BYTES_VERIFIED: '
                             'eight exact accepted 0.1.11 source/resource inputs\n')
            for relative, original in originals.items():
                target = accepted / relative
                for missing in (False, True):
                    report.unlink(missing_ok=True)
                    if missing:
                        target.unlink()
                    else:
                        target.write_bytes(original + b'\n// unrelated byte drift\n')
                    failed = subprocess.run(command, input=verifier, text=True, capture_output=True, timeout=10)
                    with self.subTest(path=relative, missing=missing):
                        self.assertNotEqual(failed.returncode, 0)
                        self.assertIn('AssertionError', failed.stderr)
                        self.assertFalse(report.exists(), 'Unverified inputs must never emit attestation')
                    target.write_bytes(original)
            resource = 'Preferences/Resources/SettingsReference.json'
            self.assertNotEqual((ROOT / resource).read_bytes(), originals[resource])
            (accepted / resource).write_bytes((ROOT / resource).read_bytes())
            wrong_schema = subprocess.run(command, input=verifier, text=True, capture_output=True, timeout=10)
            self.assertNotEqual(wrong_schema.returncode, 0, 'Never feed the nine-action schema to historical controller')
            self.assertFalse(report.exists())

    def test_actual_full_startup_graph_matches_makefile_and_historical_ui_graphs_stay_old(self):
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        startup = (ROOT / 'ci/native-startup-smoke.sh').read_text()
        makefile = (ROOT / 'Makefile').read_text()
        expected = next(line.split('=', 1)[1].split() for line in makefile.splitlines()
                        if line.startswith('TapLock_FILES = '))
        self.assertEqual(expected.count('Sources/FlashlightAction.swift'), 1)
        # Run the real source-list extraction plus the real swiftc argument
        # expansion with an argv-only xcrun substitute, never an Apple compiler.
        start = startup.index('SOURCES=()')
        end = startup.index('\ncodesign --force --sign - "$LIBS/TapLockStartup.dylib"', start)
        shell = ('set -euo pipefail\nROOT="$1"\nTARGET=fixture SDK=fixture LIBS=fixture\n'
                 'xcrun() { python3 -c \'import json,sys; print(json.dumps(sys.argv[1:]))\' "$@"; }\n' +
                 startup[start:end])
        result = subprocess.run(['bash', '-c', shell, 'source-graph-unit', str(ROOT)],
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout)
        actual = [str(Path(arg).relative_to(ROOT)) for arg in args if arg.startswith(str(ROOT) + '/')
                  and arg.endswith('.swift') and not arg.endswith('/Tests/NativeHookReactivation.swift')]
        self.assertEqual(actual, expected)
        self.assertIn('bash "$ROOT/ci/native-startup-smoke.sh" "$DEVICE"', runner)
        self.assertNotIn('FlashlightAction.swift', runner.split('run_reference_case() {', 1)[0])

    def test_real_attestation_writer_is_nonterminal_metadata_for_the_exact_suite_parser(self):
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        blocks = re.findall(r"<<'PY'\n(.*?)\nPY(?:\n|$)", runner, re.S)
        selected = [block for block in blocks if 'FLASHLIGHT_UIKIT_BASELINE_BYTES_VERIFIED:' in block]
        self.assertEqual(len(selected), 1, 'Missing actual flashlight byte-attestation report writer')
        tree = ast.parse(selected[0])
        writers = [node for node in tree.body if isinstance(node, ast.With)]
        self.assertEqual(len(writers), 1)
        with tempfile.TemporaryDirectory(prefix='flashlight-ui-metadata-', dir=os.environ.get('TMPDIR')) as folder:
            target = Path(folder) / 'report.txt'
            scope = {'sys': SimpleNamespace(argv=['writer', '', '', str(target)])}
            exec(compile(ast.Module(body=writers, type_ignores=[]), '<actual UIKit attestation writer>', 'exec'), scope)
            metadata = target.read_text()
        self.assertTrue(metadata.startswith('FLASHLIGHT_UIKIT_BASELINE_BYTES_VERIFIED:'))
        helper = FlashlightCompletionGuardContracts()
        good, modes = helper.actual_written_report()
        lines = good.splitlines(keepends=True)
        report = lines[0] + metadata + ''.join(lines[1:])
        g = helper.guard()
        self.assertEqual(g['validate_completed_suite'](report, '1234567890' * 4,
                         media_tracks=True, flashlight=True), modes[-1][1])
        with self.assertRaises(ValueError):
            g['validate_completed_run'](0, metadata, FLASHLIGHT_MODE)


if __name__ == '__main__':
    unittest.main(verbosity=2)
