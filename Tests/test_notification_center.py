"""Notification Center wiring; compiled execution and handset proof are separate."""
import re
import hashlib
import json
import unittest
from pathlib import Path
from test_source import source
from notification_center_baseline import FIXTURE, invert_notification_center
from control_center_baseline import invert_control_center
from screenshot_baseline import invert_screenshot
from settings_layout_baseline import accepted_source

ROOT = Path(__file__).resolve().parents[1]
ACCEPTED = '1b6615b46242abeb5b8ef0f0bf4afba14db18e2a'


class NotificationCenterContracts(unittest.TestCase):
    def test_exact_authorized_delta_restores_every_device_accepted_runtime_byte(self):
        self.assertEqual(FIXTURE['baseline'], ACCEPTED)
        for path, digest in FIXTURE['frozen'].items():
            with self.subTest(path=path):
                restored = invert_notification_center(path, accepted_source(path), screenshot=True, app_switcher=True)
                self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), digest)

    def test_old_inverse_stays_strict_without_explicit_new_candidate_opt_in(self):
        for path in FIXTURE['hunks']:
            text = accepted_source(path)
            with self.subTest(path=path), self.assertRaises(AssertionError):
                invert_control_center(path, text)

    def test_inverse_rejects_missing_duplicate_reordered_and_unrelated_drift(self):
        for path, hunks in FIXTURE['hunks'].items():
            text = invert_screenshot(path, accepted_source(path), app_switcher=True)
            for hunk in hunks:
                for mutation in (text.replace(hunk['after'], '', 1), text + hunk['after']):
                    with self.subTest(path=path), self.assertRaises(AssertionError):
                        invert_notification_center(path, mutation)
            if len(hunks) > 1:
                swapped = text.replace(hunks[0]['after'], '__SWAP__', 1).replace(
                    hunks[-1]['after'], hunks[0]['after'], 1).replace('__SWAP__', hunks[-1]['after'], 1)
                with self.assertRaises(AssertionError):
                    invert_notification_center(path, swapped)
            restored = invert_notification_center(path, text + '\n// unrelated drift\n')
            self.assertNotEqual(hashlib.sha256(restored.encode()).hexdigest(), FIXTURE['frozen'][path])

    def test_real_swift_and_uikit_gates_run_before_packaging_and_report_exact_red(self):
        steps = json.loads((ROOT / '.github/workflows/build.yml').read_text())['jobs']['roothide']['steps']
        runtime = next(s['run'] for s in steps if s.get('name') == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/notification-center-smoke.sh', runtime)
        package = next(s['run'] for s in steps if s.get('name') == 'Compile and package RootHide')
        self.assertIn('NOTIFICATION_CENTER_TESTS.txt', package)
        script = ROOT / 'ci/notification-center-smoke.sh'
        self.assertTrue(script.is_file(), 'Missing compiled production Swift gate')
        for token in ('BASELINE=' + ACCEPTED, 'NOTIFICATION_CENTER_BASELINE_EXPECTED_FAILURE',
                      'NOTIFICATION_CENTER_RUNTIME_PASS:', 'persisted Notification Center action is unavailable',
                      'restored == original', 'original.count(old) == count',
                      'Tests/NotificationCenterRuntimeTests.swift', 'Sources/NotificationCenterAction.swift'):
            self.assertIn(token, script.read_text())
        ui = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        for token in ('NOTIFICATION_CENTER_BASELINE=' + ACCEPTED, '-DNOTIFICATION_CENTER_ROWS',
                      '-DNOTIFICATION_CENTER_FEATURE', 'SETTINGS_CONSTRUCTION_FAIL: Notification Center action row missing'):
            self.assertIn(token, ui)

    def test_provider_belongs_only_to_tweak_and_is_verified_per_binary_slice(self):
        paths = re.search(r'^TapLock_FILES = (.+)$', (ROOT / 'Makefile').read_text(), re.M)[1].split()
        self.assertIn('Sources/NotificationCenterAction.swift', paths)
        self.assertNotIn('NotificationCenterAction', (ROOT / 'Preferences/Makefile').read_text())
        verifier = (ROOT / 'ci/verify_package.py').read_text()
        for selector in ('SBCoverSheetPresentationManager', 'setCoverSheetPresented:animated:withCompletion:',
                         'coverSheetCanTransitionToPresented:'):
            self.assertIn('b"' + selector + '"', verifier)
        self.assertIn('Notification Center provider leaked into Settings binary', verifier)

    def test_action_is_one_strict_persisted_value_preserving_old_defaults(self):
        text = source('Shared/Preferences.swift')
        for token in ('case notificationCenter',
                      'kind == "notificationCenter", record.count == 1',
                      'return .notificationCenter', 'case .notificationCenter:',
                      'record = ["kind": "notificationCenter"]',
                      'else { return .lock }', 'guard synchronize() else { return .unavailable }'):
            self.assertIn(token, text)
        self.assertEqual(text.count('CFNotificationCenterPostNotification('), 2)

    def test_native_provider_checks_exact_bool_block_abi_before_single_open_request(self):
        text = source('Sources/NotificationCenterAction.swift')
        for token in ('Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                      'NSClassFromString("SBCoverSheetPresentationManager")', '"sharedInstance"',
                      'manager.isKind(of: managerType)',
                      '"isPresented") == false', '"isVisible") == false',
                      '"isTransitioning") == false', '"coverSheetCanTransitionToPresented:"',
                      'returns: "B", arguments: ["B"]',
                      '"setCoverSheetPresented:animated:withCompletion:"',
                      'returns: "v", arguments: ["B", "B", "@?"]',
                      '@convention(block) () -> Void',
                      '@convention(c) (AnyObject, Selector, Bool, Bool, Completion?) -> Void'):
            self.assertIn(token, text)
        self.assertEqual(text.count('invoke(manager, selector, true, true, nil)'), 1)
        self.assertIn('canPresent(manager, admissionSelector, true)', text)
        for forbidden in ('requestLock(', 'AppAction', 'ControlCenterAction', 'toggle',
                          'openURL', 'asyncAfter', 'Timer(', 'perform(', 'setCoverSheetPresented:force'):
            self.assertNotIn(forbidden, text)

    def test_dispatch_only_adds_one_case_after_accepted_gesture_filters(self):
        body = source('Sources/HomeDoubleTap.swift').split('func recognized(', 1)[1].split('\n    }', 1)[0]
        for call in ('LockAction.requestLock()', 'AppAction.open(identifier: identifier)',
                     'ControlCenterAction.open()', 'NotificationCenterAction.open()'):
            self.assertEqual(body.count(call), 1)
        self.assertIn('case .notificationCenter:', body)
        self.assertLess(body.index('isBlankHit(in: host'), body.index('switch action'))
        self.assertNotIn('readAction()', body)

    def test_settings_fourth_row_only_saves_and_keeps_app_catalog_snapshot(self):
        text = invert_screenshot('Preferences/SettingsController.swift', source('Preferences/SettingsController.swift', settings_layout=True), app_switcher=True)
        for token in ('case .doubleTapAction: return 4', 'case (.doubleTapAction, 3):',
                      '"打开通知中心"', 'action == .notificationCenter ? .checkmark : .none',
                      'TapLockPreferences.writeAction(.notificationCenter)'):
            self.assertIn(token, text)
        self.assertEqual(text.count('InstalledApplications.choices()'), 1)
        self.assertNotIn('NotificationCenterAction', text)
        self.assertNotIn('setCoverSheetPresented:', text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
