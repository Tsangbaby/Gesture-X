"""App Switcher source wiring only; executed Swift/UIKit/device proof is separate."""
import re
import unittest
from pathlib import Path
from test_source import source
from bottom_swipe_baseline import accepted_layout_source as accepted_source
from release_contract import EXPECTED_RELEASE_VERSION

ROOT = Path(__file__).resolve().parents[1]


class AppSwitcherContracts(unittest.TestCase):
    def test_sixth_exclusive_action_is_saved_and_dispatched_only_after_gesture_admission(self):
        prefs = source('Shared/Preferences.swift')
        for token in ('case appSwitcher', 'kind == "appSwitcher", record.count == 1',
                      'return .appSwitcher', 'case .appSwitcher:', 'record = ["kind": "appSwitcher"]'):
            self.assertIn(token, prefs)
        self.assertEqual(prefs.count('CFNotificationCenterPostNotification('), 2)
        body = source('Sources/HomeDoubleTap.swift').split('func recognized(', 1)[1].split('\n    }', 1)[0]
        for call in ('LockAction.requestLock()', 'AppAction.open(identifier: identifier)',
                     'ControlCenterAction.open()', 'NotificationCenterAction.open()',
                     'ScreenshotAction.capture()', 'AppSwitcherAction.open()'):
            self.assertEqual(body.count(call), 1)
        self.assertLess(body.index('isBlankHit(in: host'), body.index('switch action'))
        settings = source('Preferences/SettingsController.swift', settings_layout=True)
        for token in ('case .doubleTapAction: return 6', 'case (.doubleTapAction, 5):',
                      '"打开多任务"', 'action == .appSwitcher ? .checkmark : .none',
                      'TapLockPreferences.writeAction(.appSwitcher)'):
            self.assertIn(token, settings)
        self.assertNotIn('AppSwitcherAction', settings)
        self.assertNotIn('activateMainSwitcher', settings)
        self.assertEqual(settings.count('InstalledApplications.choices()'), 1)


    def test_native_open_uses_actual_receiver_and_exact_bool_int64_bool_abi_without_toggle(self):
        text = source('Sources/AppSwitcherAction.swift')
        for token in ('Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                      'NSClassFromString("SBMainSwitcherViewController")', '"sharedInstanceIfExists"',
                      'controller.isKind(of: controllerType)', '"isAnySwitcherVisible") == false',
                      '"isMainSwitcherVisible") == false', 'object_getClass(controller)',
                      '"activateMainSwitcherNoninteractivelyWithSource:animated:"',
                      'PrivateAPI.checkedMethod', 'returns: "B", arguments: ["q", "B"]',
                      '@convention(c) (AnyObject, Selector, Int64, Bool) -> Bool'):
            self.assertIn(token, text)
        self.assertEqual(text.count('return invoke(controller, selector, 0, true)'), 1)
        for forbidden in ('toggle', 'dismiss', '_simulateHomeButtonPress', 'SBUIController',
                          'SBMainSwitcherControllerCoordinator', 'asyncAfter', 'DispatchQueue',
                          'Timer(', 'perform(', 'IOHID', 'UIView.animate', 'requestLock(',
                          'takeScreenshot', 'for ', 'while '):
            self.assertNotIn(forbidden, text)
        files = re.search(r'^TapLock_FILES = (.+)$', (ROOT / 'Makefile').read_text(), re.M)[1].split()
        self.assertIn('Sources/AppSwitcherAction.swift', files)
        self.assertNotIn('AppSwitcherAction', (ROOT / 'Preferences/Makefile').read_text())


    def test_candidate_version_matches_active_release_and_bundle_versions_match(self):
        import plistlib
        fields = dict(line.split(': ', 1) for line in (ROOT / 'control').read_text().splitlines() if ': ' in line)
        self.assertEqual(fields['Version'], EXPECTED_RELEASE_VERSION)
        info = plistlib.loads((ROOT / 'Preferences/Resources/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleVersion'], fields['Version'])
        self.assertEqual(info['CFBundleShortVersionString'], fields['Version'])
        self.assertEqual(fields['Package'], 'com.tsangbaby.taplock')


    def test_exact_delta_restores_all_device_accepted_017_bytes(self):
        import hashlib
        from app_switcher_baseline import FIXTURE, invert_app_switcher
        self.assertEqual(FIXTURE['baseline'], 'fc79961bd6a1003aab36f43d0ab010a9bb6b1859')
        for path, digest in FIXTURE['frozen'].items():
            with self.subTest(path=path):
                restored = invert_app_switcher(path, accepted_source(path, media_play_pause=True, media_tracks=True, flashlight=True))
                self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), digest)

    def test_new_inverse_rejects_missing_duplicate_reordered_hunks_and_retains_unrelated_drift(self):
        import hashlib
        from app_switcher_baseline import FIXTURE, invert_app_switcher
        for path, hunks in FIXTURE['hunks'].items():
            text = accepted_source(path, media_play_pause=True, media_tracks=True, flashlight=True)
            for hunk in hunks:
                for mutation in (text.replace(hunk['after'], '', 1), text + hunk['after']):
                    with self.subTest(path=path), self.assertRaises(AssertionError):
                        invert_app_switcher(path, mutation)
            if len(hunks) > 1:
                swapped = text.replace(hunks[0]['after'], '__SWAP__', 1).replace(
                    hunks[-1]['after'], hunks[0]['after'], 1).replace('__SWAP__', hunks[-1]['after'], 1)
                with self.assertRaises(AssertionError):
                    invert_app_switcher(path, swapped)
            restored = invert_app_switcher(path, text + '\n// unrelated drift\n')
            self.assertNotEqual(hashlib.sha256(restored.encode()).hexdigest(), FIXTURE['frozen'][path])

    def test_historical_screenshot_inverse_requires_explicit_app_switcher_opt_in(self):
        from app_switcher_baseline import FIXTURE
        from screenshot_baseline import invert_screenshot
        for path in FIXTURE['hunks']:
            text = accepted_source(path, media_play_pause=True, media_tracks=True, flashlight=True)
            with self.subTest(path=path), self.assertRaises(AssertionError):
                invert_screenshot(path, text)

    def test_executed_swift_uikit_and_package_gates_are_wired_before_upload(self):
        import json
        steps = json.loads((ROOT / '.github/workflows/build.yml').read_text())['jobs']['roothide']['steps']
        runtime = next(s['run'] for s in steps if s.get('name') == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/app-switcher-smoke.sh', runtime)
        package = next(s['run'] for s in steps if s.get('name') == 'Compile and package RootHide')
        self.assertIn('APP_SWITCHER_TESTS.txt', package)
        runner = (ROOT / 'ci/app-switcher-smoke.sh').read_text()
        for token in ('BASELINE=fc79961bd6a1003aab36f43d0ab010a9bb6b1859',
                      'APP_SWITCHER_BASELINE_EXPECTED_FAILURE', 'APP_SWITCHER_RUNTIME_PASS:',
                      'persisted App Switcher action is unavailable', 'restored == original',
                      'original.count(old) == count', 'Tests/AppSwitcherRuntimeTests.swift',
                      'Sources/AppSwitcherAction.swift'):
            self.assertIn(token, runner)
        ui = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        for token in ('APP_SWITCHER_BASELINE=fc79961bd6a1003aab36f43d0ab010a9bb6b1859',
                      '-DAPP_SWITCHER_ROWS', '-DAPP_SWITCHER_FEATURE',
                      'SETTINGS_CONSTRUCTION_FAIL: App Switcher action row missing'):
            self.assertIn(token, ui)
        app = (ROOT / 'Tests/SettingsConstructionApp.swift').read_text()
        for token in ('APP_SWITCHER_UIKIT_PASS:', 'let expectedActionRows = 6',
                      'TapLockPreferences.readAction() == .appSwitcher'):
            self.assertIn(token, app)
        self.assertNotIn('for row in 0..<5', app)
        self.assertNotIn('for row in [0, 1]', app)
        verifier = (ROOT / 'ci/verify_package.py').read_text()
        self.assertIn('b"activateMainSwitcherNoninteractivelyWithSource:animated:"', verifier)
        self.assertIn('App Switcher provider leaked into Settings binary', verifier)


    def test_actual_runtime_completion_guard_rejects_nonzero_missing_wrong_or_extra_markers(self):
        import tempfile
        from types import SimpleNamespace
        from unittest import mock
        runner = (ROOT / 'ci/app-switcher-smoke.sh').read_text()
        block = runner.rsplit("<<'PY'\n", 1)[1].split('\nPY', 1)[0]
        positive = 'APP_SWITCHER_RUNTIME_PASS: 1 assertions against production Swift; OS receivers are fixtures, NOT handset App Switcher proof'
        for code, output, accepted in ((0, positive + '\n', True), (1, positive, False),
                                       (0, '', False), (0, positive + '\nextra\n', False),
                                       (0, positive.replace(': 1 assertions', ': 0 assertions'), False),
                                       (0, 'APP_SWITCHER_RUNTIME_FAIL: wrong state\n', False)):
            with self.subTest(code=code, output=output), tempfile.TemporaryDirectory() as directory:
                argv = ['guard', 'fixture-executable', str(Path(directory) / 'report')]
                with mock.patch('sys.argv', argv), mock.patch('builtins.print'), mock.patch(
                        'subprocess.run', return_value=SimpleNamespace(returncode=code, stdout=output)):
                    failed = False
                    try:
                        exec(compile(block, '<actual App Switcher completion guard>', 'exec'), {})
                    except SystemExit:
                        failed = True
                self.assertEqual(not failed, accepted)


if __name__ == '__main__':
    unittest.main(verbosity=2)
