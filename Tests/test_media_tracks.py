"""Previous/next media are two exclusive actions, not a multi-action engine."""
import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRACKS = {
    'previousTrack': ('PREVIOUS_MEDIA', '上一首', 38, 20, 5),
    'nextTrack': ('NEXT_MEDIA', '下一首', 39, 21, 4),
}
OLDER_BASIC = {'SYSTEM_SCREENSHOT', 'SYSTEM_CONTROLCENTER', 'SYSTEM_COVER',
               'SYSTEM_LOCKSCREEN', 'SYSTEM_SWITCHER', 'PLAYPAUSE_MEDIA'}


class MediaTrackContracts(unittest.TestCase):
    def test_both_original_track_rows_are_saved_and_dispatched_as_independent_single_commands(self):
        reference = json.loads((ROOT / 'Preferences/Resources/SettingsReference.json').read_text())
        rows = {r['id']: r for r in reference['basicActions']}
        prefs = (ROOT / 'Shared/Preferences.swift').read_text()
        settings = (ROOT / 'Preferences/SettingsController.swift').read_text()
        dispatch = (ROOT / 'Sources/HomeDoubleTap.swift').read_text().split('func recognized(', 1)[1]
        provider = (ROOT / 'Sources/MediaPlayPauseAction.swift').read_text()
        for kind, (row_id, title, reference_action, slot, command) in TRACKS.items():
            row = rows[row_id]
            with self.subTest(kind=kind):
                self.assertTrue(row['available'], row_id + ' remains disabled')
                self.assertEqual((row['actionKind'], row['title'], row['referenceActionNumber'], row['referenceSlot']),
                                 (kind, title, reference_action, slot))
                for token in ('case ' + kind, 'kind == "' + kind + '", record.count == 1',
                              'case .' + kind + ':', 'record = ["kind": "' + kind + '"]'):
                    self.assertIn(token, prefs)
                self.assertIn('case "' + kind + '": return .' + kind, settings)
                call = 'MediaPlayPauseAction.' + kind + '()'
                self.assertIn('case .' + kind + ':\n            ' + call, dispatch)
                self.assertEqual(dispatch.count(call), 1)
                self.assertLess(dispatch.index('isBlankHit('), dispatch.index(call))
                body = provider.split('static func ' + kind + '() -> Bool {', 1)[1].split('\n    }', 1)[0]
                for token in ('Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                              'let send = sendCommand', 'return send(' + str(command) + ', nil) != 0'):
                    self.assertIn(token, body)
                self.assertLess(body.index('LockAction.unlockedManager()'), body.index('let send = sendCommand'))
                self.assertEqual(provider.count('send(' + str(command) + ', nil)'), 1)
        self.assertEqual({r['id'] for r in rows.values() if r['available']},
                         OLDER_BASIC | {row[0] for row in TRACKS.values()})
        self.assertEqual(prefs.count('CFNotificationCenterPostNotification('), 2)
        self.assertNotIn('MediaRemote', settings)
        self.assertNotIn('MediaPlayPauseAction', settings)
        self.assertEqual(provider.count('dlopen('), 1)
        self.assertEqual(provider.count('dlsym('), 1)
        self.assertIn('@convention(c) (UInt32, AnyObject?) -> UInt8', provider)
        code = re.sub(r'(?m)^\s*//.*$', '', provider)
        for forbidden in ('asyncAfter', 'DispatchQueue', 'Timer(', 'MPMusicPlayer', 'GetNowPlaying',
                          'UIApplication', 'perform(', 'for ', 'while '):
            self.assertNotIn(forbidden, code)


    def test_active_release_identity_is_bumped_without_rewriting_historical_fixtures(self):
        from release_contract import EXPECTED_RELEASE_VERSION
        self.assertEqual(EXPECTED_RELEASE_VERSION, '0.1.11')

    def test_native_and_real_uikit_tracks_are_mandatory_exact_source_ci_gates(self):
        runner = ROOT / 'ci/media-tracks-smoke.sh'
        self.assertTrue(runner.is_file(), 'Missing actual Swift/C track runtime gate')
        text = runner.read_text()
        for token in ('cd480bfe09c7080b0523e1c73910b8af617edb01',
                      'LegacyPreferences.swift', 'Tests/MediaTracksRuntimeTests.swift',
                      'Tests/MediaRemoteFixture.m', 'Sources/MediaPlayPauseAction.swift',
                      '--baseline-next', '--baseline-previous', '--missing-library',
                      '--missing-symbol', '--working', 'MRMediaRemoteSendCommand',
                      'ci/media_tracks_guard.py'):
            self.assertIn(token, text)
        self.assertIn('MEDIA_TRACKS_SWIFT_EXECUTION_PASS:', (ROOT / 'ci/media_tracks_guard.py').read_text())
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_text())
        steps = workflow['jobs']['roothide']['steps']
        native = next(s['run'] for s in steps if s['name'] == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/media-tracks-smoke.sh', native)
        self.assertIn('python3 -B ci/media_tracks_guard.py --validate-suite "$RUNNER_TEMP/MEDIA_TRACKS_TESTS.txt" "$GITHUB_SHA"', native)
        settings = next(s['run'] for s in steps if s['name'] == 'Settings constructor regression (iOS Simulator fixture)')
        self.assertIn('--validate-suite', settings)
        self.assertIn('--with-track-baseline', settings)
        package = next(s['run'] for s in steps if s['name'] == 'Compile and package RootHide')
        self.assertIn('cp "$RUNNER_TEMP/MEDIA_TRACKS_TESTS.txt" "$OUT_DIR/MEDIA_TRACKS_TESTS.txt"', package)
        ui = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        for token in ('"上一首"', '"下一首"', '--expect-track-baseline-failure',
                      'MEDIA_TRACKS_SETTINGS_BASELINE_EXPECTED_FAILURE:', 'MEDIA_TRACKS_UNAVAILABLE',
                      'case "nextTrack": return .nextTrack', 'case "previousTrack": return .previousTrack',
                      'eight single-value replacements'):
            self.assertIn(token, ui)
        startup = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        self.assertIn('run_reference_case "$TRACK_UI" track-baseline --expect-track-baseline-failure', startup)
        self.assertIn("Tests/media_tracks_baseline.json", startup)


class MediaTrackBaselineContracts(unittest.TestCase):
    def test_exact_candidate_inverse_restores_all_26_accepted_010_production_inputs(self):
        from media_tracks_baseline import FIXTURE, invert_media_tracks
        self.assertEqual(FIXTURE['baseline'], 'cd480bfe09c7080b0523e1c73910b8af617edb01')
        self.assertEqual(len(FIXTURE['frozen']), 26)
        self.assertEqual(set(FIXTURE['hunks']), {
            'Shared/Preferences.swift', 'Sources/HomeDoubleTap.swift', 'Sources/MediaPlayPauseAction.swift',
            'Preferences/SettingsController.swift', 'Preferences/Resources/SettingsReference.json',
            'control', 'Preferences/Resources/Info.plist',
        })
        self.assertEqual(sum(len(v) for v in FIXTURE['hunks'].values()), 11)
        for path, digest in FIXTURE['frozen'].items():
            with self.subTest(path=path):
                text = (ROOT / path).read_bytes().decode('utf-8')
                before = invert_media_tracks(path, text)
                self.assertEqual(hashlib.sha256(before.encode()).hexdigest(), digest)
                if path == 'Sources/MediaPlayPauseAction.swift':
                    self.assertTrue(text.startswith(before.rsplit('\n}', 1)[0]),
                                    'Existing loader, native ABI and toggle body must stay byte-exact')

    def test_track_inverse_rejects_missing_duplicate_order_crlf_and_unrelated_drift(self):
        from media_tracks_baseline import FIXTURE, invert_media_tracks
        for path, edits in FIXTURE['hunks'].items():
            text = (ROOT / path).read_bytes().decode('utf-8')
            invert_media_tracks(path, text)
            mutants = [text + '\n// unrelated drift\n', text.replace('\n', '\r\n')]
            for h in edits:
                mutants.extend([text.replace(h['after'], '', 1), text + h['after']])
            if len(edits) > 1:
                self.assertNotIn('__SWAP__', text)
                mutants.append(text.replace(edits[0]['after'], '__SWAP__', 1).replace(
                    edits[-1]['after'], edits[0]['after'], 1).replace('__SWAP__', edits[-1]['after'], 1))
            for mutant in mutants:
                with self.subTest(path=path), self.assertRaises(AssertionError):
                    invert_media_tracks(path, mutant)

    def test_historical_layers_do_not_implicitly_accept_tracks_or_refresh_old_hashes(self):
        from media_tracks_baseline import accepted_source as track_source
        from media_play_pause_baseline import invert_media_play_pause
        from settings_layout_baseline import accepted_source
        path = 'Preferences/SettingsController.swift'
        current = (ROOT / path).read_text()
        with self.assertRaises(AssertionError):
            invert_media_play_pause(path, current)
        with self.assertRaises(AssertionError):
            accepted_source(path, media_play_pause=True)
        invert_media_play_pause(path, track_source(path))
        restored = accepted_source(path, media_play_pause=True, media_tracks=True)
        self.assertIn('TapLockPreferences.writeAction(.appSwitcher)', restored)
        self.assertNotIn('return .nextTrack', restored)
        self.assertNotIn('return .previousTrack', restored)


class MediaTrackCompletionGuardContracts(unittest.TestCase):
    """Synthetic guard INPUTS only; never reported as real native/UI execution."""
    def native_guard(self):
        import runpy
        return runpy.run_path(str(ROOT / 'ci/media_tracks_guard.py'))

    def test_each_actual_native_mode_requires_exact_exit_nonzero_assertions_and_one_marker(self):
        guard = self.native_guard()['validate_completed_run']
        suffix = '; actual Swift/C loader fixture, NOT handset track-change proof'
        for mode in ('--missing-library', '--missing-symbol', '--working'):
            good = 'MEDIA_TRACKS_RUNTIME_PASS: 1 assertions; mode=' + mode + suffix
            self.assertEqual(guard(0, good + '\n', mode), good)
            for code, bad in [(1, good), (0, ''), (0, good + '\n\n'),
                              (0, good + '\n' + good), (0, 'prefix ' + good),
                              (0, good.replace(': 1 assertions', ': 0 assertions')),
                              (0, good.replace('mode=' + mode, 'mode=--other'))]:
                with self.subTest(mode=mode, code=code, output=bad), self.assertRaises(ValueError):
                    guard(code, bad, mode)
        for mode, kind in (('--baseline-next', 'nextTrack'), ('--baseline-previous', 'previousTrack')):
            failure = 'MEDIA_TRACKS_RUNTIME_FAIL: persisted ' + kind + ' action is unavailable'
            self.assertIn(kind, guard(1, failure + '\n', mode))
            for code, bad in [(0, failure), (2, failure), (1, ''), (1, failure + '\n\n'),
                              (1, failure + '\n' + failure), (1, 'compile failure')]:
                with self.subTest(mode=mode, code=code, output=bad), self.assertRaises(ValueError):
                    guard(code, bad, mode)
        with self.assertRaises(ValueError):
            guard(0, '', '--unknown')

    def test_native_suite_requires_exact_source_both_behavior_reds_three_modes_and_terminal(self):
        g = self.native_guard()
        source = '1234567890' * 4
        lines = ['MEDIA_TRACKS_SOURCE_COMMIT: ' + source]
        for mode in ('--baseline-next', '--baseline-previous'):
            lines.extend([g['baseline_failure'](mode), g['baseline_marker'](mode)])
        lines.extend('MEDIA_TRACKS_RUNTIME_PASS: 1 assertions; mode=' + mode +
                     '; actual Swift/C loader fixture, NOT handset track-change proof'
                     for mode in ('--missing-library', '--missing-symbol', '--working'))
        lines.append(g['SUMMARY'])
        good = '\n'.join(lines) + '\n'
        self.assertEqual(g['validate_completed_suite'](good, source), g['SUMMARY'])
        for i in range(len(lines)):
            for bad in ('\n'.join(lines[:i] + lines[i+1:]), good + lines[i] + '\n'):
                with self.subTest(line=i), self.assertRaises(ValueError):
                    g['validate_completed_suite'](bad, source)
        for bad in (good.replace(source, 'a' * 40),
                    good.replace(lines[5], '__SWAP__').replace(lines[6], lines[5]).replace('__SWAP__', lines[6]),
                    good + 'MEDIA_TRACKS_RUNTIME_FAIL: interrupted\n',
                    good.replace(': 1 assertions', ': 0 assertions')):
            with self.subTest(report=bad), self.assertRaises(ValueError):
                g['validate_completed_suite'](bad, source)

    def test_uikit_four_stage_guard_requires_old_track_rows_and_remains_explicit_opt_in(self):
        import runpy
        g = runpy.run_path(str(ROOT / 'ci/reference_settings_guard.py'))
        marker = 'MEDIA_TRACKS_SETTINGS_BASELINE_EXPECTED_FAILURE: original previous/next rows are disabled'
        self.assertEqual(g['validate_completed_run'](0, marker, '--expect-track-baseline-failure'), marker)
        for code, bad in [(1, marker), (0, ''), (0, marker + '\n' + marker),
                          (0, marker + '\nREFERENCE_SETTINGS_FAIL: interrupted'),
                          (0, marker.replace('previous/next', 'next'))]:
            with self.subTest(code=code, output=bad), self.assertRaises(ValueError):
                g['validate_completed_run'](code, bad, '--expect-track-baseline-failure')
        source = '1234567890' * 4
        positive = 'REFERENCE_SETTINGS_UIKIT_PASS: 1 assertions; guard unit fixture; simulator fixture boundary only'
        lines = ['REFERENCE_UIKIT_SOURCE_COMMIT: ' + source, g['NEGATIVE'], g['MEDIA_NEGATIVE'], marker, positive]
        good = '\n'.join(lines)
        self.assertEqual(g['validate_completed_suite'](good, source, media_tracks=True), positive)
        with self.assertRaises(ValueError):
            g['validate_completed_suite'](good, source)
        for i in range(len(lines)):
            for bad in ('\n'.join(lines[:i] + lines[i+1:]), good + '\n' + lines[i]):
                with self.subTest(line=i), self.assertRaises(ValueError):
                    g['validate_completed_suite'](bad, source, media_tracks=True)
        for bad in (good.replace(source, 'a' * 40),
                    '\n'.join([lines[0], lines[1], lines[3], lines[2], lines[4]]),
                    good.replace(': 1 assertions', ': 0 assertions')):
            with self.subTest(report=bad), self.assertRaises(ValueError):
                g['validate_completed_suite'](bad, source, media_tracks=True)

    def test_real_native_parent_completion_command_rejects_zero_exit_child_without_report(self):
        import os
        import subprocess
        import tempfile
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_text())
        native = next(s['run'] for s in workflow['jobs']['roothide']['steps']
                      if s['name'] == 'Source and real Swift runtime tests')
        commands = [line for line in native.splitlines()
                    if line.startswith('python3 -B ci/media_tracks_guard.py --validate-suite ')]
        self.assertEqual(len(commands), 1)
        with tempfile.TemporaryDirectory(prefix='media-tracks-parent-', dir=os.environ.get('TMPDIR')) as folder:
            env = dict(os.environ, RUNNER_TEMP=folder, GITHUB_SHA='1234567890' * 4)
            result = subprocess.run(['bash', '-c', 'set -euo pipefail\n( exit 0 )\n' + commands[0]],
                                    cwd=ROOT, env=env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0, 'A child zero exit must not replace executed-test evidence')
        self.assertIn('FileNotFoundError', result.stderr)
        self.assertNotIn('MEDIA_TRACKS_SWIFT_EXECUTION_PASS:', result.stdout)

    def test_each_native_uikit_feature_flag_expands_as_one_scalar_bash_argument(self):
        import subprocess
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        start = runner.index('    local compile_flag=-DREFERENCE_SETTINGS_CURRENT')
        end = runner.index('    python3 - "$app/Info.plist"', start)
        logic = runner[start:end]
        script = ('set -euo pipefail\nchoose() {\nlocal label="$1"\n' + logic +
                  'printf "%s\\n" "$compile_flag"\n}\n' +
                  '\n'.join('choose ' + label for label in
                            ('reference-baseline', 'media-baseline', 'track-baseline', 'reference-fixed')))
        run = subprocess.run(['bash', '-c', script], text=True, capture_output=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.splitlines(), ['-DMEDIA_PLAY_PAUSE_UNAVAILABLE', '-DMEDIA_PLAY_PAUSE_UNAVAILABLE',
                                                  '-DMEDIA_TRACKS_UNAVAILABLE', '-DREFERENCE_SETTINGS_CURRENT'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
