"""Current media-action wiring; Swift/UIKit and handset evidence are separate."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MediaPlayPauseContracts(unittest.TestCase):
    def test_only_play_pause_is_newly_available_and_uses_single_action_storage(self):
        reference = json.loads((ROOT / 'Preferences/Resources/SettingsReference.json').read_text())
        rows = {row['id']: row for row in reference['basicActions']}
        self.assertTrue(rows['PLAYPAUSE_MEDIA']['available'], 'original Play/Pause row remains disabled')
        self.assertEqual(rows['PLAYPAUSE_MEDIA']['actionKind'], 'playPause')
        self.assertEqual(rows['PLAYPAUSE_MEDIA']['title'], '播放/暂停')
        self.assertEqual(rows['PLAYPAUSE_MEDIA']['referenceActionNumber'], 37)
        self.assertEqual({r['id'] for r in rows.values() if r['available']}, {
            'SYSTEM_SCREENSHOT', 'SYSTEM_CONTROLCENTER', 'SYSTEM_COVER',
            'SYSTEM_LOCKSCREEN', 'SYSTEM_SWITCHER', 'PLAYPAUSE_MEDIA',
        })
        prefs = (ROOT / 'Shared/Preferences.swift').read_text()
        for token in ('case playPause', 'kind == "playPause", record.count == 1',
                      'return .playPause', 'case .playPause:', 'record = ["kind": "playPause"]'):
            self.assertIn(token, prefs)
        self.assertEqual(prefs.count('CFNotificationCenterPostNotification('), 2)
        settings = (ROOT / 'Preferences/SettingsController.swift').read_text()
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
            text = (ROOT / path).read_bytes().decode('utf-8')
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256(invert_media_play_pause(path, text).encode()).hexdigest(), digest)

    def test_media_inverse_rejects_missing_duplicate_reordered_drift_and_crlf(self):
        import importlib.util
        self.assertIsNotNone(importlib.util.find_spec('media_play_pause_baseline'))
        from media_play_pause_baseline import FIXTURE, invert_media_play_pause
        for path, hunks in FIXTURE['hunks'].items():
            text = (ROOT / path).read_bytes().decode('utf-8')
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
        self.assertIn('six basic replacements', harness)
        verifier = (ROOT / 'ci/verify_package.py').read_text()
        self.assertIn('b"MRMediaRemoteSendCommand"', verifier)
        self.assertIn('Media provider leaked into Settings binary', verifier)

    def test_older_inverse_is_still_strict_unless_media_opt_in_is_explicit(self):
        from settings_layout_baseline import accepted_source
        path = 'Preferences/SettingsController.swift'
        with self.assertRaises(AssertionError):
            accepted_source(path)
        self.assertIn('TapLockPreferences.writeAction(.appSwitcher)', accepted_source(path, media_play_pause=True))

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


if __name__ == '__main__':
    unittest.main(verbosity=2)
