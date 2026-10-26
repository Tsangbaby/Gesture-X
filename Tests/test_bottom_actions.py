"""Source/runner contracts only. These do not compile or execute Swift/UIKit."""
import os
import platform
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OWNER = ROOT / 'Sources/BottomActions.swift'


def code():
    if not OWNER.is_file():
        raise AssertionError('Missing production bottom panel/flow consumer')
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda m: m[0] if m[0].startswith('"') else ' ', OWNER.read_text(), flags=re.S)


def body(text, anchor):
    start = text.index('{', text.index(anchor)) + 1
    depth = 1
    # Preserve string lengths so braces inside labels are not Swift structure.
    masked = re.sub(r'"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m[0]), text)
    for i in range(start, len(text)):
        depth += (masked[i] == '{') - (masked[i] == '}')
        if depth == 0:
            return text[start:i]
    raise AssertionError('Unterminated Swift body: ' + anchor)


class BottomActionSourceContracts(unittest.TestCase):
    def test_consumer_interface_and_no_preference_hot_path(self):
        text = code()
        for token in ('final class BottomActionCoordinator', 'static let shared',
                      'func trigger(_ selection: BottomGesturePreferences.Selection,',
                      'in scene: UIWindowScene, allowWhileLocked: Bool)',
                      'func cancelPendingFlow()', 'func cancelAll()'):
            self.assertIn(token, text)
        for forbidden in ('CFPreferences', 'readSnapshot(', 'readAction(', 'LSApplication',
                          'HomeDoubleTap.shared', 'dlopen(', 'unsafeBitCast('):
            self.assertNotIn(forbidden, text)

    def test_only_existing_provider_routes_and_no_invalid_fallback(self):
        text = code()
        for call in ('LockAction.requestLock()', 'AppAction.open(identifier:',
                     'ControlCenterAction.open()', 'NotificationCenterAction.open()',
                     'ScreenshotAction.capture()', 'AppSwitcherAction.open()',
                     'MediaPlayPauseAction.toggle()', 'MediaPlayPauseAction.previousTrack()',
                     'MediaPlayPauseAction.nextTrack()', 'FlashlightAction.toggle()',
                     'SystemMuteAction.toggle()'):
            self.assertEqual(text.count(call), 1, call)
        self.assertIn('TapLockPreferences.validBundleIdentifier(identifier)', text)
        self.assertRegex(text, r'case \.unavailable:\s*(?:return|break)')


    def test_lazy_panel_toggle_and_release_are_scoped(self):
        text = code()
        trigger = body(text, 'func trigger(')
        self.assertIn('selection.enabled', trigger)
        self.assertIn('selection.actions.allSatisfy', trigger)
        self.assertIn('cancelPendingFlow()', trigger)
        self.assertIn('if panelWindow != nil', trigger)
        self.assertIn('presentPanel(', trigger)
        self.assertNotIn('actions.count == 1', trigger)
        present = body(text, 'private func presentPanel(')
        self.assertIn('BottomActionPanelWindow(windowScene: scene)', present)
        self.assertIn('window.isHidden = false', present)
        self.assertNotIn('makeKey', present)
        release = body(text, 'private func releasePanel()')
        for token in ('window.isHidden = true', 'window.rootViewController = nil',
                      'controller?.invalidate()', 'panelWindow = nil'):
            self.assertIn(token, release)
        pending = body(text, 'func cancelPendingFlow()')
        self.assertIn('generation &+= 1', pending)
        self.assertNotIn('releasePanel', pending)
        self.assertNotIn('panelWindow', pending)

    def test_flow_callbacks_check_generation_scene_permission_before_invocation(self):
        text = code()
        flow = body(text, 'private func startFlow(')
        for token in ('actions.enumerated()', '0.3 * Double(ordinal)', 'ordinal == 0',
                      'generation == token', 'isEligible(', 'io.invoke(action)', '[weak self, weak scene]'):
            self.assertIn(token, flow)
        self.assertLess(flow.index('generation == token'), flow.index('io.invoke(action)'))
        delayed = body(flow, 'io.schedule(delay)')
        for token in ('Thread.isMainThread', 'self.generation == token', 'let scene = scene',
                      'self.isEligible(', 'self.cancelAll()', 'self.io.invoke(action)'):
            self.assertIn(token, delayed)
        self.assertLess(delayed.index('self.generation == token'), delayed.index('self.io.invoke(action)'))
        self.assertLess(delayed.index('self.isEligible('), delayed.index('self.io.invoke(action)'))
        eligible = body(text, 'private func isEligible(')
        for token in ('Thread.isMainThread', 'UIScreen.main', '.foregroundActive',
                      'UIAccessibility.isVoiceOverRunning', 'io.permission(scene, allowWhileLocked)',
                      'scene.interfaceOrientation == orientation'):
            self.assertIn(token, eligible)

    def test_panel_choices_require_exact_visible_control_and_one_shot_authority(self):
        text = code()
        action = body(text, 'func actionPressed(')
        for token in ('buttons.firstIndex(where:', '$0 === sender', 'sender.tag == index',
                      'isVisible(sender)', '.action(index)'):
            self.assertIn(token, action)
        choice = body(text, 'func consumeChoice()')
        self.assertIn('pendingChoice = nil', choice)
        delegate = body(text, 'func panelDidRequestDismissal(')
        for token in ('window.rootViewController === panel', 'panel.consumeChoice()',
                      'generation == token', 'releasePanel()', 'isEligible('):
            self.assertIn(token, delegate)
        self.assertIn('weak var delegate:', text)
        hit = body(text, 'override func hitTest(')
        self.assertIn('hasPresentedPanel', hit)
        self.assertIn('return nil', hit)


class BottomActionsRunnerContracts(unittest.TestCase):
    runner = ROOT / 'ci/bottom-actions-smoke.sh'

    def test_completion_guard_rejects_false_success(self):
        self.assertTrue(self.runner.is_file(), 'Missing executable UIKit runner')
        cases = [
            (0, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=23\n', True),
            (0, '', False),
            (0, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=0\n', False),
            (0, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=-1\n', False),
            (0, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=1.5\n', False),
            (0, 'OTHER_PASS: assertions=4\n', False),
            (0, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=2\n' * 2, False),
            (0, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=2\nBOTTOM_ACTIONS_UIKIT_FAIL: broken\n', False),
            (0, 'BOTTOM_ACTIONS_UIKIT_FAIL: broken\n', False),
            (1, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=2\n', False),
            (124, 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=2\n', False),
        ]
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as work:
            output = Path(work) / 'console.txt'
            for status, text, expected in cases:
                with self.subTest(status=status, text=text):
                    output.write_text(text)
                    result = subprocess.run(['bash', str(self.runner), '--verify-output', str(status), str(output)],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)

    def test_runner_declares_actual_consumer_and_every_provider(self):
        self.assertTrue(self.runner.is_file(), 'Missing executable UIKit runner')
        text = self.runner.read_text()
        for source in ('Shared/Preferences.swift', 'Shared/BottomGesturePreferences.swift',
                       'Sources/PrivateAPI.swift', 'Sources/BottomActions.swift',
                       'Sources/LockAction.swift', 'Sources/AppAction.swift',
                       'Sources/ControlCenterAction.swift', 'Sources/NotificationCenterAction.swift',
                       'Sources/ScreenshotAction.swift', 'Sources/AppSwitcherAction.swift',
                       'Sources/MediaPlayPauseAction.swift', 'Sources/FlashlightAction.swift',
                       'Sources/SystemMuteAction.swift', 'Tests/BottomActionsApp.swift'):
            self.assertEqual(text.count('"$ROOT/' + source + '"'), 1, source)
        for block in re.findall(r"<<'PY'\n(.*?)\nPY", text, re.S):
            compile(block, 'bottom-actions-embedded-python', 'exec')
        for command in ('simctl create', 'simctl bootstatus', 'simctl shutdown', 'simctl delete',
                        'xcrun swiftc', 'trap cleanup EXIT'):
            self.assertIn(command, text)
        for forbidden in ('git fetch', 'xcodebuild -download', 'curl ', 'brew '):
            self.assertNotIn(forbidden, text)

    def test_authored_uikit_harness_exercises_real_owner_not_a_python_model(self):
        text = (ROOT / 'Tests/BottomActionsApp.swift').read_text()
        for token in ('@main', 'BottomActionCoordinator(io:', 'testFlow(scene)', 'testPanel(scene)',
                      'testRejections(scene)', '.sendActions(for: .touchUpInside)',
                      'owner.panelDidRequestDismissal(panel)', 'clock.advance(to:',
                      'UIWindowSceneDelegate', 'BOTTOM_ACTIONS_UIKIT_PASS: assertions=',
                      'BOTTOM_ACTIONS_UIKIT_FAIL:', 'weak var released: UIWindow?'):
            self.assertIn(token, text)

    def test_actions_host_yields_for_actual_animation_completion_without_nested_runloops(self):
        text = (ROOT / 'Tests/BottomActionsApp.swift').read_text()
        self.assertIn('@main\n@MainActor\nfinal class BottomActionsApp:', text)
        self.assertRegex(text, r'private func run\(_ scene: UIWindowScene\)\s+async\s*\{')
        settle = body(text, 'private func settle(')
        self.assertIn('await Task.sleep', settle)
        self.assertIn('duration * 1_000_000_000', settle)
        self.assertNotIn('RunLoop.main.run(', text)
        self.assertIn('Task { @MainActor in await self.run(scene) }', text)
        run = body(text, 'private func run(')
        self.assertIn('await testMainQueueProgress()', run)
        self.assertIn('await testPanel(scene)', run)
        self.assertIn('await testRejections(scene)', run)
        self.assertLess(run.index('await testMainQueueProgress()'), run.index('testFlow(scene)'))
        panel = body(text, 'private func testPanel(')
        self.assertIn('await settle(0.03)', panel)
        self.assertIn('await settle()', panel)
        self.assertIn('events.map { $0.0 } == [.previousTrack] && owner.panelWindow == nil', panel)
        self.assertIn('timeout=180', self.runner.read_text())

    def test_actions_host_reports_phases_and_actual_selection_state(self):
        text = (ROOT / 'Tests/BottomActionsApp.swift').read_text()
        checkpoint = body(text, 'private func checkpoint(')
        for token in ('BOTTOM_ACTIONS_CHECKPOINT:', 'checks', 'events.map', 'owner?.panelWindow', 'fflush(stdout)'):
            self.assertIn(token, checkpoint)
        self.assertIn('checkpoint("selection after double tap")', body(text, 'private func testPanel('))
        self.assertIn('BOTTOM_ACTIONS_SELECTION_STATE:', text)
        self.assertIn('selected.isEnabled', body(text, 'private func testPanel('))
        self.assertIn('checkpoint("terminal")', body(text, 'private func finish('))

    @unittest.skipIf(platform.system() == 'Darwin', 'Apple execution is a separate gate')
    def test_unsupported_host_is_explicit_failure_not_a_skip_pass(self):
        self.assertTrue(self.runner.is_file(), 'Missing executable UIKit runner')
        result = subprocess.run(['bash', str(self.runner)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 69)
        self.assertIn('UNSUPPORTED_HOST', result.stderr)
        self.assertIn('no tests executed', result.stderr)
        self.assertNotIn('BOTTOM_ACTIONS_UIKIT_PASS:', result.stdout)


if __name__ == '__main__':
    unittest.main()
