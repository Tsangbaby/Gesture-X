"""Historical media contracts restore newer stages explicitly before reads.

Native provider and current CI gates stay live. Historical hashes and malformed
record coverage are not enlarged to accommodate a newly valid action.
"""
import json
from pathlib import Path
import unittest
from bottom_swipe_baseline import accepted_media_tracks_source as track_accepted_source

ROOT = Path(__file__).resolve().parents[1]


class MediaPlayPauseContracts(unittest.TestCase):
    def test_only_play_pause_is_newly_available_and_uses_single_action_storage(self):
        reference = json.loads(track_accepted_source('Preferences/Resources/SettingsReference.json'))
        rows = {row['id']: row for row in reference['basicActions']}
        self.assertTrue(rows['PLAYPAUSE_MEDIA']['available'], 'original Play/Pause row remains disabled')
        self.assertEqual(rows['PLAYPAUSE_MEDIA']['actionKind'], 'playPause')
        self.assertEqual(rows['PLAYPAUSE_MEDIA']['title'], '播放/暂停')
        self.assertEqual(rows['PLAYPAUSE_MEDIA']['referenceActionNumber'], 37)
        self.assertEqual({r['id'] for r in rows.values() if r['available']}, {
            'SYSTEM_SCREENSHOT', 'SYSTEM_CONTROLCENTER', 'SYSTEM_COVER',
            'SYSTEM_LOCKSCREEN', 'SYSTEM_SWITCHER', 'PLAYPAUSE_MEDIA',
        })
        prefs = track_accepted_source('Shared/Preferences.swift')
        for token in ('case playPause', 'kind == "playPause", record.count == 1',
                      'return .playPause', 'case .playPause:', 'record = ["kind": "playPause"]'):
            self.assertIn(token, prefs)
        self.assertEqual(prefs.count('CFNotificationCenterPostNotification('), 2)
        settings = track_accepted_source('Preferences/SettingsController.swift')
        self.assertIn('case "playPause": return .playPause', settings)
        self.assertNotIn('MediaRemote', settings)
        self.assertNotIn('MediaPlayPauseAction', settings)

    def test_native_toggle_is_one_guarded_byte_returning_c_command_and_no_fallback(self):
        import re
        from test_source import source
        path = ROOT / 'Sources/MediaPlayPauseAction.swift'
        self.assertTrue(path.is_file(), 'missing single-call media provider')
        text = source('Sources/MediaPlayPauseAction.swift')
        for token in ('@convention(c) (UInt32, AnyObject?) -> UInt8',
                      'private static let sendCommand: SendCommand?',
                      'dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_LOCAL)',
                      'dlsym(handle, "MRMediaRemoteSendCommand")', 'dlclose(handle)',
                      'Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                      'let send = sendCommand', 'return send(2, nil) != 0'):
            self.assertIn(token, text)
        self.assertEqual(text.count('send(2, nil)'), 1)
        body = text.split('static func toggle()', 1)[1]
        self.assertLess(body.index('LockAction.unlockedManager()'), body.index('let send = sendCommand'))
        for forbidden in ('asyncAfter', 'DispatchQueue', 'Timer(', 'MPMusicPlayer',
                          'GetNowPlaying', 'UIApplication', 'perform(', 'for ', 'while '):
            self.assertNotIn(forbidden, text)
        dispatch = source('Sources/HomeDoubleTap.swift').split('func recognized(', 1)[1]
        self.assertIn('case .playPause:\n            MediaPlayPauseAction.toggle()', dispatch)
        self.assertEqual(dispatch.count('MediaPlayPauseAction.toggle()'), 1)
        self.assertLess(dispatch.index('isBlankHit('), dispatch.index('MediaPlayPauseAction.toggle()'))
        files = re.search(r'^TapLock_FILES = (.+)$', (ROOT / 'Makefile').read_text(), re.M)[1].split()
        self.assertIn('Sources/MediaPlayPauseAction.swift', files)
        self.assertNotIn('MediaPlayPause', (ROOT / 'Preferences/Makefile').read_text())

    def test_exact_inverse_restores_protected_019_without_refreshing_older_fixtures(self):
        import importlib.util
        import hashlib
        self.assertIsNotNone(importlib.util.find_spec('media_play_pause_baseline'),
                             'missing exact media-only inverse')
        from media_play_pause_baseline import FIXTURE, invert_media_play_pause
        self.assertEqual(FIXTURE['baseline'], '1e2b7ef11a5f743b8db122c02d9a5478d2f20bfa')
        self.assertEqual(set(FIXTURE['hunks']), {
            'Makefile', 'Shared/Preferences.swift', 'Sources/HomeDoubleTap.swift',
            'Preferences/SettingsController.swift', 'Preferences/Resources/SettingsReference.json',
            'control', 'Preferences/Resources/Info.plist',
        })
        for path, digest in FIXTURE['frozen'].items():
            text = track_accepted_source(path)
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256(invert_media_play_pause(path, text).encode()).hexdigest(), digest)

    def test_media_inverse_rejects_missing_duplicate_reordered_drift_and_crlf(self):
        import importlib.util
        self.assertIsNotNone(importlib.util.find_spec('media_play_pause_baseline'))
        from media_play_pause_baseline import FIXTURE, invert_media_play_pause
        for path, hunks in FIXTURE['hunks'].items():
            text = track_accepted_source(path)
            invert_media_play_pause(path, text)
            mutations = [text + '\n// unrelated drift\n', text.replace('\n', '\r\n')]
            for h in hunks:
                mutations += [text.replace(h['after'], '', 1), text + h['after']]
            if len(hunks) > 1:
                mutations.append(text.replace(hunks[0]['after'], '__SWAP__', 1).replace(
                    hunks[-1]['after'], hunks[0]['after'], 1).replace('__SWAP__', hunks[-1]['after'], 1))
            for mutant in mutations:
                with self.subTest(path=path), self.assertRaises(AssertionError):
                    invert_media_play_pause(path, mutant)

    def test_actual_swift_loader_uikit_and_package_gates_are_wired_before_upload(self):
        runner = ROOT / 'ci/media-play-pause-smoke.sh'
        self.assertTrue(runner.is_file(), 'missing real Swift media loader regression')
        text = runner.read_text()
        for token in ('MEDIA_PLAY_PAUSE_BASELINE_EXPECTED_FAILURE', 'MEDIA_PLAY_PAUSE_RUNTIME_PASS:',
                      '1e2b7ef11a5f743b8db122c02d9a5478d2f20bfa',
                      'original.count(old) == count', 'restored == original',
                      'Tests/MediaPlayPauseRuntimeTests.swift', 'Tests/MediaRemoteFixture.m',
                      'Sources/MediaPlayPauseAction.swift', '--missing-library', '--missing-symbol', '--working'):
            self.assertIn(token, text)
        steps = json.loads((ROOT / '.github/workflows/build.yml').read_text())['jobs']['roothide']['steps']
        runtime = next(s['run'] for s in steps if s['name'] == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/media-play-pause-smoke.sh', runtime)
        package = next(s['run'] for s in steps if s['name'] == 'Compile and package RootHide')
        self.assertIn('MEDIA_PLAY_PAUSE_TESTS.txt', package)
        ui = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        self.assertIn('media-baseline --expect-media-baseline-failure', ui)
        harness = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertIn('case "playPause": return .playPause', harness)
        self.assertIn('MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE:', harness)
        self.assertIn('ten single-value replacements', harness)
        verifier = (ROOT / 'ci/verify_package.py').read_text()
        self.assertIn('b"MRMediaRemoteSendCommand"', verifier)
        self.assertIn('Media provider leaked into Settings binary', verifier)

    def test_older_inverse_is_still_strict_unless_media_opt_in_is_explicit(self):
        from settings_layout_baseline import accepted_source
        from bottom_swipe_baseline import accepted_layout_source
        path = 'Preferences/SettingsController.swift'
        from unittest import mock
        # Exercise the old layout default against the media stage, after newer
        # flashlight and track restoration, so outer rejection cannot pass it.
        stage = track_accepted_source(path)
        with mock.patch('settings_layout_baseline.ROOT') as root:
            file = root.__truediv__.return_value
            file.is_file.return_value = True
            file.read_bytes.return_value = stage.encode('utf-8')
            with self.assertRaises(AssertionError):
                accepted_source(path)
        self.assertIn('TapLockPreferences.writeAction(.appSwitcher)', accepted_layout_source(path, media_play_pause=True, media_tracks=True, flashlight=True))

    def test_media_swift_completion_guard_rejects_nonzero_wrong_duplicate_and_extra_output(self):
        import tempfile
        from types import SimpleNamespace
        from unittest import mock
        runner = ROOT / 'ci/media-play-pause-smoke.sh'
        self.assertTrue(runner.is_file())
        block = runner.read_text().rsplit("<<'PY'\n", 1)[1].split('\nPY', 1)[0]
        positive = 'MEDIA_PLAY_PAUSE_RUNTIME_PASS: 1 assertions; mode=--working; actual Swift/C loader fixture, NOT handset playback proof'
        for status, output, accepted in (
            (0, positive + '\n', True), (1, positive, False), (0, '', False),
            (0, positive + '\n' + positive, False), (0, positive + '\nextra', False),
            (0, positive + ' ', False), (0, positive.replace(': 1 assertions', ': 0 assertions'), False),
            (0, positive.replace('--working', '--missing-symbol'), False),
            (0, 'MEDIA_PLAY_PAUSE_RUNTIME_FAIL: wrong state', False),
        ):
            with self.subTest(status=status, output=output), tempfile.TemporaryDirectory() as directory:
                argv = ['guard', 'fixture-executable', str(Path(directory) / 'report'), '--working', directory]
                with mock.patch('sys.argv', argv), mock.patch('builtins.print'), mock.patch(
                        'subprocess.run', return_value=SimpleNamespace(returncode=status, stdout=output)):
                    failed = False
                    try:
                        exec(compile(block, '<actual media completion guard>', 'exec'), {})
                    except SystemExit:
                        failed = True
                self.assertEqual(not failed, accepted)

    def test_media_uikit_guard_accepts_only_its_exact_baseline_marker(self):
        import runpy
        guard = runpy.run_path(str(ROOT / 'ci/reference_settings_guard.py'))['validate_completed_run']
        marker = 'MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE: original play/pause row is disabled'
        mode = '--expect-media-baseline-failure'
        self.assertEqual(guard(0, marker + '\n', mode), marker)
        for code, output in ((1, marker), (0, ''), (0, marker + '\n' + marker),
                             (0, 'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE: root navigation differs from reference'),
                             (0, marker + '\nREFERENCE_SETTINGS_UIKIT_PASS: 1 assertions; ok; simulator fixture boundary only')):
            with self.subTest(output=output), self.assertRaises(ValueError):
                guard(code, output, mode)

    def test_current_and_both_legacy_ui_compiles_always_receive_a_nonempty_scalar_feature_flag(self):
        import subprocess
        body = (ROOT / 'ci/settings-construction-smoke.sh').read_text().split('run_reference_case() {', 1)[1]
        selection = '    local compile_' + body.split('    local compile_', 1)[1].split('    python3 - ', 1)[0]
        command = '    xcrun swiftc' + body.split('    xcrun swiftc', 1)[1].split('\n    codesign', 1)[0]
        shell = '''set -euo pipefail
xcrun() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"; }
probe() {
    local label="$1" source_root=/source ROOT=/root app=/app TARGET=target SDK=sdk WORK=/work
''' + selection + command + '''
}
probe reference-baseline
probe media-baseline
probe reference-fixed
'''
        p = subprocess.run(['bash', '-c', shell], capture_output=True, text=True, timeout=10)
        self.assertEqual(p.returncode, 0, p.stderr)
        commands = [json.loads(line) for line in p.stdout.splitlines()]
        self.assertEqual(len(commands), 3)
        for args, flag in zip(commands, ['-DMEDIA_PLAY_PAUSE_UNAVAILABLE', '-DMEDIA_PLAY_PAUSE_UNAVAILABLE', '-DREFERENCE_SETTINGS_CURRENT']):
            self.assertEqual([a for a in args if a.startswith('-D')], [flag])
        self.assertNotIn('compile_flags=()', body)

    def test_workflow_rejects_false_green_settings_child_with_no_completed_reports(self):
        import os
        import subprocess
        import tempfile
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_text())
        step = next(s['run'] for s in workflow['jobs']['roothide']['steps']
                    if s['name'] == 'Settings constructor regression (iOS Simulator fixture)')
        with tempfile.TemporaryDirectory() as directory:
            environment = dict(os.environ, RUNNER_TEMP=directory, GITHUB_SHA='c' * 40)
            shell = 'set -euo pipefail\nbash() { return 0; }\n' + step
            p = subprocess.run(['bash', '-c', shell], cwd=ROOT, env=environment,
                               capture_output=True, text=True, timeout=10)
            self.assertNotEqual(p.returncode, 0, 'child exit 0 without current UIKit/startup proof must fail the parent step')
        self.assertIn('--validate-suite', step)

    def test_completed_ui_suite_requires_exact_source_both_reds_and_one_current_green(self):
        import runpy
        module = runpy.run_path(str(ROOT / 'ci/reference_settings_guard.py'))
        self.assertTrue(callable(module.get('validate_completed_suite')), 'missing whole-suite completion validator')
        guard = module['validate_completed_suite']
        source = 'c' * 40
        header = 'REFERENCE_UIKIT_SOURCE_COMMIT: ' + source
        old = module['NEGATIVE']
        media = module['MEDIA_NEGATIVE']
        current = 'REFERENCE_SETTINGS_UIKIT_PASS: 1 assertions; six basic replacements; simulator fixture boundary only'
        good = '\n'.join([header, 'fixture boundary metadata', old, media, current]) + '\n'
        self.assertEqual(guard(good, source), current)
        for bad in [good.replace(header, ''), good + '\n' + header,
                    good.replace(source, 'd' * 40), good.replace(current, ''),
                    good.replace(media, ''), good.replace(old, ''), good + current + '\n',
                    good.replace(current, current.replace('1 assertions', '0 assertions')),
                    good.replace(old + '\n' + media, media + '\n' + old),
                    good + 'REFERENCE_SETTINGS_FAIL: interrupted\n']:
            with self.subTest(report=bad), self.assertRaises(ValueError):
                guard(bad, source)

    def test_parent_startup_report_requires_one_nonzero_production_execution_marker(self):
        import runpy
        module = runpy.run_path(str(ROOT / 'ci/reference_settings_guard.py'))
        self.assertTrue(callable(module.get('validate_startup_report')), 'missing startup completion validator')
        guard = module['validate_startup_report']
        marker = 'NATIVE_STARTUP_PASS: 1 executed production-startup/hook/attachment checks'
        self.assertEqual(guard(marker + '\nBoundary: fixtures only\n'), marker)
        for bad in ['', marker + '\n' + marker, marker.replace(': 1 executed', ': 0 executed'),
                    marker + '\nNATIVE_STARTUP_FAIL: interrupted', 'NATIVE_STARTUP_FAIL: no completion']:
            with self.subTest(report=bad), self.assertRaises(ValueError):
                guard(bad)


if __name__ == '__main__':
    unittest.main(verbosity=2)
