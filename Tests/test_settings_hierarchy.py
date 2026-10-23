"""Settings hierarchy wiring only; real UIKit execution is a separate CI gate."""
import hashlib
import plistlib
import unittest
from pathlib import Path
from settings_hierarchy_baseline import FIXTURE, invert_settings_hierarchy

ROOT = Path(__file__).resolve().parents[1]


class SettingsHierarchyContracts(unittest.TestCase):
    def test_ui_candidate_version_is_newer_without_renaming_the_preference_domain(self):
        fields = dict(line.split(': ', 1) for line in (ROOT / 'control').read_text().splitlines()
                      if ': ' in line)
        info = plistlib.loads((ROOT / 'Preferences/Resources/Info.plist').read_bytes())
        self.assertEqual(fields['Version'], '0.1.2')
        self.assertEqual(info['CFBundleVersion'], fields['Version'])
        self.assertEqual(info['CFBundleShortVersionString'], fields['Version'])
        self.assertEqual(fields['Package'], 'com.tsangbaby.taplock')

    def test_accepted_lock_is_reachable_through_the_home_screen_category(self):
        text = (ROOT / "Preferences/SettingsController.swift").read_text()
        for token in ('case root, homeScreen, doubleTapAction',
                      '"主屏幕的手势"', '"启用主屏双击"',
                      '"选择双击动作"', '"系统锁屏"',
                      'init(page: Page)', 'TapLockSettingsController(page: .homeScreen)',
                      'TapLockSettingsController(page: .doubleTapAction)',
                      'didSelectRowAt indexPath', '.disclosureIndicator', '.checkmark',
                      'popViewController(animated: true)'):
            self.assertIn(token, text)
        self.assertEqual(text.count('UISwitch()'), 1)
        self.assertEqual(text.count('TapLockPreferences.writeEnabled(sender.isOn)'), 1)
        self.assertIn('UITableViewCell(style: .value1', text)
        for forbidden in ('LockAction', 'HomeDoubleTap', 'URLSession', 'NSUserDefaults',
                          'UserDefaults', 'writeAction', 'fatalError', 'TODO', 'FIXME'):
            self.assertNotIn(forbidden, text)

    def test_accepted_runtime_preferences_loader_and_build_graph_are_byte_exact(self):
        self.assertEqual(FIXTURE['baseline'], '94b384d64ce44705e754f4695c98661110db76ff')
        for relative, digest in FIXTURE['frozen'].items():
            with self.subTest(path=relative):
                self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), digest)
        restored = invert_settings_hierarchy((ROOT / 'Preferences/SettingsController.swift').read_text())
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), FIXTURE['baseline_sha256'])

    def test_exact_inverse_rejects_missing_or_duplicate_ui_hunks(self):
        text = (ROOT / 'Preferences/SettingsController.swift').read_text()
        for hunk in FIXTURE['hunks']:
            for mutation in (text.replace(hunk['after'], '', 1), text + hunk['after']):
                with self.assertRaises(AssertionError):
                    invert_settings_hierarchy(mutation)

    def test_exact_inverse_does_not_hide_unrelated_drift(self):
        text = (ROOT / 'Preferences/SettingsController.swift').read_text()
        restored = invert_settings_hierarchy(text + '\n// unrelated drift\n')
        self.assertNotEqual(hashlib.sha256(restored.encode()).hexdigest(), FIXTURE['baseline_sha256'])

    def test_navigation_harness_compiles_against_old_controllers_without_new_delegate_methods(self):
        app = (ROOT / 'Tests/SettingsConstructionApp.swift').read_text()
        self.assertNotRegex(app, r'\b(?:controller|home|action)\.tableView\([^\n]*didSelectRowAt:')
        for table in ('table', 'homeTable', 'actionTable'):
            self.assertIn(table + '.delegate?.tableView?(', app)

    def test_same_uikit_harness_rejects_the_old_layout_before_testing_current_navigation(self):
        script = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        self.assertIn('HIERARCHY_BASELINE=' + FIXTURE['baseline'], script)
        self.assertIn('show "$HIERARCHY_BASELINE:$path"', script)
        self.assertLess(script.index('run_case "$STABLE"'), script.index('run_case "$ROOT"'))
        self.assertIn('SETTINGS_CONSTRUCTION_FAIL: root must link to 主屏幕的手势', script)
        app = (ROOT / 'Tests/SettingsConstructionApp.swift').read_text()
        for token in ('real switch did not persist', 'reentry lost the persisted gesture value',
                      'action navigation changed enable state', 'savedToggle.sendActions',
                      'unimplemented actions must not be exposed', 'actionTrips += 1'):
            self.assertIn(token, app)


if __name__ == "__main__":
    unittest.main(verbosity=2)
