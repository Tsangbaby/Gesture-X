"""Recognizer-view SOURCE regression; UIKit execution is a separate Apple gate."""
import hashlib
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATH = 'Sources/BottomGestureSession.swift'
BASE_SHA256 = '2bb82aad5909640cac7c2aaf751288d53f1b9a433e311460aacd90c1cf98efaa'
BEFORE = '''              let container = objectIvar(deck, "_tongueContainer") as? UIView,
              let recognizer = edgeRecognizer(in: deck),
              recognizer === gesture, recognizer.view != nil,
'''
AFTER = '''              let recognizer = edgeRecognizer(in: deck), recognizer === gesture,
              let container = recognizer.view,
'''
POINT_BEFORE = '        let point = container.convert(recognizer.location(in: container), to: referenceSpace)\n'
POINT_AFTER = '''        let localPoint = recognizer.location(in: container)
        guard localPoint.x.isFinite, localPoint.y.isFinite else { return nil }
        let point = container.convert(localPoint, to: referenceSpace)
'''


def restore(text):
    assert text.count(AFTER) == 1, 'sample-view inverse anchor'
    assert text.count(POINT_AFTER) == 1, 'raw-point inverse anchor'
    original = text.replace(AFTER, BEFORE, 1).replace(POINT_AFTER, POINT_BEFORE, 1)
    assert hashlib.sha256(original.encode()).hexdigest() == BASE_SHA256, 'unrelated sample-view runtime drift'
    return original


