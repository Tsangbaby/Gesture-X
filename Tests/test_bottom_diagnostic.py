"""Diagnostic-only SOURCE gates; Apple execution is reported separately."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BottomDiagnosticContracts(unittest.TestCase):
    def test_collector_is_default_off_bounded_and_uses_no_follow_fd(self):
        text = (ROOT / 'Sources/BottomGestureNative.swift').read_text()
        self.assertIn('enum BottomGestureDiagnostic {', text, 'Missing bounded diagnostic collector')
        collector = text.split('enum BottomGestureDiagnostic {', 1)[1]
        for token in ('#if BOTTOM_GESTURE_DIAGNOSTIC', 'maximumBytes = 32768',
                      'maximumFlushes = 256', 'pending', 'O_NOFOLLOW', 'O_NONBLOCK',
                      'O_EXCL', 'fstat(', 'st_nlink == 1', 'fchmod(', 'flock(',
                      'LOCK_NB', 'ftruncate(', 'EINTR', 'defer { close(',
                      'BottomDiagnosticBuild.sourceSHA', 'TapLockBottomDiag1'):
            self.assertIn(token, collector)
        for forbidden in ('NSLog(', 'URLSession', 'FileHandle', 'Data(contentsOf:', 'print(',
                          'location(in:', 'userInfo', 'String(describing:', 'asyncAfter(deadline: .now() + 0)'):
            self.assertNotIn(forbidden, collector)
        self.assertIn('return condition', collector)
        self.assertIn('return candidate', collector)
    def test_required_markers_have_real_call_sites_and_preserve_gate_order(self):
        native = (ROOT / 'Sources/BottomGestureNative.swift').read_text().split('// BOTTOM_DIAGNOSTIC_COLLECTOR_BEGIN')[0]
        session = (ROOT / 'Sources/BottomGestureSession.swift').read_text()
        for token in ('BottomGestureDiagnostic.mark(.activated)',
                      'BottomGestureDiagnostic.mark(.hookAttempt)',
                      'BottomGestureDiagnostic.callback(phase.rawValue)',
                      'BottomGestureDiagnostic.mark(.hookInstalled)',
                      'BottomGestureDiagnostic.preferences('):
            self.assertIn(token, native, 'Missing real diagnostic boundary: ' + token)
        for token in ('BottomGestureDiagnostic.admission(true)',
                      'defer { BottomGestureDiagnostic.admission(false) }',
                      'BottomGestureDiagnostic.value(container.window, .sampleContainerDetached)',
                      'BottomGestureDiagnostic.value(window.windowScene, .sampleSceneUnavailable)',
                      'BottomGestureDiagnostic.check(scene.activationState == .foregroundActive, .sampleSceneInactive)',
                      'BottomGestureDiagnostic.check(snapshot.available, .beganPreferencesUnavailable)',
                      'BottomGestureDiagnostic.check(unlocked(), .beganLockedOrUnknown)',
                      'BottomGestureDiagnostic.mark(.beganAdmitted)',
                      'BottomGestureDiagnostic.mark(.actionSubmitted)'):
            self.assertIn(token, session, 'Missing real diagnostic boundary: ' + token)
        # Each formal getter is still evaluated only once at the same gate.
        capture = session.split('static func captureValidated(', 1)[1].split('/// No guessed', 1)[0]
        for getter in ('container.window', 'window.windowScene', 'scene.activationState',
                       'recognizer.location(in: container)', 'interfaceOrientation(of: capabilities.application)'):
            self.assertEqual(capture.count(getter), 1, getter)
        self.assertLess(capture.index('container.window'), capture.index('window.windowScene'))
        self.assertLess(capture.index('window.windowScene'), capture.index('interfaceOrientation(of:'))
        began = session.split('case .began:', 1)[1].split('case .updated:', 1)[0]
        ordered = ['active == nil', 'let gesture =', 'let tongue =', 'snapshot.available', 'unlocked()',
                   'sample(receiver, tongue, gesture)', 'BottomGestureGeometry.bounds(',
                   'BottomGestureGeometry.side(', 'enabledSide(side, snapshot: snapshot)', 'active = Active(']
        offsets = [began.index(token) for token in ordered]
        self.assertEqual(offsets, sorted(offsets))
    def test_diagnostic_lane_is_cloud_only_opt_in_and_does_not_edit_formal_metadata(self):
        import json
        workflow_path = ROOT / '.github/workflows/bottom-diagnostic.yml'
        self.assertTrue(workflow_path.is_file(), 'Missing isolated diagnostic cloud lane')
        workflow = json.loads(workflow_path.read_text())
        self.assertEqual(workflow['on'], {'push': {'branches': ['diag/bottom-ingress-08bdc78']}})
        job = workflow['jobs']['roothide-bottom-diagnostic']
        self.assertEqual(job['runs-on'], 'macos-15')
        self.assertEqual(job['env']['THEOS_PACKAGE_SCHEME'], 'roothide')
        commands = '\n'.join(s.get('run', '') for s in job['steps'])
        self.assertNotIn('simctl', commands)
        self.assertNotIn('continue-on-error', json.dumps(workflow))
        self.assertIn('bottom-diagnostic-runtime-smoke.sh', commands)
        self.assertIn('bottom-diagnostic-build.sh', commands)
        builder = (ROOT / 'ci/bottom-diagnostic-build.sh').read_text()
        for token in ('BOTTOM_GESTURE_DIAGNOSTIC', 'make all', 'make package', 'verify_package.py',
                      'ci/BottomDiagnosticBuild.swift', 'SOURCE_COMMIT.txt', 'THEOS_PACKAGE_SCHEME=roothide'):
            self.assertIn(token, builder)
        self.assertNotIn('BOTTOM_GESTURE_DIAGNOSTIC', (ROOT / 'Makefile').read_text())
        self.assertIn('Version: 0.1.13\n', (ROOT / 'control').read_text())
        preparer = (ROOT / 'ci/bottom_diagnostic.py').read_text()
        for token in ('0.1.13+bottomdiag1', 'BottomDiagnosticBuild', 'sourceSHA',
                      '/var/mobile/Library/Logs', 'diagnostic_only', 'git', 'archive'):
            self.assertIn(token, preparer)
    def test_inverse_binds_the_observation_to_exact_failed_runtime_and_rejects_drift(self):
        import hashlib
        import runpy
        module = runpy.run_path(str(ROOT / 'ci/bottom_diagnostic.py'))
        restore = module['restore']
        frozen = {
            'Sources/BottomGestureNative.swift': 'd0673687b9c42ec7de020529a2c4ae810c3ce6adb192ff88987df1c454e06e3f',
            'Sources/BottomGestureSession.swift': '2bb82aad5909640cac7c2aaf751288d53f1b9a433e311460aacd90c1cf98efaa',
        }
        for path, expected in frozen.items():
            current = (ROOT / path).read_text()
            self.assertEqual(hashlib.sha256(restore(path, current).encode()).hexdigest(), expected)
            with self.assertRaisesRegex(AssertionError, 'non-diagnostic runtime drift'):
                restore(path, current + '\n// unrelated mutation\n')
        path = 'Sources/BottomGestureSession.swift'
        current = (ROOT / path).read_text()
        for target in ('scene.activationState == .foregroundActive', 'snapshot.available', 'unlocked()',
                       'active == nil', 'recognizer === gesture', 'referenceSpace.bounds == referenceRect'):
            anchor = 'BottomGestureDiagnostic.check(' + target + ','
            self.assertEqual(current.count(anchor), 1)
            with self.subTest(target=target), self.assertRaisesRegex(AssertionError, 'diagnostic inverse anchor'):
                restore(path, current.replace(anchor, 'BottomGestureDiagnostic.check(true,', 1))

    def test_writer_formats_outside_counter_lock_and_validates_before_reset(self):
        text = (ROOT / 'Sources/BottomGestureNative.swift').read_text()
        flush = text.split('private static func flush()', 1)[1].split('private static func persist(', 1)[0]
        self.assertLess(flush.index('lock.unlock()'), flush.index('Array(report(snapshot).utf8)'))
        writer = text.split('private static func persist(', 1)[1].split('#if BOTTOM_DIAGNOSTIC_TESTS', 1)[0]
        for predicate in ('fileStat.st_uid == geteuid()', 'fileStat.st_nlink == 1',
                          'flock(fd, LOCK_EX | LOCK_NB)', 'fchmod(fd, mode_t(0o600))'):
            self.assertLess(writer.index(predicate), writer.index('ftruncate(fd, 0)'))
        self.assertNotIn('O_TRUNC', writer)
        self.assertNotIn('rename', writer)
        self.assertIn('guard reset == 0 else { return false }', writer)
        self.assertLess(writer.index('guard reset == 0'), writer.index('write(fd,'))

    def test_extractor_reads_the_actual_collector_and_validates_source_sha(self):
        import runpy
        import tempfile
        module = runpy.run_path(str(ROOT / 'ci/bottom_diagnostic.py'))
        identity = module['identity']
        self.assertIn('static let sourceSHA = "' + 'a' * 40 + '"', identity('a' * 40, 'fixed'))
        for invalid in ('a' * 39, 'a' * 41, 'g' * 40, 'a' * 39 + '\n'):
            with self.assertRaises(AssertionError):
                identity(invalid, 'fixed')
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'extracted'
            module['extract'](output, 'a' * 40)
            self.assertIn('enum BottomGestureDiagnostic {', (output / 'Collector.swift').read_text())
            self.assertNotIn('import UIKit', (output / 'Collector.swift').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
