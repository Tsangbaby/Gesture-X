"""SOURCE/runtime-runner contracts; NOT compiled Swift or device evidence."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def code(path):
    text = (ROOT / path).read_text()
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda m: m[0] if m[0].startswith('"') else '', text, flags=re.S)


class BottomNativeSourceTests(unittest.TestCase):
    def test_reference_rectangle_negative_fixture_isolates_fixed_bounds_and_checks_recovery(self):
        text = code('Tests/BottomGestureNativeApp.swift')
        fixture = text.split('private func testSafeObjectSlots()', 1)[1].split('private func testCoordinatorBridge()', 1)[0]
        for token in ('let fixedSpace = UIScreen.main.fixedCoordinateSpace',
                      'let referenceBefore = BottomGestureSample.referenceRectangle(of: UIScreen.main)',
                      'object_getClass(fixedSpace as AnyObject)', 'NSSelectorFromString("bounds")',
                      'let frozenReference = referenceBefore!',
                      'let referenceSnapshot: @convention(block) (AnyObject) -> CGRect = { _ in frozenReference }',
                      'let referenceSnapshotIMP = imp_implementationWithBlock(referenceSnapshot as Any)',
                      'method_setImplementation(referenceMethod, referenceSnapshotIMP)',
                      'method_setImplementation(fixedBoundsMethod, unsafeBitCast(incompatible, to: IMP.self))',
                      'let referenceDuring = BottomGestureSample.referenceRectangle(of: UIScreen.main)',
                      'let fixedDuring = fixedSpace.bounds',
                      'method_setImplementation(fixedBoundsMethod, previousFixedBounds)',
                      'method_setImplementation(referenceMethod, previousReference)',
                      'imp_removeBlock(referenceSnapshotIMP)',
                      'referenceDuring == referenceBefore && fixedDuring != referenceDuring',
                      'require(incompatibleSample == nil', 'let restoredSample = BottomGestureSample.captureValidated(',
                      'restoredSample?.point == expected && restoredSample?.referenceRect == referenceBefore'):
            self.assertIn(token, fixture)
        self.assertNotIn('method_setImplementation(referenceMethod, unsafeBitCast(incompatible,', fixture)
        self.assertLess(fixture.index('let referenceBefore ='), fixture.index('let previousFixedBounds ='))
        self.assertLess(fixture.index('let fixedDuring ='), fixture.index('let incompatibleSample ='))
        self.assertLess(fixture.index('method_setImplementation(fixedBoundsMethod, previousFixedBounds)'),
                        fixture.index('require(incompatibleSample == nil'))

    def test_full_abi_is_gated_before_any_install(self):
        path = ROOT / 'Sources/BottomGestureNative.swift'
        self.assertTrue(path.is_file(), 'missing real four-callback native owner')
        text = code('Sources/BottomGestureNative.swift')
        for phase in ('Began', 'Updated', 'Ended', 'Canceled'):
            self.assertIn('grabberTongue' + phase + 'Pulling:withDistance:andVelocity:andGesture:', text)
        for token in ('@convention(c) (AnyObject, Selector, AnyObject?, Double, Double, AnyObject?) -> Void',
                      'returns: "v", arguments: ["@", "d", "d", "@"]',
                      'method_getImplementation', 'MSHookMessageEx', 'guard !started',
                      'BottomGestureRuntime', 'BottomActionCoordinator.shared'):
            self.assertIn(token, text)
        self.assertLess(text.index('guard methods.count =='), text.index('installer(type, Self.selectors[index]'))

    def test_session_has_frozen_identity_core_order_and_lifecycle_ownership(self):
        path = ROOT / 'Sources/BottomGestureSession.swift'
        self.assertTrue(path.is_file(), 'missing main-thread gesture session owner')
        text = code('Sources/BottomGestureSession.swift')
        for token in ('final class BottomGestureSession', 'let snapshot:', 'let origin:',
                      'let receiver: AnyObject', 'let gesture: AnyObject',
                      'receiver === receiver', 'gesture === gesture',
                      'BottomGestureGeometry.bounds(snapshot:', 'BottomGestureGeometry.side(origin:',
                      'BottomGestureGeometry.classify(origin:', 'referenceSize: saved.referenceSize',
                      'cancelPendingFlow()', 'func invalidate()', 'cancelAll()',
                      'case .ended:', 'case .canceled:', 'defer { reset(ifSame: saved) }'):
            self.assertIn(token, text)
        ended = text.split('case .ended:', 1)[1].split('case .canceled:', 1)[0]
        self.assertLess(ended.index('trigger('), ended.index('forward()'))
        canceled = text.split('case .canceled:', 1)[1]
        self.assertLess(canceled.index('forward()'), canceled.index('reset(ifSame: saved)'))
        self.assertNotIn('readSnapshot(', text)
        self.assertNotIn('valueForKey', text)

    def test_live_coordinates_are_schema_gated_and_do_not_use_callback_doubles(self):
        path = ROOT / 'Sources/BottomGestureSession.swift'
        self.assertTrue(path.is_file(), 'missing live coordinate acquisition')
        text = code('Sources/BottomGestureSession.swift')
        for token in ('deckGrabberTongue', 'let container = recognizer.view', '_edgePullGestureRecognizer',
                      'recognizer === gesture', 'location(in: container)', '_referenceBounds',
                      'ivar_getTypeEncoding', 'object_getIvar', 'PrivateAPI.checkedMethod',
                      'window.windowScene', 'scene.interfaceOrientation.rawValue'):
            self.assertIn(token, text)
        self.assertNotIn('distance:', text)
        self.assertNotIn('velocity:', text)

    def test_optional_edge_only_relaxes_original_true_under_narrow_policy(self):
        native = code('Sources/BottomGestureNative.swift')
        session = code('Sources/BottomGestureSession.swift')
        self.assertIn('returns: "B", arguments: ["d"]', native)
        self.assertIn('"_shouldProtectEdgeLocation:"', native)
        self.assertNotIn('"_shouldProtectEdgeLocation:edge:"', native)
        for token in ('let protected = previous(receiver, selector, location)',
                      'guard Thread.isMainThread, protected', 'owner.session.shouldRelaxEdge('):
            self.assertIn(token, native)
        for token in ('func shouldRelaxEdge(', 'snapshot.boolean(.ignoreEdgeProtect)',
                      'unlocked()', 'enabledSide(side, snapshot: snapshot)'):
            self.assertIn(token, session)
        self.assertNotIn('"_handleDismissGesture:"', native)

    def test_real_uikit_harness_calls_production_imps_and_covers_ownership(self):
        path = ROOT / 'Tests/BottomGestureNativeApp.swift'
        self.assertTrue(path.is_file(), 'missing real UIKit/ObjC forwarding harness')
        text = code('Tests/BottomGestureNativeApp.swift')
        for token in ('@main', 'BottomGestureHooks(session:', 'method_getImplementation',
                      'BottomGestureHooks.PullCall.self', 'BottomGestureSample.capture(',
                      'testForwarding', 'testOverlap', 'testInvalidation', 'testLandscape',
                      'testCapabilityRejection', 'testSafeObjectSlots', 'testEdge',
                      'DispatchQueue.global()', 'BOTTOM_GESTURE_NATIVE_PASS: assertions=',
                      'BOTTOM_GESTURE_NATIVE_FAIL:'):
            self.assertIn(token, text)

    def test_runner_compiles_production_graph_and_reuses_objc_backend_fixture(self):
        path = ROOT / 'ci/bottom-gesture-native-smoke.sh'
        self.assertTrue(path.is_file(), 'missing real Apple execution runner')
        text = path.read_text()
        for name in ('Shared/Preferences.swift', 'Shared/BottomGesturePreferences.swift',
                     'Shared/BottomGestureGeometry.swift', 'Sources/PrivateAPI.swift',
                     'Sources/BottomGestureNative.swift', 'Sources/BottomGestureSession.swift',
                     'Sources/BottomActions.swift', 'Sources/LockAction.swift',
                     'Sources/AppAction.swift', 'Sources/ControlCenterAction.swift',
                     'Sources/NotificationCenterAction.swift', 'Sources/ScreenshotAction.swift',
                     'Sources/AppSwitcherAction.swift', 'Sources/MediaPlayPauseAction.swift',
                     'Sources/FlashlightAction.swift', 'Sources/SystemMuteAction.swift',
                     'Tests/BottomGestureNativeApp.swift', 'Tests/NativeHookFixture.m'):
            self.assertIn(name, text)
        for block in re.findall(r"<<'PY'\n(.*?)\nPY", text, re.S):
            compile(block, 'native-runner-embedded-python', 'exec')
        self.assertNotIn('git fetch', text)

    def test_actual_runner_marker_guard_truth_table(self):
        runner = ROOT / 'ci/bottom-gesture-native-smoke.sh'
        self.assertTrue(runner.is_file(), 'missing actual marker guard')
        cases = [
            (0, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=1\n', True),
            (0, 'launch transport success\n', False),
            (0, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=0\n', False),
            (0, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=-1\n', False),
            (0, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=abc\n', False),
            (0, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=01\n', False),
            (0, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=1\n' * 2, False),
            (0, 'BOTTOM_GESTURE_NATIVE_FAIL: x\nBOTTOM_GESTURE_NATIVE_PASS: assertions=1\n', False),
            (0, 'WRONG_BOTTOM_GESTURE_NATIVE_PASS: assertions=1\n', False),
            (0, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=1 trailing\n', False),
            (1, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=1\n', False),
            (124, 'BOTTOM_GESTURE_NATIVE_PASS: assertions=1\n', False),
        ]
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as work:
            log = Path(work) / 'console.txt'
            for status, output, accepted in cases:
                with self.subTest(status=status, output=output):
                    log.write_text(output)
                    result = subprocess.run(['bash', str(runner), '--verify-output', str(status), str(log)],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)

    @unittest.skipIf(sys.platform == 'darwin', 'non-Apple refusal applies only to unsupported host')
    def test_runner_refuses_unsupported_host_instead_of_claiming_pass(self):
        runner = ROOT / 'ci/bottom-gesture-native-smoke.sh'
        self.assertTrue(runner.is_file(), 'missing real platform refusal')
        result = subprocess.run(['bash', str(runner)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 69)
        self.assertIn('UNSUPPORTED_HOST:', result.stderr)
        self.assertIn('no tests executed.', result.stderr)
        self.assertNotIn('BOTTOM_GESTURE_NATIVE_PASS:', result.stdout)

    def test_cancel_marks_matching_owner_terminal_before_native_reentrancy(self):
        text = code('Sources/BottomGestureSession.swift').split('case .canceled:', 1)[1]
        self.assertIn('saved.ending = true', text)
        self.assertLess(text.index('saved.ending = true'), text.index('forward()'))
        self.assertLess(text.index('forward()'), text.index('reset(ifSame: saved)'))

    def test_coordinate_addendum_freezes_validated_fixed_space_and_exact_classes(self):
        text = code('Sources/BottomGestureSession.swift')
        for token in ('let referenceSpace: UICoordinateSpace', 'let screen: UIScreen',
                      'referenceSpace.bounds == referenceRect',
                      'container.convert(localPoint, to: referenceSpace)',
                      'sample.referenceSpace === referenceSpace', 'sample.screen === screen',
                      'activeInterfaceOrientation', 'returns: "q"', '"SBGrabberTongue"',
                      '"SBFluidSwitcherGestureManager"', '"edgePullGestureRecognizer"',
                      'let container = recognizer.view'):
            self.assertIn(token, text)
        self.assertNotIn('objectSlot(deck, "_tongueContainer")', text)

    def test_scene_lifecycle_is_filtered_to_owned_scene(self):
        session = code('Sources/BottomGestureSession.swift')
        native = code('Sources/BottomGestureNative.swift')
        self.assertIn('func invalidate(in scene: UIWindowScene)', session)
        self.assertIn('active?.scene === scene', session)
        self.assertIn('owner.invalidate(in: scene)', native)

    def test_harness_records_actual_c_selector_and_predecessor_identity(self):
        text = code('Tests/BottomGestureNativeApp.swift')
        for token in ('exactPredecessor: BottomGestureHooks.PullCall',
                      'selector: selector, tongue: tongue, distance: distance',
                      'unsafeBitCast(Self.exactPredecessor, to: IMP.self)',
                      'expectedPredecessors[selector]', 'previous.pointee!'):
            self.assertIn(token, text)

    def test_edge_acquisition_validates_private_owner_before_reading_tongue_fields(self):
        text = code('Sources/BottomGestureSession.swift')
        self.assertIn('static func captureEdge(', text)
        edge = text.split('static func captureEdge(', 1)[1].split('static func captureValidated(', 1)[0]
        self.assertLess(edge.index('deck.isKind(of: capabilities.tongue)'), edge.index('edgeRecognizer(in: deck)'))
        policy = text.split('func shouldRelaxEdge(', 1)[1].split('func receive(', 1)[0]
        self.assertIn('let current = edgeSample?(receiver)', policy)
        self.assertNotIn('PrivateAPI.object(', policy)


if __name__ == '__main__':
    unittest.main()
