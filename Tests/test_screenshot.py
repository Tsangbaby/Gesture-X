"""Screenshot source contracts; compiled Swift and handset proof are separate."""
import plistlib
import hashlib
import json
import re
import unittest
from pathlib import Path
from test_source import source
from screenshot_baseline import FIXTURE, invert_screenshot
from notification_center_baseline import invert_notification_center
from app_switcher_baseline import invert_app_switcher
from settings_layout_baseline import accepted_source
from release_contract import EXPECTED_RELEASE_VERSION

ROOT = Path(__file__).resolve().parents[1]
ACCEPTED = '078b98fb67582422a577b70ae3335ecc0d1e2ab9'


class ScreenshotContracts(unittest.TestCase):
    def test_exact_screenshot_delta_restores_every_device_accepted_runtime_byte(self):
        self.assertEqual(FIXTURE['baseline'], ACCEPTED)
        for path, digest in FIXTURE['frozen'].items():
            with self.subTest(path=path):
                restored = invert_screenshot(path, accepted_source(path, media_play_pause=True, media_tracks=True, flashlight=True), app_switcher=True)
                self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), digest)

    def test_historical_inverse_requires_explicit_screenshot_opt_in(self):
        for path in ('Shared/Preferences.swift', 'Sources/HomeDoubleTap.swift',
                     'Preferences/SettingsController.swift', 'Makefile'):
            text = accepted_source(path, media_play_pause=True, media_tracks=True, flashlight=True)
            with self.subTest(path=path), self.assertRaises(AssertionError):
                invert_notification_center(path, text)

    def test_inverse_rejects_missing_duplicate_reordered_hunks_and_does_not_hide_drift(self):
        for path, hunks in FIXTURE['hunks'].items():
            text = invert_app_switcher(path, accepted_source(path, media_play_pause=True, media_tracks=True, flashlight=True))
            for hunk in hunks:
                for mutation in (text.replace(hunk['after'], '', 1), text + hunk['after']):
                    with self.subTest(path=path), self.assertRaises(AssertionError):
                        invert_screenshot(path, mutation)
            if len(hunks) > 1:
                swapped = text.replace(hunks[0]['after'], '__SWAP__', 1).replace(
                    hunks[-1]['after'], hunks[0]['after'], 1).replace('__SWAP__', hunks[-1]['after'], 1)
                with self.assertRaises(AssertionError):
                    invert_screenshot(path, swapped)
            restored = invert_screenshot(path, text + '\n// unrelated drift\n')
            self.assertNotEqual(hashlib.sha256(restored.encode()).hexdigest(), FIXTURE['frozen'][path])

    def test_real_swift_and_uikit_gates_precede_packaging_and_preserve_exact_baseline_red(self):
        steps = json.loads((ROOT / '.github/workflows/build.yml').read_text())['jobs']['roothide']['steps']
        runtime = next(s['run'] for s in steps if s.get('name') == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/screenshot-smoke.sh', runtime)
        package = next(s['run'] for s in steps if s.get('name') == 'Compile and package RootHide')
        self.assertIn('SCREENSHOT_TESTS.txt', package)
        script = (ROOT / 'ci/screenshot-smoke.sh').read_text()
        for token in ('BASELINE=' + ACCEPTED, 'SCREENSHOT_BASELINE_EXPECTED_FAILURE',
                      'SCREENSHOT_RUNTIME_PASS:', 'persisted screenshot action is unavailable',
                      'restored == original', 'original.count(old) == count',
                      'Tests/ScreenshotRuntimeTests.swift', 'Sources/ScreenshotAction.swift'):
            self.assertIn(token, script)
        ui = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        for token in ('SCREENSHOT_BASELINE=' + ACCEPTED, '-DSCREENSHOT_ROWS', '-DSCREENSHOT_FEATURE',
                      'SETTINGS_CONSTRUCTION_FAIL: Screenshot action row missing'):
            self.assertIn(token, ui)
        app = (ROOT / 'Tests/SettingsConstructionApp.swift').read_text()
        for token in ('SCREENSHOT_UIKIT_PASS:', 'Screenshot action row missing', '0..<expectedActionRows',
                      'TapLockPreferences.readAction() == .screenshot'):
            self.assertIn(token, app)

    def test_package_verifier_keeps_native_screenshot_provider_out_of_settings(self):
        text = (ROOT / 'ci/verify_package.py').read_text()
        self.assertIn('b"takeScreenshot"', text)
        self.assertIn('Screenshot provider leaked into Settings binary', text)

    def test_one_new_exclusive_action_uses_only_the_checked_native_screenshot_entry(self):
        prefs = source('Shared/Preferences.swift')
        for token in ('case screenshot', 'kind == "screenshot", record.count == 1',
                      'return .screenshot', 'case .screenshot:', 'record = ["kind": "screenshot"]'):
            self.assertIn(token, prefs)
        self.assertEqual(prefs.count('CFNotificationCenterPostNotification('), 2)
        self.assertIn('guard synchronize() else { return .unavailable }', prefs)
        text = source('Sources/ScreenshotAction.swift')
        for token in ('Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                      'NSClassFromString("SpringBoard")', '"sharedApplication"',
                      'application.isKind(of: applicationType)', 'object_getClass(application)',
                      '"takeScreenshot"', 'PrivateAPI.checkedMethod', 'returns: "v"',
                      '@convention(c) (AnyObject, Selector) -> Void'):
            self.assertIn(token, text)
        self.assertEqual(text.count('invoke(application, selector)'), 1)
        for forbidden in ('requestLock(', 'openURL', 'asyncAfter', 'Timer(', 'perform(',
                          'UIImage', 'UIGraphics', 'CGWindow', 'Photo', 'URLSession',
                          'saveScreenshot', 'screenshotManager', 'IOHID', 'UIView.animate'):
            self.assertNotIn(forbidden, text)
        body = source('Sources/HomeDoubleTap.swift').split('func recognized(', 1)[1].split('\n    }', 1)[0]
        for call in ('LockAction.requestLock()', 'AppAction.open(identifier: identifier)',
                     'ControlCenterAction.open()', 'NotificationCenterAction.open()', 'ScreenshotAction.capture()'):
            self.assertEqual(body.count(call), 1)
        self.assertIn('case .screenshot:', body)
        self.assertLess(body.index('isBlankHit(in: host'), body.index('switch action'))
        settings = invert_app_switcher('Preferences/SettingsController.swift', source('Preferences/SettingsController.swift', settings_layout=True))
        for token in ('case .doubleTapAction: return 5', 'case (.doubleTapAction, 4):',
                      '"系统截图"', 'action == .screenshot ? .checkmark : .none',
                      'TapLockPreferences.writeAction(.screenshot)'):
            self.assertIn(token, settings)
        self.assertEqual(settings.count('InstalledApplications.choices()'), 1)
        self.assertNotIn('ScreenshotAction', settings)
        self.assertNotIn('takeScreenshot', settings)
        files = re.search(r'^TapLock_FILES = (.+)$', (ROOT / 'Makefile').read_text(), re.M)[1].split()
        self.assertIn('Sources/ScreenshotAction.swift', files)
        self.assertNotIn('ScreenshotAction', (ROOT / 'Preferences/Makefile').read_text())

    def test_authorized_candidate_version_matches_every_active_surface(self):
        fields = dict(line.split(': ', 1) for line in (ROOT / 'control').read_text().splitlines() if ': ' in line)
        self.assertEqual(fields['Version'], EXPECTED_RELEASE_VERSION)
        info = plistlib.loads((ROOT / 'Preferences/Resources/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleVersion'], fields['Version'])
        self.assertEqual(info['CFBundleShortVersionString'], fields['Version'])
        self.assertEqual(fields['Package'], 'com.tsangbaby.taplock')


if __name__ == '__main__':
    unittest.main(verbosity=2)
