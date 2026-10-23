"""Open-App source contracts; executed Swift/UIKit evidence is separate."""
import unittest
import hashlib
import json
from pathlib import Path
from test_source import source
from open_app_baseline import FIXTURE, invert_open_app

ROOT = Path(__file__).resolve().parents[1]
ACCEPTED = '7f35f9e51aa9d61d8bd052f0ab6b85127313d326'


class OpenAppContracts(unittest.TestCase):
    def test_uikit_harness_preserves_no_marker_failure_and_emits_ci_only_evidence(self):
        app = (ROOT / 'Tests/SettingsConstructionApp.swift').read_text()
        self.assertIn('SETTINGS_CHECKPOINT: didFinishLaunching', app)
        script = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        for token in ('SettingsConstruction crash report:', 'Library/Logs/DiagnosticReports',
                      'process == "SettingsConstruction"', 'missing verified completion marker'):
            self.assertIn(token, script)

    def test_runtime_fixture_names_cannot_collide_with_system_launchservices(self):
        app = (ROOT / 'Tests/ApplicationsRuntimeTests.swift').read_text()
        self.assertNotIn('@objc(LSApplicationProxy)', app)
        self.assertNotIn('@objc(LSApplicationWorkspace)', app)
        for name in ('TLTapLockApplicationProxyFixture', 'TLTapLockApplicationWorkspaceFixture'):
            self.assertIn('@objc(' + name + ')', app)
        script = (ROOT / 'ci/open-app-smoke.sh').read_text()
        for token in ('original.count(old) == count', 'restored == original',
                      '"LSApplicationProxy"', '"LSApplicationWorkspace"'):
            self.assertIn(token, script)

    def test_authorized_delta_restores_exact_device_accepted_bytes(self):
        self.assertEqual(FIXTURE['baseline'], ACCEPTED)
        for path, digest in FIXTURE['frozen'].items():
            with self.subTest(path=path):
                restored = invert_open_app(path, (ROOT / path).read_text())
                self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), digest)

    def test_inverse_rejects_missing_duplicate_reordered_and_unrelated_drift(self):
        for path, hunks in FIXTURE['hunks'].items():
            text = (ROOT / path).read_text()
            for hunk in hunks:
                for mutation in (text.replace(hunk['after'], '', 1), text + hunk['after']):
                    with self.assertRaises(AssertionError):
                        invert_open_app(path, mutation)
            if len(hunks) > 1:
                swapped = text.replace(hunks[0]['after'], '__SWAP__', 1).replace(
                    hunks[-1]['after'], hunks[0]['after'], 1).replace('__SWAP__', hunks[-1]['after'], 1)
                with self.assertRaises(AssertionError):
                    invert_open_app(path, swapped)
            restored = invert_open_app(path, text + '\n// unrelated drift\n')
            self.assertNotEqual(hashlib.sha256(restored.encode()).hexdigest(), FIXTURE['frozen'][path])

    def test_apple_runtime_and_behavioral_red_gate_precede_package_build(self):
        job = json.loads((ROOT / '.github/workflows/build.yml').read_text())['jobs']['roothide']
        runtime = next(s['run'] for s in job['steps'] if s.get('name') == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/open-app-smoke.sh', runtime)
        smoke = (ROOT / 'ci/open-app-smoke.sh').read_text()
        for path in ('Shared/Preferences.swift', 'Shared/Applications.swift', 'Sources/PrivateAPI.swift',
                     'Tests/ApplicationsRuntimeTests.swift', 'OPEN_APP_TESTS.txt'):
            self.assertIn(path, smoke)
        ui = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        self.assertIn('OPEN_APP_BASELINE=' + ACCEPTED, ui)
        self.assertLess(ui.index('run_case "$APP_OLD"'), ui.index('run_case "$ROOT"'))
        for token in ('-DOPEN_APP_ROWS', '-DOPEN_APP_FEATURE', 'Shared/Applications.swift', 'Sources/PrivateAPI.swift'):
            self.assertIn(token, ui)

    def test_settings_exposes_only_lock_and_installed_app_choice_without_launching(self):
        text = source('Preferences/SettingsController.swift')
        for token in ('applicationPicker', '"打开指定App"', '"选择App"',
                      'InstalledApplications.choices()', 'TapLockPreferences.readAction()',
                      'TapLockPreferences.writeAction(.lock)',
                      'TapLockPreferences.writeAction(.openApp(choice.identifier))',
                      'InstalledApplications.choice(identifier:', 'case .unavailable:',
                      'private var applications: [InstalledApplications.Choice] = []'):
            self.assertIn(token, text)
        self.assertEqual(text.count('InstalledApplications.choices()'), 1)
        for method in ('cellForRowAt', 'numberOfRowsInSection'):
            body = text.split(method, 1)[1].split('\n    }', 1)[0]
            self.assertNotIn('InstalledApplications.', body)
        self.assertNotIn('InstalledApplications.open(', text)
        self.assertNotIn('LockAction', text)

    def test_gesture_caches_selection_and_dispatches_one_action_after_existing_gates(self):
        text = source('Sources/HomeDoubleTap.swift')
        self.assertIn('private var action: TapLockPreferences.Action = .lock', text)
        reload = text.split('func reloadPreferences()', 1)[1].split('\n    }', 1)[0]
        self.assertLess(reload.index('cancelAll()'), reload.index('TapLockPreferences.readAction()'))
        self.assertLess(reload.index('TapLockPreferences.readAction()'), reload.index('refreshRecognizers()'))
        body = text.split('func recognized(', 1)[1].split('\n    }', 1)[0]
        self.assertIn('switch action', body)
        self.assertEqual(body.count('LockAction.requestLock()'), 1)
        self.assertEqual(body.count('InstalledApplications.open(identifier: identifier)'), 1)
        self.assertIn('case .unavailable:', body)
        self.assertNotIn('readAction()', body)
        self.assertLess(body.index('isEligible(in: host)'), body.index('switch action'))
        self.assertLess(body.index('isBlankHit(in: host'), body.index('switch action'))

    def test_catalog_uses_checked_launchservices_without_urls_or_fallback_actions(self):
        path = ROOT / 'Shared/Applications.swift'
        self.assertTrue(path.is_file(), 'Missing installed-App catalog/launch implementation')
        text = source('Shared/Applications.swift')
        for token in ('"LSApplicationWorkspace"', '"defaultWorkspace"', '"allApplications"',
                      '"LSApplicationProxy"', '"applicationProxyForIdentifier:"',
                      '"openApplicationWithBundleID:"', '"isInstalled"',
                      '"isLaunchProhibited"', '"appTags"', '"hidden"',
                      'returns: "@", arguments: ["@"]',
                      'returns: "B", arguments: ["@"]',
                      '@convention(c) (AnyObject, Selector, NSString) -> Bool',
                      'choice(identifier: identifier) != nil', 'Thread.isMainThread'):
            self.assertIn(token, text)
        for forbidden in ('URL(', 'openURL', 'LockAction', 'asyncAfter', 'Timer(', 'perform('):
            self.assertNotIn(forbidden, text)
        self.assertEqual(text.count('"allApplications"'), 1)
        self.assertEqual(text.count('invoke(workspace, selector, identifier as NSString)'), 1)

    def test_action_is_one_atomic_preference_with_upgrade_lock_and_invalid_rejection(self):
        text = source('Shared/Preferences.swift')
        for token in ('enum Action: Equatable', 'case lock', 'case openApp(String)',
                      'case unavailable', 'static let actionKey = "DoubleTapAction"',
                      'static func readAction()', 'static func writeAction(',
                      'static func validBundleIdentifier(', 'CFDictionaryGetTypeID()',
                      '"bundleIdentifier"', '"openApp"'):
            self.assertIn(token, text)
        self.assertEqual(text.count('CFNotificationCenterPostNotification('), 2)
        self.assertIn('CFPreferencesSetValue(actionKey as CFString, previous,', text)
        self.assertIn('return .lock', text)
        self.assertIn('return .unavailable', text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
