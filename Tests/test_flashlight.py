"""The original flashlight row enables one saved action, not another gesture."""
import json
import unittest
from pathlib import Path

from system_mute_baseline import accepted_source

ROOT = Path(__file__).resolve().parents[1]
ACCEPTED_BASIC = {
    'SYSTEM_SCREENSHOT', 'SYSTEM_CONTROLCENTER', 'SYSTEM_COVER',
    'SYSTEM_LOCKSCREEN', 'SYSTEM_SWITCHER', 'PLAYPAUSE_MEDIA',
    'PREVIOUS_MEDIA', 'NEXT_MEDIA',
}


class FlashlightContracts(unittest.TestCase):
    def test_original_flashlight_row_is_one_more_available_exclusive_action(self):
        data = json.loads(accepted_source('Preferences/Resources/SettingsReference.json'))
        rows = {row['id']: row for row in data['basicActions']}
        row = rows['TOGGLE_FLASHLIGHT']
        self.assertEqual((row['title'], row['image'], row['referenceSlot'], row['referenceActionNumber']),
                         ('开关手电', 'flashlight.on.fill', 16, 33))
        self.assertTrue(row['available'], 'Original TOGGLE_FLASHLIGHT remains disabled')
        self.assertEqual(row['actionKind'], 'flashlight')
        self.assertEqual({row['id'] for row in rows.values() if row['available']},
                         ACCEPTED_BASIC | {'TOGGLE_FLASHLIGHT'})

    def test_single_record_storage_save_only_settings_and_proven_dispatch_are_connected(self):
        prefs = accepted_source('Shared/Preferences.swift')
        for token in ('case flashlight', 'kind == "flashlight", record.count == 1',
                      'case .flashlight:', 'record = ["kind": "flashlight"]'):
            self.assertIn(token, prefs)
        settings = accepted_source('Preferences/SettingsController.swift')
        self.assertIn('case "flashlight": return .flashlight', settings)
        self.assertIn('basicActions.compactMap({ $0.action }).count == 9', settings)
        self.assertNotIn('FlashlightAction', settings)
        dispatch = accepted_source('Sources/HomeDoubleTap.swift').split('func recognized(', 1)[1]
        self.assertIn('case .flashlight:\n            FlashlightAction.toggle()', dispatch)
        self.assertEqual(dispatch.count('FlashlightAction.toggle()'), 1)
        self.assertLess(dispatch.index('isBlankHit('), dispatch.index('FlashlightAction.toggle()'))
        self.assertEqual(prefs.count('CFNotificationCenterPostNotification('), 2)
        self.assertEqual((ROOT / 'Makefile').read_text().count('Sources/FlashlightAction.swift'), 1)
        self.assertNotIn('FlashlightAction', (ROOT / 'Preferences/Makefile').read_text())

    def test_provider_uses_uint64_native_state_and_one_void_branch_without_a_fallback(self):
        import re
        path = ROOT / 'Sources/FlashlightAction.swift'
        self.assertTrue(path.is_file(), 'Missing the actual Swift flashlight provider')
        code = re.sub(r'(?m)^\s*//.*$', '', path.read_text())
        for token in ('Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                      'NSClassFromString("SBUIFlashlightController")',
                      'PrivateAPI.object(controllerType as AnyObject, "sharedInstance")',
                      'controller.isKind(of: controllerType)', 'object_getClass(controller)',
                      'returns: "Q"', 'returns: "v", arguments: ["Q"]',
                      '@convention(c) (AnyObject, Selector) -> UInt64',
                      '@convention(c) (AnyObject, Selector) -> Void',
                      '@convention(c) (AnyObject, Selector, UInt64) -> Void',
                      'if readLevel(controller, levelSelector) != 0',
                      'turnOff(controller, turnOffSelector)',
                      'setLevel(controller, setLevelSelector, loadLevel(controller, loadLevelSelector))'):
            self.assertIn(token, code)
        self.assertEqual(code.count('PrivateAPI.checkedMethod('), 4)
        self.assertEqual(code.count('turnOff(controller, turnOffSelector)'), 1)
        self.assertEqual(code.count('setLevel(controller, setLevelSelector, loadLevel(controller, loadLevelSelector))'), 1)
        self.assertLess(code.index('LockAction.unlockedManager()'), code.index('NSClassFromString('))
        self.assertLess(code.index('arguments: ["Q"]'), code.index('if readLevel('))
        for forbidden in ('AVCaptureDevice', 'AVFlashlight', 'turnFlashlightOnForReason',
                          'turnFlashlightOffForReason', 'asyncAfter', 'DispatchQueue', 'Timer(',
                          'dlsym(', 'dlopen(', 'perform(', 'print(', 'NSLog(', 'impactOccurred',
                          'takeRetainedValue', 'returns: "q"', 'returns: "B"'):
            self.assertNotIn(forbidden, code)

    def test_active_version_advances_once_from_the_accepted_media_baseline(self):
        import plistlib
        import re
        from release_contract import EXPECTED_RELEASE_VERSION
        old = json.loads((ROOT / 'Tests/media_tracks_baseline.json').read_bytes())
        original_control = old['hunks']['control'][0]['after']
        baseline = re.search(r'(?m)^Version: (\S+)$', original_control).group(1)
        pieces = [int(value) for value in baseline.split('.')]
        pieces[-1] += 1
        self.assertEqual(re.search(r'(?m)^Version: (\S+)$', accepted_source('control')).group(1), '.'.join(map(str, pieces)))
        self.assertIn('Version: ' + EXPECTED_RELEASE_VERSION + '\n', (ROOT / 'control').read_text())
        info = plistlib.loads((ROOT / 'Preferences/Resources/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleVersion'], EXPECTED_RELEASE_VERSION)
        self.assertEqual(info['CFBundleShortVersionString'], EXPECTED_RELEASE_VERSION)

    def test_cloud_executes_and_revalidates_flashlight_reports_without_expanding_triggers(self):
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_bytes())
        self.assertEqual(workflow['on']['push']['branches'], ['main'])
        self.assertEqual(set(workflow['jobs']), {'roothide'})
        steps = workflow['jobs']['roothide']['steps']
        native = next(step['run'] for step in steps if step['name'] == 'Source and real Swift runtime tests')
        self.assertIn('bash ci/flashlight-smoke.sh', native)
        self.assertIn('python3 -B ci/flashlight_guard.py --validate-suite "$RUNNER_TEMP/FLASHLIGHT_TESTS.txt" "$GITHUB_SHA"', native)
        ui = next(step['run'] for step in steps if step['name'] == 'Settings constructor regression (iOS Simulator fixture)')
        self.assertIn('--with-track-baseline --with-flashlight-baseline', ui)
        package = next(step['run'] for step in steps if step['name'] == 'Compile and package RootHide')
        self.assertIn('cp "$RUNNER_TEMP/FLASHLIGHT_TESTS.txt" "$OUT_DIR/FLASHLIGHT_TESTS.txt"', package)

    def test_package_verifier_excludes_new_native_fixtures_and_provider_from_settings(self):
        verifier = (ROOT / 'ci/verify_package.py').read_text()
        self.assertIn('"FlashlightRuntimeTests"', verifier)
        self.assertIn('b"SBUIFlashlightController"', verifier)
        self.assertIn('b"_loadFlashlightLevel"', verifier)
        self.assertIn('Flashlight provider leaked into Settings binary', verifier)