class BottomSampleFixContracts(unittest.TestCase):
    def test_uses_exact_recognizer_view_without_display_ivar_dependency(self):
        text = (ROOT / PATH).read_bytes().decode()
        capture = text.split('static func captureValidated(', 1)[1].split('/// No guessed', 1)[0]
        self.assertIn(AFTER, capture, 'Sampling must use the validated recognizer attachment, not optional display UI')
        self.assertNotIn('_tongueContainer', capture)
        for token in ('Thread.isMainThread', 'UIApplication.shared.applicationState == .active',
                      'deck === tongue', 'deck.isKind(of: capabilities.tongue)',
                      'container.window', 'window.screen === UIScreen.main',
                      'window.windowScene', 'scene.activationState == .foregroundActive',
                      'scene.screen === window.screen', 'orientationRaw == scene.interfaceOrientation.rawValue',
                      'referenceSpace.bounds == referenceRect',
                      'container.convert(localPoint, to: referenceSpace)',
                      'point.x.isFinite', 'point.y.isFinite'):
            self.assertIn(token, capture)
        ordered = ['deck === tongue', 'recognizer === gesture', 'let container = recognizer.view',
                   'container.window', 'window.windowScene', 'recognizer.location(in: container)']
        positions = [capture.index(token) for token in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(capture.count('recognizer.view'), 1)
        self.assertEqual(capture.count('recognizer.location(in: container)'), 1)

    def test_raw_nonfinite_input_rejects_before_uikit_conversion(self):
        capture = (ROOT / PATH).read_text().split('static func captureValidated(', 1)[1].split('/// No guessed', 1)[0]
        for token in ('let localPoint = recognizer.location(in: container)',
                      'guard localPoint.x.isFinite, localPoint.y.isFinite else { return nil }',
                      'let point = container.convert(localPoint, to: referenceSpace)',
                      'guard point.x.isFinite, point.y.isFinite else { return nil }'):
            self.assertIn(token, capture)
        self.assertLess(capture.index('guard localPoint.x.isFinite'), capture.index('container.convert(localPoint,'))

    def test_only_authorized_sample_chain_changes(self):
        text = (ROOT / PATH).read_bytes().decode()
        original = restore(text)
        self.assertIn(BEFORE, original)
        for target in ('Thread.isMainThread', 'recognizer === gesture',
                       'scene.activationState == .foregroundActive',
                       'sample.container === container', 'referenceSpace.bounds == referenceRect'):
            with self.subTest(target=target), self.assertRaises(AssertionError):
                restore(text.replace(target, 'true', 1))
        for mutant in (text + '\n// unrelated\n', text.replace('\n', '\r\n'),
                       text.replace(AFTER, AFTER * 2, 1)):
            with self.assertRaises(AssertionError):
                restore(mutant)
    def test_cloud_lane_is_exact_branch_roothide_and_keeps_historical_gates(self):
        import json
        workflow = ROOT / '.github/workflows/bottom-sample-fix.yml'
        self.assertTrue(workflow.is_file(), 'Missing isolated functional cloud lane')
        data = json.loads(workflow.read_text())
        self.assertEqual(data['on'], {'push': {'branches': ['fix/bottom-sample-view-08bdc78']}})
        self.assertEqual(data['permissions'], {'contents': 'read'})
        self.assertEqual(set(data['jobs']), {'roothide-sample-fix'})
        job = data['jobs']['roothide-sample-fix']
        old = json.loads((ROOT / '.github/workflows/package-recovery.yml').read_text())['jobs']['roothide-package']
        self.assertEqual(job['runs-on'], 'macos-15')
        self.assertEqual(job['env'], old['env'])
        commands = '\n'.join(step.get('run', '') for step in job['steps'])
        self.assertIn('ci/bottom-sample-fix-smoke.sh', commands)
        self.assertIn('ci/bottom-sample-fix-build.sh', commands)
        self.assertNotIn('continue-on-error', json.dumps(data))
        source = next(s['run'] for s in old['steps'] if s['name'] == 'Source and real Swift runtime tests')
        self.assertIn(source, commands)
        upload = [s for s in job['steps'] if 'actions/upload-artifact@' in s.get('uses', '')]
        self.assertEqual(len(upload), 1)
        self.assertEqual(upload[0]['if'], 'always()')
        self.assertEqual(upload[0]['with']['name'], 'taplock-roothide-bottomfix1-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}')
        builder = (ROOT / 'ci/bottom-sample-fix-build.sh').read_text()
        for token in ('make all', 'make package', 'verify_package.py', 'SOURCE_COMMIT.txt'):
            self.assertIn(token, builder)
        self.assertNotIn('BOTTOM_GESTURE_DIAGNOSTIC', builder)

    def test_red_completion_requires_the_specific_behavioral_failure(self):
        import runpy
        helper = ROOT / 'ci/bottom_sample_fix.py'
        self.assertTrue(helper.is_file(), 'Missing exact-source staging and RED guard')
        verify = runpy.run_path(str(helper))['validate_red']
        expected = 'BOTTOM_GESTURE_NATIVE_FAIL: missing display container must not block attached recognizer sampling\n'
        verify(1, expected)
        for status, text in [(0, expected), (124, expected), (1, ''), (1, 'compiler error'),
                             (1, expected * 2), (1, expected + 'BOTTOM_GESTURE_NATIVE_PASS: assertions=1\n'),
                             (1, 'BOTTOM_GESTURE_NATIVE_FAIL: other\n')]:
            with self.subTest(status=status, text=text), self.assertRaises(AssertionError):
                verify(status, text)

    def test_owned_completion_binds_real_marker_to_exact_build_and_launch(self):
        import runpy
        helper = runpy.run_path(str(ROOT / 'ci/bottom_sample_fix.py'))
        self.assertIn('validate_owned_result', helper, 'Missing launch-owned durable completion verifier')
        verify = helper['validate_owned_result']
        sha, token = 'a' * 40, 'b' * 32
        marker = 'BOTTOM_GESTURE_NATIVE_PASS: assertions=1'
        result = dict(schema=1, source_sha=sha, run_token=token, marker=marker)
        self.assertEqual(verify(0, '', result, sha, token), marker)
        self.assertEqual(verify(0, marker + '\n', result, sha, token), marker)
        failure = dict(result, marker='BOTTOM_GESTURE_NATIVE_FAIL: exact assertion')
        self.assertEqual(verify(1, '', failure, sha, token), failure['marker'])
        for status, text, record in [(124, '', result), (1, '', result), (0, '', None),
                                     (0, '', dict(result, source_sha='c' * 40)),
                                     (0, '', dict(result, run_token='d' * 32)),
                                     (0, '', dict(result, marker='BOTTOM_GESTURE_NATIVE_PASS: assertions=0')),
                                     (0, '', dict(result, schema=2)),
                                     (0, marker + '\n' + marker + '\n', result),
                                     (0, str(failure['marker']) + '\n', result)]:
            with self.subTest(status=status, record=record), self.assertRaises(AssertionError):
                verify(status, text, record, sha, token)
        runner = (ROOT / 'ci/bottom-gesture-native-smoke.sh').read_text()
        app = (ROOT / 'Tests/BottomGestureNativeApp.swift').read_text()
        for key in ('BottomNativeSourceCommit', 'BottomNativeRunToken', 'BottomGestureNative.result.json'):
            self.assertIn(key, runner)
            self.assertIn(key, app)
        self.assertIn('validate_owned_result', runner)
        self.assertIn('didFinishLaunchingWithOptions', app)
        self.assertIn('publishResult(marker)', app)

    def test_candidate_has_no_diagnostic_runtime(self):
        native = (ROOT / 'Sources/BottomGestureNative.swift').read_text()
        session = (ROOT / PATH).read_text()
        for text in (native, session):
            self.assertNotIn('BottomGestureDiagnostic', text)
            self.assertNotIn('TapLockBottomDiag1', text)
        fixture = (ROOT / 'Tests/BottomGestureNativeApp.swift').read_text()
        for token in ('private func testRecognizerViewSampling()', 'receiver.deck.container = nil',
                      'receiver.deck.container = UIView()', 'recognizer.lastLocationView === attached',
                      'changed recognizer view invalidates owned session',
                      'unchanged recognizer attachment recovers single action submission',
                      'testSafeObjectSlots(); testRecognizerViewSampling(); testCoordinatorBridge()'):
            self.assertIn(token, fixture)


if __name__ == '__main__':
    unittest.main(verbosity=2)
