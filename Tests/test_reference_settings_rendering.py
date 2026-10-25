"""Executable source wiring contracts, NOT a Swift/UIKit runtime test."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Preferences/SettingsController.swift"


class ReferenceSettingsRenderingTests(unittest.TestCase):
    def test_reference_resource_drives_settings_in_own_bundle(self):
        source = SOURCE.read_text()
        self.assertIn('Bundle(for: TapLockSettingsController.self)', source,
                      'settings must load its reference data from the Preferences bundle')
        self.assertIn('"SettingsReference"', source)
        self.assertIn('JSONDecoder()', source)
        for collection in ('rootSections', 'homeSections', 'actionCategories', 'basicActions'):
            self.assertIn(collection, source)

    def test_actions_never_advertise_editing_or_sorting(self):
        source = SOURCE.read_text()
        self.assertIn('canEditRowAt indexPath: IndexPath) -> Bool { return false }', source)
        self.assertIn('canMoveRowAt indexPath: IndexPath) -> Bool { return false }', source)

    def test_reference_available_kinds_are_exact_not_only_present_somewhere(self):
        source = SOURCE.read_text()
        self.assertIn('Set(basicActions.filter { $0.available }.compactMap { $0.actionKind }) ==', source)

    def test_reference_optional_icons_and_existing_preference_owners(self):
        source = SOURCE.read_text()
        self.assertIn('let image: String?', source)
        self.assertIn('if let symbol = entry.image { cell.imageView?.image = UIImage(systemName: symbol) }', source)
        self.assertEqual(source.count('TapLockPreferences.writeAction('), 1)
        self.assertEqual(source.count('TapLockPreferences.writeEnabled('), 1)
        for forbidden in ('CFPreferencesSet', 'UserDefaults', 'UIApplication.shared.open',
                          'openApplicationWithBundleID', 'performAction', 'SiriService'):
            self.assertNotIn(forbidden, source)

    def test_snapshot_and_real_icon_chain_are_settings_only(self):
        source = SOURCE.read_text()
        self.assertEqual(source.count('InstalledApplications.choices()'), 1)
        self.assertIn('case .applicationPicker:', source)
        self.assertIn('ApplicationIcons()', source)
        self.assertIn('applicationIcons.image(identifier: choice.identifier)', source)
        self.assertIn('InstalledApplications.choice(identifier: choice.identifier) != nil', source)

    def test_disabled_rows_have_ui_and_direct_delivery_guards(self):
        from bottom_swipe_baseline import system_mute_source
        source = system_mute_source('Preferences/SettingsController.swift')
        self.assertIn('guard let reference = reference else { return }', source)
        self.assertIn('rowIsAvailable(row), row.kind == "link" else { return }', source)
        self.assertIn('reference.actionCategories[indexPath.row].available, indexPath.row < 2 else { return }', source)
        self.assertIn('let selected = entries[indexPath.row].action else { return }', source)
        self.assertIn('page == .homeScreen, sender.isEnabled', source)
        self.assertIn('switches["homescreenDoubleTapEnabled"] === sender', source)
        self.assertIn('cell.isUserInteractionEnabled = false', source)
        self.assertIn('cell.accessibilityTraits.insert(.notEnabled)', source)
        self.assertNotIn('isHidden', source)

    def test_search_filters_original_order_and_refreshes_selection(self):
        source = SOURCE.read_text()
        self.assertIn('all.filter { $0.title.range(of: query, options: .caseInsensitive) != nil }', source)
        self.assertIn('query.isEmpty ? all', source)
        body = source.split('func updateSearchResults(for searchController: UISearchController)', 1)[1].split('\n    }', 1)[0]
        self.assertIn('refreshSelection()', body)
        self.assertIn('reloadData()', body)

    def test_runtime_harness_remains_baseline_compatible_and_asserts_behavior(self):
        harness = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        for marker in ('--expect-reference-baseline-failure', '--expect-reference-fixed',
                       'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE: root navigation differs from reference',
                       'REFERENCE_SETTINGS_UIKIT_PASS:', 'REFERENCE_SETTINGS_FAIL:'):
            self.assertIn(marker, harness)
        self.assertIn('TLConstructDetail(TapLockSettingsController.self, legacy)', harness)
        self.assertIn('runRoundTrip(true)', harness)
        self.assertIn('runRoundTrip(false)', harness)
        self.assertIn('Bundle.main.url(forResource: "SettingsReference"', harness)
        self.assertNotIn('SettingsReference.load', harness)
        self.assertNotIn('SettingsReference.BasicAction', harness)
        self.assertIn('table.delegate?.tableView?(table, didSelectRowAt: path)', harness)
        self.assertIn('toggle.sendActions(for: .valueChanged)', harness)
        self.assertIn('samePreferences(before)', harness)
        self.assertIn('ApplicationIcons.load(identifier: id)', harness)
        self.assertIn('checkUnavailableResources()', harness)

    def test_actual_resource_matches_decoder_shape_without_requiring_unknown_icons(self):
        reference = json.loads((ROOT / 'Preferences/Resources/SettingsReference.json').read_text())
        self.assertIsInstance(reference['schemaVersion'], int)
        for key in ('root', 'home', 'actions', 'basic', 'application', 'selected', 'choose'):
            self.assertIsInstance(reference['titles'][key], str)
        for key in ('rootSections', 'homeSections'):
            for section in reference[key]:
                self.assertIsInstance(section['id'], str)
                for row in section['rows']:
                    self.assertIsInstance(row['id'], str)
                    self.assertIsInstance(row['title'], str)
                    self.assertIsInstance(row['available'], bool)
                    self.assertIn(row['kind'], ('switch', 'link', 'button'))
                    if 'defaultValue' in row:
                        self.assertIsInstance(row['defaultValue'], bool)
        for entry in reference['basicActions']:
            self.assertTrue(entry['image'] is None or isinstance(entry['image'], str))
            self.assertIsInstance(entry['referenceSlot'], int)
            self.assertTrue(entry['actionKind'] is None or isinstance(entry['actionKind'], str))
        source = SOURCE.read_text()
        self.assertIn('reference.phaseNotice + "\\n原版说明（非本阶段功能）：\\n" + reference.originalSelectedFooter', source)
        self.assertNotIn('拖动', reference['originalSelectedFooter'])

    def test_navigation_uses_declared_reference_destinations_with_whitelist(self):
        source = SOURCE.read_text()
        self.assertIn('switch row.destination', source)
        self.assertIn('switch reference.actionCategories[indexPath.row].destination', source)
        self.assertIn('case "home" where page == .root:', source)
        self.assertIn('case "actions" where page == .homeScreen:', source)

    def test_harness_uses_valid_inferred_for_in_pattern(self):
        harness = (ROOT / 'Tests/ReferenceSettingsApp.swift').read_text()
        self.assertNotRegex(harness, r'for\s+\w+\s*:\s*CFPropertyList\s+in')


if __name__ == '__main__':
    unittest.main(verbosity=2)
