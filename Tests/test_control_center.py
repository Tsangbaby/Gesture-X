"""Control Center wiring contracts; actual Swift/UIKit tests are separate."""
import json
import hashlib
import re
import unittest
from pathlib import Path
from test_source import source
from control_center_baseline import FIXTURE, invert_control_center
from open_app_baseline import invert_open_app
from notification_center_baseline import invert_notification_center

ROOT = Path(__file__).resolve().parents[1]
ACCEPTED = 'b8d6994be7defcc37ceac3bb158c5526c952ac3a'


class ControlCenterContracts(unittest.TestCase):
    def test_historical_inverse_does_not_silently_accept_the_new_candidate(self):
        for path in FIXTURE['hunks']:
            with self.subTest(path=path), self.assertRaises(AssertionError):
                invert_open_app(path, (ROOT / path).read_text())

    def test_only_the_exact_authorized_delta_changes_device_accepted_runtime_bytes(self):
        self.assertEqual(FIXTURE['baseline'], ACCEPTED)
        for path, digest in FIXTURE['frozen'].items():
            with self.subTest(path=path):
                restored = invert_control_center(path, (ROOT / path).read_text(), notification_center=True, screenshot=True, app_switcher=True)
                self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), digest)

    def test_candidate_inverse_rejects_missing_duplicate_reordered_and_unrelated_drift(self):
        for path, hunks in FIXTURE['hunks'].items():
            text = invert_notification_center(path, (ROOT / path).read_text(), screenshot=True, app_switcher=True)
            for hunk in hunks:
                for mutation in (text.replace(hunk['after'], '', 1), text + hunk['after']):
                    with self.assertRaises(AssertionError):
                        invert_control_center(path, mutation)
            if len(hunks) > 1:
                swapped = text.replace(hunks[0]['after'], '__SWAP__', 1).replace(
                    hunks[-1]['after'], hunks[0]['after'], 1).replace('__SWAP__', hunks[-1]['after'], 1)
                with self.assertRaises(AssertionError):
                    invert_control_center(path, swapped)
            restored = invert_control_center(path, text + '\n// unrelated drift\n')
            self.assertNotEqual(hashlib.sha256(restored.encode()).hexdigest(), FIXTURE['frozen'][path])

    def test_control_center_is_a_strict_atomic_action_not_a_new_gesture(self):
        text = source('Shared/Preferences.swift')
        for token in ('case controlCenter', 'kind == "controlCenter", record.count == 1',
                      'return .controlCenter', 'case .controlCenter:',
                      'record = ["kind": "controlCenter"]'):
            self.assertIn(token, text)
        self.assertEqual(text.count('CFNotificationCenterPostNotification('), 2)
        self.assertIn('guard synchronize() else { return .unavailable }', text)

    def test_native_action_checks_receiver_state_and_exact_bool_abi_before_one_call(self):
        path = ROOT / 'Sources/ControlCenterAction.swift'
        self.assertTrue(path.is_file(), 'Missing native Control Center action')
        text = source('Sources/ControlCenterAction.swift')
        for token in ('Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                      'NSClassFromString("SBControlCenterController")',
                      '"sharedInstance"', 'controller.isKind(of: controllerType)',
                      '"isPresentedOrDismissing") == false', '"canBePresented") == true',
                      '"presentAnimated:"', 'returns: "v", arguments: ["B"]',
                      '@convention(c) (AnyObject, Selector, Bool) -> Void'):
            self.assertIn(token, text)
        self.assertEqual(text.count('invoke(controller, selector, true)'), 1)
        for forbidden in ('LSApplication', 'openURL', 'asyncAfter', 'Timer(',
                          'perform(', 'toggleControlCenter', 'requestLock()', 'AppAction.open'):
            self.assertNotIn(forbidden, text)

    def test_existing_gesture_dispatch_adds_only_one_exclusive_control_center_case(self):
        body = source('Sources/HomeDoubleTap.swift').split('func recognized(', 1)[1].split('\n    }', 1)[0]
        self.assertIn('case .controlCenter:', body)
        self.assertEqual(body.count('ControlCenterAction.open()'), 1)
        self.assertEqual(body.count('LockAction.requestLock()'), 1)
        self.assertEqual(body.count('AppAction.open(identifier: identifier)'), 1)
        self.assertLess(body.index('isBlankHit(in: host'), body.index('switch action'))
        self.assertNotIn('readAction()', body)

    def test_settings_adds_a_third_row_and_saves_without_invoking_the_action(self):
        # Inspect this historical stage after inverting only the new action.
        text = invert_notification_center('Preferences/SettingsController.swift',
                                          source('Preferences/SettingsController.swift'), screenshot=True, app_switcher=True)
        for token in ('case .doubleTapAction: return 3', 'case (.doubleTapAction, 2):',
                      '"打开控制中心"', 'action == .controlCenter ? .checkmark : .none',
                      'TapLockPreferences.writeAction(.controlCenter)'):
            self.assertIn(token, text)
        self.assertEqual(text.count('InstalledApplications.choices()'), 1)
        self.assertNotIn('ControlCenterAction', text)
        self.assertNotIn('presentAnimated:', text)

    def test_native_swift_and_old_baseline_behavior_gates_precede_packaging(self):
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_text())
        steps = workflow['jobs']['roothide']['steps']
        runtime = next(s['run'] for s in steps if s.get('name') == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/control-center-smoke.sh', runtime)
        self.assertIn('CONTROL_CENTER_TESTS.txt', next(s['run'] for s in steps if s.get('name') == 'Compile and package RootHide'))
        script = ROOT / 'ci/control-center-smoke.sh'
        self.assertTrue(script.is_file(), 'Missing executed Swift feature gate')
        text = script.read_text()
        for token in ('BASELINE=' + ACCEPTED, 'CONTROL_CENTER_BASELINE_EXPECTED_FAILURE',
                      'CONTROL_CENTER_RUNTIME_PASS:', 'persisted Control Center action is unavailable',
                      'restored == original', 'original.count(old) == count',
                      'Tests/ControlCenterRuntimeTests.swift', 'Sources/ControlCenterAction.swift'):
            self.assertIn(token, text)
        ui = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        for token in ('CONTROL_CENTER_BASELINE=' + ACCEPTED, '-DCONTROL_CENTER_ROWS',
                      '-DCONTROL_CENTER_FEATURE', 'SETTINGS_CONSTRUCTION_FAIL: Control Center action row missing'):
            self.assertIn(token, ui)

    def test_action_is_in_tweak_graph_but_not_settings_and_is_required_per_slice(self):
        makefile = (ROOT / 'Makefile').read_text()
        paths = re.search(r'^TapLock_FILES = (.+)$', makefile, re.M)[1].split()
        self.assertIn('Sources/ControlCenterAction.swift', paths)
        self.assertNotIn('Sources/ControlCenterAction.swift', (ROOT / 'Preferences/Makefile').read_text())
        verifier = (ROOT / 'ci/verify_package.py').read_text()
        for selector in ('SBControlCenterController', 'presentAnimated:', 'isPresentedOrDismissing', 'canBePresented'):
            self.assertIn('b"' + selector + '"', verifier)
        self.assertIn('require_selector_per_slice', verifier)


if __name__ == '__main__':
    unittest.main(verbosity=2)
