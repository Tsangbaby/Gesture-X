"""Independent package lane; does not certify the unresolved Simulator regression."""
import json
import shlex
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class PackageRecoveryContracts(unittest.TestCase):
    def workflow(self):
        path = ROOT / '.github/workflows/package-recovery.yml'
        self.assertTrue(path.is_file(), 'Missing independent cloud Mac package lane')
        return json.loads(path.read_text())

    def test_package_lane_has_no_simulator_or_dependency_on_simulator_verdict(self):
        workflow = self.workflow()
        self.assertEqual(workflow['on'], {'push': {'branches': ['ci/bottom-package-8271e08'],
            'paths': ['.github/workflows/package-recovery.yml', 'Tests/test_package_recovery_ci.py']}})
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        self.assertEqual(set(workflow['jobs']), {'roothide-package'})
        job = workflow['jobs']['roothide-package']
        self.assertEqual(job['runs-on'], 'macos-15')
        self.assertNotIn('needs', job)
        self.assertNotIn('continue-on-error', json.dumps(job))
        self.assertNotIn('simctl', '\n'.join(step.get('run', '') for step in job['steps']))
        self.assertNotIn('settings-construction-smoke.sh', json.dumps(job))
        self.assertEqual(job['env']['THEOS_PACKAGE_SCHEME'], 'roothide')
        self.assertLessEqual(job['timeout-minutes'], 35)

    def test_original_host_gates_and_pinned_tools_are_preserved(self):
        original = json.loads((ROOT / '.github/workflows/build.yml').read_text())['jobs']['roothide']
        job = self.workflow()['jobs']['roothide-package']
        self.assertEqual(job['env'], original['env'])
        def command(steps, name):
            return next(step['run'] for step in steps if step.get('name') == name)
        self.assertIn(command(original['steps'], 'Source and real Swift runtime tests'),
                      command(job['steps'], 'Source and real Swift runtime tests'))
        self.assertIn(command(original['steps'], 'Install packaging tools and pinned RootHide Theos'),
                      command(job['steps'], 'Install packaging tools and pinned RootHide Theos'))
        names = [step['name'] for step in job['steps']]
        self.assertLess(names.index('Source and real Swift runtime tests'), names.index('Compile and package RootHide'))
        self.assertIn('bash ci/build.sh', command(job['steps'], 'Compile and package RootHide'))

    def test_scope_report_never_claims_full_regression_or_device_pass(self):
        job = self.workflow()['jobs']['roothide-package']
        commands = '\n'.join(step.get('run', '') for step in job['steps'])
        scope = next(step['run'] for step in job['steps']
                     if step['name'] == 'Freeze exact production scope and disclose pending validation')
        program = shlex.split(scope.split('python3 -B -c ', 1)[1])
        self.assertEqual(len(program), 1)
        commands += '\n' + program[0]
        self.assertIn('VALIDATION_SCOPE.json', commands)
        self.assertIn('8271e08dfe20b6f6cc71f2631b7824f9755d9854', commands)
        self.assertIn("'full_simulator_regression': 'unresolved; not executed in this package lane'", commands)
        self.assertIn("'device_tested': False", commands)
        self.assertIn("'source_sha': os.environ['GITHUB_SHA']", commands)
        self.assertIn("'git', 'diff', '--name-only', base, 'HEAD'", commands)
        self.assertIn("assert changed ==", commands)
        self.assertIn('40258681550', commands)
        self.assertNotIn('TARGET_CODESIGN=', commands)

    def test_failure_logs_are_uploaded_and_success_artifact_is_exact_sha(self):
        steps = self.workflow()['jobs']['roothide-package']['steps']
        uploads = [step for step in steps if step.get('uses', '').startswith('actions/upload-artifact@')]
        self.assertEqual(len(uploads), 1)
        self.assertEqual(uploads[0]['if'], 'always()')
        self.assertEqual(uploads[0]['with']['name'], 'taplock-roothide-recovery-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}')
        self.assertEqual(uploads[0]['with']['if-no-files-found'], 'error')
        self.assertIn('source-tests.log', json.dumps(steps))
        self.assertIn('tool-setup.log', json.dumps(steps))
        for step in steps:
            if 'uses' in step:
                self.assertRegex(step['uses'], r'@[a-f0-9]{40}$')
            if 'run' in step:
                self.assertTrue(step['run'].startswith('set -euo pipefail\n'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
