"""Original-bound bottom Settings data contracts, NOT executed UIKit proof."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BottomGestureReferenceTests(unittest.TestCase):
    def test_original_geometry_settings_resource(self):
        path = ROOT / 'Preferences/Resources/BottomGestureReference.json'
        self.assertTrue(path.is_file(), 'bottom gesture Settings reference resource is missing')
        data = json.loads(path.read_bytes())
        self.assertEqual(data['schemaVersion'], 1)
        self.assertEqual(data['referencePackageSHA256'], '240362fc1846f697025122e4788d04bbd1920b8f5102bcfc5642a9a14b62837a')
        self.assertEqual(data['referenceBinarySHA256'], 'a3e95d0028907909bc521a687934fa362cef18c4c813a787ff2a4b9e0eba6586')
        sections = data['sections']
        self.assertEqual([s['id'] for s in sections], ['left', 'right', 'policy', 'portrait', 'landscape-enable', 'landscape-parameters'])
        numeric = [row for section in sections for row in section['rows'] if row['kind'] == 'slider']
        expected = [
            ('bottomTriggerPosition', 0, 50, 30),
            ('bottomTriggerRightPosition', 0, 50, 30),
            ('bottomTriggerSensitivity', 0, 10, 7),
            ('bottomTriggerArea', 0, 100, 18),
            ('bottomTriggerExtraArea', 0, 100, 40),
            ('bottomTriggerExtraPlusArea', 0, 100, 60),
            ('bottomTriggerPositionLandscape', 0, 50, 20),
            ('bottomTriggerRightPositionLandscape', 0, 50, 20),
            ('bottomTriggerSensitivityLandscape', 0, 10, 7),
            ('bottomTriggerAreaLandscape', 0, 100, 40),
            ('bottomTriggerExtraAreaLandscape', 0, 100, 70),
            ('bottomTriggerExtraPlusAreaLandscape', 0, 100, 100),
        ]
        self.assertEqual([(r['key'], r['minimum'], r['maximum'], r['defaultNumber']) for r in numeric], expected)
        self.assertEqual(len({r['id'] for r in numeric}), len(expected))
        self.assertEqual(sections[3]['footer'], '数值单位均为屏幕宽度或高度的百分比。\n注意：最小触发高度 < +手势最小触发高度 < ++手势最小触发高度 < 最高触发高度')
        self.assertTrue(all(r.get('visibleWhen') == 'bottomUpOnLandscapeEnabled' for r in sections[5]['rows']))


if __name__ == '__main__':
    unittest.main()
