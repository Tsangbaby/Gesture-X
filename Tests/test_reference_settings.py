"""Source-bound declarative UI contract, NOT Swift/UIKit/device execution proof."""
import hashlib
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORACLE = ROOT / 'Tests/reference_settings_oracle.json'
RESOURCE = ROOT / 'Preferences/Resources/SettingsReference.json'
ORACLE_SHA256 = 'a0f639ae24ece250a155ee2f88dcb3bc109c56501a05ae2f5f0a366ac4b82fd8'
ALLOWED_PRODUCTION_EDITS = {
    'Preferences/SettingsController.swift', 'control', 'Preferences/Resources/Info.plist',
}
SUPPORTED = {
    'SYSTEM_SCREENSHOT': 'screenshot',
    'SYSTEM_CONTROLCENTER': 'controlCenter',
    'SYSTEM_COVER': 'notificationCenter',
    'SYSTEM_LOCKSCREEN': 'lock',
    'SYSTEM_SWITCHER': 'appSwitcher',
    'PLAYPAUSE_MEDIA': 'playPause',
    'PREVIOUS_MEDIA': 'previousTrack',
    'NEXT_MEDIA': 'nextTrack',
}


def oracle():
    return json.loads(ORACLE.read_text())


class ReferenceSettingsContract(unittest.TestCase):
    def resource(self):
        self.assertTrue(RESOURCE.is_file(), 'Missing source-bound SettingsReference.json')
        # Preserve the eight-action historical catalog assertion at its exact input stage.
        from flashlight_baseline import accepted_source as flashlight_accepted_source
        return json.loads(flashlight_accepted_source('Preferences/Resources/SettingsReference.json'))

    def test_original_evidence_oracle_is_frozen_independently_of_ui_resource(self):
        self.assertEqual(hashlib.sha256(ORACLE.read_bytes()).hexdigest(), ORACLE_SHA256)
        data = oracle()
        self.assertEqual(data['referencePackageSHA256'],
                         '240362fc1846f697025122e4788d04bbd1920b8f5102bcfc5642a9a14b62837a')
        self.assertEqual(data['referenceBinarySHA256'],
                         'a3e95d0028907909bc521a687934fa362cef18c4c813a787ff2a4b9e0eba6586')

    def test_resource_provenance_and_independent_product_boundary_are_explicit(self):
        actual, expected = self.resource(), oracle()
        self.assertEqual(actual['schemaVersion'], 1)
        for field in ('referencePackageSHA256', 'referenceBinarySHA256'):
            self.assertEqual(actual[field], expected[field])
        self.assertEqual(actual['titles']['root'], 'TapLock')
        self.assertEqual(actual['titles']['home'], '主屏幕的手势')
        self.assertEqual(actual['titles']['actions'], '选择动作')
        self.assertEqual(actual['titles']['basic'], '选择基础动作')
        self.assertEqual(actual['titles']['application'], '选择应用')
        self.assertEqual(actual['titles']['selected'], '已选择')
        self.assertEqual(actual['titles']['choose'], '选择动作')
        self.assertEqual(set(actual['excludedReferenceSurfaces']), {
            'originalAuthorLicensingPurchasesAndPromotion',
            'deviceAndThirdPartyConditionalCatalogAdditions',
            'multipleActionsEditingSortingAndPanelExecution',
        })
        self.assertIn('单个动作', actual['phaseNotice'])
        self.assertIn('未实现', actual['phaseNotice'])

    def test_root_navigation_matches_original_order_and_only_home_is_available(self):
        data = self.resource()
        rows = [row for section in data['rootSections'] for row in section['rows']]
        reference = oracle()['root']['ordered_navigation_links']
        ids = {r['key_and_id'] for r in reference}
        nav = [r for r in rows if r['id'] in ids]
        self.assertEqual([(r['id'], r['title']) for r in nav],
                         [(r['key_and_id'], r['label_zh_CN']) for r in reference])
        self.assertEqual([r['id'] for r in nav if r['available']], ['homescreenOptions'])
        self.assertEqual([r['id'] for r in nav if r.get('phoneOnly')],
                         ['bottomOptions', 'reachabilityOptions'])
        self.assertEqual(next(r for r in nav if r['available'])['destination'], 'home')
        enabled = next(r for r in rows if r['id'] == 'enabled')
        self.assertEqual((enabled['title'], enabled['kind'], enabled['defaultValue'], enabled['available']),
                         ('启用插件', 'switch', True, False))
        management = [r for r in rows if r['kind'] == 'button']
        self.assertEqual([r['title'] for r in management],
                         ['注销设备生效', '备份所有设置', '还原设置备份', '重置所有设置'])
        self.assertFalse(any(r['available'] for r in management))
        self.assertIn('总开关', [s.get('header') for s in data['rootSections']])
        self.assertIn('杂项', [s.get('header') for s in data['rootSections']])

    def test_home_retains_all_seven_three_row_groups_and_original_defaults(self):
        data = self.resource()
        sections = [s for s in data['homeSections'] if s['rows']]
        self.assertEqual(len(sections), 7)
        self.assertEqual([len(s['rows']) for s in sections], [3] * 7)
        actual = [r for s in sections for r in s['rows']]
        expected = [r for r in oracle()['home']['ordered_specifiers']
                    if r['kind'] in ('switch', 'action_link')]
        self.assertEqual(len(actual), oracle()['home']['control_count'])
        self.assertEqual([(r['id'], r['title'], r['kind']) for r in actual],
                         [(r['specifier_id'], r['label_zh_CN'],
                           'link' if r['kind'] == 'action_link' else 'switch') for r in expected])
        self.assertEqual([r['id'] for r in actual if r['available']],
                         ['homescreenDoubleTapEnabled', 'homescreenDoubleTap'])
        for row in actual:
            if row['kind'] == 'switch':
                self.assertIs(row['defaultValue'], False)
        self.assertEqual(actual[1]['destination'], 'actions')
        self.assertFalse(any('hide' in k.lower() or 'visiblewhen' in k.lower()
                             for row in actual for k in row), 'Original Home has no dependency hiding')
        self.assertTrue(any('主屏幕下划触发区域宽度' in (s.get('footer') or '')
                            for s in data['homeSections']))

    def test_action_categories_match_both_original_sections_and_source_order(self):
        data = self.resource()
        expected = oracle()['actionPicker']['sections'][1]['ordered_categories']
        actual = data['actionCategories']
        self.assertEqual([(r['id'], r['title']) for r in actual],
                         [(r['key'], r['zh_CN']) for r in expected])
        self.assertEqual([r['id'] for r in actual if r['available']],
                         ['BASIC_ACTION', 'OPEN_APPLICATION'])
        self.assertEqual([r['destination'] for r in actual if r['available']], ['basic', 'application'])
        self.assertIn('多个动作', data['originalSelectedFooter'])
        self.assertIn('面板', data['originalSelectedFooter'])
        self.assertEqual(data['originalSelectedFooter'],
                         '- 选择单个动作直接执行，多个动作显示面板\n'
                         '- 非编辑状态下，点按编辑动作\n'
                         '- 编辑状态下，点按删除动作')

    def test_basic_catalog_matches_original_constructor_order(self):
        actual, expected = self.resource()['basicActions'], oracle()['basicActions']
        self.assertEqual(len(actual), len(expected))
        self.assertEqual([r['referenceSlot'] for r in actual], list(range(len(expected))))
        self.assertEqual([(r['id'], r['title'], r['image'], r['referenceSlot'], r['referenceActionNumber'])
                          for r in actual],
                         [(r['title_key'], r['zh_CN'], r['image'], r['slot_0based'], r['action_id'])
                          for r in expected])
        self.assertEqual({r['id']: r['actionKind'] for r in actual if r['available']}, SUPPORTED)
        for row in actual:
            self.assertEqual(row['available'], row['id'] in SUPPORTED)
            if not row['available']:
                self.assertIsNone(row['actionKind'])
        self.assertFalse(any(r['id'] == 'OPEN_APPLICATION' for r in actual),
                         'Open Application belongs to its own original category')

    def test_existing_runtime_and_storage_files_are_byte_exact_018(self):
        from media_play_pause_baseline import invert_media_play_pause
        from flashlight_baseline import accepted_media_tracks_source as track_accepted_source
        manifest = json.loads((ROOT / 'Tests/settings_layout_baseline.json').read_text())
        self.assertEqual(manifest['baseline'], 'f3a2e138fa9ac93d250645e9c66226b074d429ee')
        self.assertEqual(len(manifest['frozen']), 24)
        self.assertEqual(set(manifest['before_text']), ALLOWED_PRODUCTION_EDITS)
        self.assertEqual(set(manifest['candidate_sha256']), ALLOWED_PRODUCTION_EDITS)
        for relative, digest in manifest['frozen'].items():
            if relative not in ALLOWED_PRODUCTION_EDITS:
                with self.subTest(relative=relative):
                    text = invert_media_play_pause(relative, track_accepted_source(relative))
                    self.assertEqual(hashlib.sha256(text.encode('utf-8')).hexdigest(), digest)


if __name__ == '__main__':
    unittest.main(verbosity=2)
