"""Bottom end-to-end SOURCE wiring; not a Swift/UIKit/device execution claim."""
import json
import re
from pathlib import Path
import unittest
from bottom_panel_inverse import source as baseline_source

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return baseline_source(path)


class BottomRuntimeIntegrationContracts(unittest.TestCase):
    def test_new_native_owner_and_session_are_real_production_members(self):
        for path in ('Sources/BottomGestureNative.swift', 'Sources/BottomGestureSession.swift'):
            self.assertTrue((ROOT / path).is_file(), 'Missing real bottom Hook/session owner: ' + path)
        text = source('Sources/BottomGestureNative.swift')
        self.assertIn('enum BottomGestureRuntime', text)
        self.assertIn('static func activate()', text)
        self.assertIn('MSHookMessageEx', text)
        for phase in ('Began', 'Updated', 'Ended', 'Canceled'):
            self.assertIn('grabberTongue' + phase + 'Pulling:withDistance:andVelocity:andGesture:', text)
        self.assertIn('BottomActionCoordinator.shared', text)
        makefile = source('Makefile')
        match = re.search(r'^TapLock_FILES = (.+)$', makefile, re.M)
        self.assertIsNotNone(match)
        assert match is not None
        paths = match[1].split()
        for path in ('Sources/BottomGestureNative.swift', 'Sources/BottomGestureSession.swift', 'Sources/BottomActions.swift'):
            self.assertIn(path, paths)
        self.assertEqual(len(paths), len(set(paths)))

    def test_accepted_startup_appends_exactly_one_new_activation(self):
        text = source('Sources/NativeHook.swift')
        self.assertIn('        HomeDoubleTap.shared.start()\n        BottomGestureRuntime.activate()\n', text)
        self.assertEqual(text.count('BottomGestureRuntime.activate()'), 1)

    def test_real_panel_flow_owner_uses_only_accepted_action_provider_routes(self):
        path = 'Sources/BottomActions.swift'
        self.assertTrue((ROOT / path).is_file(), 'Missing real panel/flow/provider consumer')
        text = source(path)
        for token in ('final class BottomActionCoordinator', 'static let shared', 'func trigger(',
                      'func cancelPendingFlow()', 'func cancelAll()', 'UIWindow', 'UIWindowScene'):
            self.assertIn(token, text)
        calls = ('LockAction.requestLock()', 'AppAction.open(identifier:', 'ControlCenterAction.open()',
                 'NotificationCenterAction.open()', 'ScreenshotAction.capture()', 'AppSwitcherAction.open()',
                 'MediaPlayPauseAction.toggle()', 'MediaPlayPauseAction.previousTrack()',
                 'MediaPlayPauseAction.nextTrack()', 'FlashlightAction.toggle()', 'SystemMuteAction.toggle()')
        for call in calls:
            self.assertIn(call, text)
        for forbidden in ('CFPreferencesSynchronize(', 'TapLockPreferences.readAction(', 'HomeDoubleTap.shared'):
            self.assertNotIn(forbidden, text)

    def test_bottom_apple_gates_are_registered_before_package_without_new_push_trigger(self):
        workflow = json.loads(source('.github/workflows/build.yml'))
        self.assertEqual(workflow['on'], {'push': {'branches': ['main'], 'paths-ignore': ['docs/**', 'README.md']},
                                         'workflow_dispatch': {}})
        steps = workflow['jobs']['roothide']['steps']
        bottom = next((s for s in steps if s.get('name') == 'Bottom gesture model and UIKit gates'), None)
        self.assertIsNotNone(bottom, 'New source must have explicit executable Apple gates before packaging')
        assert bottom is not None
        package = next(s for s in steps if s.get('name') == 'Compile and package RootHide')
        self.assertLess(steps.index(bottom), steps.index(package))
        self.assertIn('set -euo pipefail', bottom['run'])
        for runner, report in [('bottom-gesture-model', 'BOTTOM_GESTURE_MODEL'),
                               ('bottom-gesture-settings', 'BOTTOM_GESTURE_SETTINGS'),
                               ('bottom-gesture-native', 'BOTTOM_GESTURE_NATIVE'),
                               ('bottom-actions', 'BOTTOM_ACTIONS')]:
            self.assertIn('bash ci/' + runner + '-smoke.sh', bottom['run'])
            self.assertIn('tee "$RUNNER_TEMP/' + report + '_TESTS.txt"', bottom['run'])
            self.assertIn('cp "$RUNNER_TEMP/' + report + '_TESTS.txt" "$OUT_DIR/' + report + '_TESTS.txt"', package['run'])


if __name__ == '__main__':
    unittest.main()
