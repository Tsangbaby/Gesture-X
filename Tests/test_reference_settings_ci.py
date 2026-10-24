"""CI runner/guard/resource contracts; fake outputs below are guard unit inputs only."""
import json
import runpy
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEGATIVE = 'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE: root navigation differs from reference'
POSITIVE = ('REFERENCE_SETTINGS_UIKIT_PASS: 200 assertions; both native constructors; '
            'simulator fixture boundary only')


class ReferenceSettingsCIGates(unittest.TestCase):
    def guard(self):
        path = ROOT / 'ci/reference_settings_guard.py'
        self.assertTrue(path.is_file(), 'Missing strict reference settings completion guard')
        return runpy.run_path(str(path))['validate_completed_run']

    def test_actual_guard_requires_exact_mode_marker_and_transport_success(self):
        validate = self.guard()
        for mode, message in (('--expect-reference-fixed', POSITIVE),
                              ('--expect-reference-baseline-failure', NEGATIVE)):
            with self.subTest(mode=mode):
                self.assertEqual(validate(0, 'UIKit incidental log\n' + message + '\n', mode), message)
                for status, output in ((1, message), (0, ''), (0, message + '\n' + message),
                                       (0, NEGATIVE if mode.endswith('fixed') else POSITIVE),
                                       (0, message + '\nREFERENCE_SETTINGS_FAIL: contradiction')):
                    with self.subTest(status=status, output=output), self.assertRaises(ValueError):
                        validate(status, output, mode)
        for bad in (POSITIVE.replace('200 assertions', '0 assertions'),
                    POSITIVE.replace('200 assertions', 'NaN assertions'),
                    POSITIVE.replace('simulator fixture boundary only', 'device verified'),
                    POSITIVE + '\n' + NEGATIVE):
            with self.subTest(output=bad), self.assertRaises(ValueError):
                validate(0, bad, '--expect-reference-fixed')
        with self.assertRaises(ValueError):
            validate(0, POSITIVE, '--not-a-mode')

    def test_same_real_harness_runs_frozen_018_red_then_current_ui_green(self):
        runner = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        for token in ('REFERENCE_BASELINE=f3a2e138fa9ac93d250645e9c66226b074d429ee',
                      'show "$REFERENCE_BASELINE:$path"', 'REFERENCE_UIKIT_BASELINE_BYTES_VERIFIED',
                      'run_case "$ACCEPTED_UI" fixed', 'Tests/ReferenceSettingsApp.swift',
                      'reference_settings_guard.py', 'REFERENCE_SETTINGS_TESTS.txt',
                      'cp "$ROOT/Preferences/Resources/SettingsReference.json"',
                      'run_reference_case "$ACCEPTED_UI" reference-baseline --expect-reference-baseline-failure',
                      'run_reference_case "$ROOT" reference-fixed --expect-reference-fixed'):
            self.assertIn(token, runner)
        self.assertNotIn('run_case "$ROOT" fixed', runner)
        self.assertLess(runner.index('run_reference_case "$ACCEPTED_UI"'),
                        runner.index('run_reference_case "$ROOT"'))
        app = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertIn('DispatchQueue.main.async', app, 'Run after native UIApplication launch returns')
        self.assertIn('REFERENCE_SETTINGS_CHECKPOINT:', app)
        self.assertNotIn('SettingsReference.load', app)

    def test_new_ui_report_is_required_before_artifact_upload_without_widening_trigger(self):
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_text())
        self.assertEqual(workflow['on']['push']['branches'], ['main'])
        self.assertEqual(workflow['on']['workflow_dispatch'], {})
        self.assertEqual(set(workflow['jobs']), {'roothide'})
        steps = workflow['jobs']['roothide']['steps']
        package = next(s['run'] for s in steps if s['name'] == 'Compile and package RootHide')
        self.assertIn('cp "$RUNNER_TEMP/REFERENCE_SETTINGS_TESTS.txt"', package)
        gate = next(i for i, s in enumerate(steps) if s['name'].startswith('Settings constructor'))
        build = next(i for i, s in enumerate(steps) if s['name'] == 'Compile and package RootHide')
        self.assertLess(gate, build)

    def test_package_gate_checks_exact_shipped_resource_not_only_source_presence(self):
        module = runpy.run_path(str(ROOT / 'ci/verify_package.py'))
        self.assertIn('verify_settings_reference_resource', module,
                      'Package gate must validate the extracted source-bound resource')
        expected = (ROOT / 'Preferences/Resources/SettingsReference.json').read_bytes()
        result = module['verify_settings_reference_resource'](expected, expected)
        self.assertEqual(result['home_controls'], 21)
        self.assertEqual(result['categories'], 6)
        self.assertEqual(result['basic_catalog'], 68)
        for mutated in (b'', expected + b'\n', expected.replace('控制中心'.encode(), b'wrong', 1)):
            with self.subTest(mutated_bytes=len(mutated)), self.assertRaises(ValueError):
                module['verify_settings_reference_resource'](mutated, expected)
        text = (ROOT / 'ci/verify_package.py').read_text()
        self.assertIn('Library/PreferenceBundles/TapLockPrefs.bundle/SettingsReference.json', text)
        self.assertIn('verify_settings_reference_resource((dest / required[5]).read_bytes()', text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
