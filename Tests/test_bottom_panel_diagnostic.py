"""Observation-only contracts; execution/handset evidence is reported separately."""
import hashlib
import json
from pathlib import Path
import re
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = 'b606238d93bb71e7caf1c219767aefaad63a0bb7'
FROZEN = {
    'Sources/BottomGestureNative.swift': 'd0673687b9c42ec7de020529a2c4ae810c3ce6adb192ff88987df1c454e06e3f',
    'Sources/BottomGestureSession.swift': '793b955b60e71c32927a9e5215c311f78f302e8d9299e275e655f552478ff543',
    'Sources/BottomActions.swift': 'bd8f20d4fa05c5b3531cc18ff84c3b4806ba70012b7e725ccde6759aa6906aaf',
}


class BottomPanelDiagnosticContracts(unittest.TestCase):
    def test_closed_flow_hook_to_real_sampler_to_chooser_is_exercised(self):
        text = (ROOT / 'Tests/BottomGestureNativeApp.swift').read_text()
        self.assertIn('private func testClosedFlowChooserBridge() async', text,
                      'Missing flow-disabled complete chooser regression')
        section = text.split('private func testClosedFlowChooserBridge() async', 1)[1].split('private func run(', 1)[0]
        for token in ('configured(flow: false)', 'useActualSampler = true', 'invoke(.began)',
                      'invoke(.updated)', 'invoke(.ended)', 'coordinator?.panelWindow',
                      'BottomActionPanelController', 'bottom.action.0', 'providerActions.isEmpty',
                      'await Task.yield()', 'Task.sleep', 'panel survives main-queue turn',
                      'disabled higher tier must not produce a chooser',
                      'lost sampling must not produce a chooser', 'later valid gesture recovers chooser',
                      'await testClosedFlowChooserBridge()'):
            self.assertIn(token, text if token.startswith('await test') else section)
        self.assertIn('if useActualSampler', text)
        self.assertIn('BottomGestureSample.captureValidated(target, tongue, gesture,', text)

    def test_exact_observation_inverse_and_mutation_rejection(self):
        path = ROOT / 'Tests/bottom_panel_inverse.py'
        self.assertTrue(path.is_file(), 'Missing isolated diagnostic inverse')
        module = runpy.run_path(str(path))
        restore = module['restore']
        manifest = json.loads((ROOT / 'Tests/bottom_panel_inverse.json').read_text())
        self.assertEqual(manifest['observation_base'], BASE)
        self.assertEqual(set(manifest['files']), set(FROZEN))
        for relative, expected in FROZEN.items():
            text = (ROOT / relative).read_bytes().decode()
            original = restore(relative, text)
            self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), expected)
            for mutant in (text + '\n// unrelated\n', text.replace('\n', '\r\n')):
                with self.subTest(relative=relative), self.assertRaises(AssertionError):
                    restore(relative, mutant)
            for edit in manifest['files'][relative]['hunks']:
                with self.assertRaises(AssertionError):
                    restore(relative, text.replace(edit['after'], edit['after'] * 2, 1))

    def test_collector_is_bounded_and_has_no_user_payload_vocabulary(self):
        path = ROOT / 'ci/BottomPanelDiagnostic.swift'
        self.assertTrue(path.is_file(), 'Missing actual bounded collector')
        text = path.read_text()
        for token in ('#if BOTTOM_PANEL_DIAGNOSTIC', 'maximumBytes = 32768',
                      'maximumFlushes = 256', 'maximumTrace = 96', 'O_NOFOLLOW', 'O_NONBLOCK',
                      'fstat(', 'flock(', 'ftruncate(', 'F_SETPROTECTIONCLASS', 'TapLockBottomDiag2',
                      'revision=bottomdiag2', 'mode=diagnostic_only', 'first_failure_current_gesture',
                      'gesture_number=', 'trace.', 'observation_base=' + BASE):
            self.assertIn(token, text)
        for forbidden in ('bundleIdentifier', 'URLSession', 'UIPasteboard', 'NSLog', 'Date()',
                          'description)', 'location(in:', 'readSnapshot(', 'makeKey', 'print('):
            self.assertNotIn(forbidden, text)

    def test_decisive_stages_have_real_call_sites_not_only_enum_cases(self):
        sources = {p: (ROOT / p).read_text() for p in FROZEN}
        obligations = {
            'Sources/BottomGestureNative.swift': ['activated', 'hookInstalled', 'callbackOwnerMissing', 'preferenceReload', 'systemOrientationChanged'],
            'Sources/BottomGestureSession.swift': ['beganAdmitted', 'updateSampleRejected', 'endedWithoutOwner', 'endedClassificationRejected', 'actionSubmitted', 'contextContainerChanged', 'sampleSceneUnavailable'],
            'Sources/BottomActions.swift': ['coordinatorEntered', 'coordinatorSelectionRejected', 'coordinatorSceneInactive', 'coordinatorVoiceOver', 'panelCreated', 'panelNotHidden', 'panelDeferredReleased', 'panelReleased', 'panelGeometryChanged'],
        }
        for path, events in obligations.items():
            for event in events:
                self.assertIn('BottomPanelDiagnostic.mark(.' + event + ')', sources[path], (path, event))
        for path in FROZEN:
            self.assertIn('#if BOTTOM_PANEL_DIAGNOSTIC', sources[path])
        session = sources['Sources/BottomGestureSession.swift']
        self.assertIn('BottomPanelDiagnostic.admission(true)', session)
        self.assertIn('defer { BottomPanelDiagnostic.admission(false) }', session)
        actions = sources['Sources/BottomActions.swift']
        self.assertIn('[weak self, weak window]', actions)
        self.assertIn('let permitted = io.permission(scene, allowWhileLocked)', actions)
        self.assertNotIn('window.makeKey', actions)

    def test_cloud_and_staging_preserve_formal_and_functional_refs(self):
        path = ROOT / '.github/workflows/bottom-panel-diagnostic.yml'
        self.assertTrue(path.is_file(), 'Missing explicit RootHide-only diagnostic push lane')
        workflow = json.loads(path.read_text())
        self.assertEqual(workflow['on'], {'push': {'branches': ['diag/bottom-panel-b606238']}})
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        jobs = workflow['jobs']
        self.assertEqual(len(jobs), 1)
        job = next(iter(jobs.values()))
        old = json.loads((ROOT / '.github/workflows/bottom-sample-fix.yml').read_text())['jobs']['roothide-sample-fix']
        self.assertEqual(job['env'], old['env'])
        self.assertEqual(job['runs-on'], 'macos-15')
        commands = '\n'.join(step.get('run', '') for step in job['steps'])
        self.assertIn('ci/bottom-panel-diagnostic-smoke.sh', commands)
        self.assertIn('ci/bottom-panel-diagnostic-build.sh', commands)
        self.assertNotIn('continue-on-error', json.dumps(workflow))
        self.assertIn(next(s['run'] for s in old['steps'] if s['name'] == 'Source and real Swift runtime tests'), commands)
        helper = ROOT / 'ci/bottom_panel_diagnostic.py'
        self.assertTrue(helper.is_file())
        module = runpy.run_path(str(helper))
        self.assertEqual(module['BASE'], BASE)
        self.assertEqual(module['VERSION'], '0.1.13+bottomfix1.diag1')
        self.assertIn('BOTTOM_PANEL_DIAGNOSTIC', helper.read_text())
        self.assertIn('native-off', helper.read_text())
        self.assertIn('native-on', helper.read_text())
        for step in job['steps']:
            if 'run' in step:
                import subprocess
                self.assertEqual(subprocess.run(['bash', '-n'], input=step['run'], text=True, capture_output=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
