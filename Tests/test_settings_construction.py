"""Wiring and frozen-source guards; executed UIKit proof comes from cloud CI."""
import hashlib
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "72826b2a558b03e20a7dd5e98047dfdecc489202"


class SettingsConstructionContracts(unittest.TestCase):
    def test_missing_legacy_super_initializer_is_exercised_before_packaging(self):
        steps = json.loads((ROOT / ".github/workflows/build.yml").read_text())["jobs"]["roothide"]["steps"]
        names = [step["name"] for step in steps]
        gate = "Settings constructor regression (iOS Simulator fixture)"
        self.assertIn(gate, names)
        self.assertLess(names.index(gate), names.index("Compile and package RootHide"))
        step = next(step for step in steps if step["name"] == gate)
        self.assertIn("ci/settings-construction-smoke.sh", step["run"])
        script_path = ROOT / "ci/settings-construction-smoke.sh"
        self.assertTrue(script_path.is_file())
        script = script_path.read_text()
        for token in (BASELINE, 'show "$BASELINE:$path"', "--expect-legacy-failure", "--expect-fixed",
                      "SettingsConstructionApp.swift", "SettingsConstructionFixture.m",
                      "Shared/Preferences.swift", "Preferences/SettingsController.swift",
                      "simctl", "timeout=120", "SETTINGS_CONSTRUCTION_TESTS.txt"):
            self.assertIn(token, script)

    def test_fixture_has_no_legacy_super_implementation_and_never_ships(self):
        path = ROOT / "Tests/SettingsConstructionFixture.m"
        self.assertTrue(path.is_file())
        fixture = path.read_text()
        base = fixture.split("@implementation PSViewController", 1)[1].split("@end", 1)[0]
        self.assertNotIn("initForContentSize", base)
        self.assertIn("@catch (NSException", fixture)
        self.assertIn("respondsToSelector", fixture)
        app = (ROOT / "Tests/SettingsConstructionApp.swift").read_text()
        for token in ("class_getInstanceMethod", "NSInvalidArgumentException",
                      "loadViewIfNeeded", "UISwitch", "BASELINE_EXPECTED_FAILURE",
                      "FIXED_CONSTRUCTION_PASS"):
            self.assertIn(token, app)
        for makefile in ("Makefile", "Preferences/Makefile"):
            self.assertNotIn("SettingsConstruction", (ROOT / makefile).read_text())
        self.assertFalse(any("SettingsConstruction" in p.name for p in (ROOT / "layout").rglob("*")))

    def test_gesture_lock_preferences_and_build_graph_remain_byte_exact(self):
        frozen = {
            "Sources/HomeDoubleTap.swift": "b1614281d2ae17799075a59fd963931b2548047b866d9f33d31a0a045df98eef",
            "Sources/LockAction.swift": "532850be046aa6fcd67946d7e9e665a54193052df868fa2525e7d86f1a162dc4",
            "Sources/PrivateAPI.swift": "a2b9fdeed907801f2259175f88e328123c6f0c759c9a3f1008b521a9f9db6aa7",
            "Preferences/SettingsController.swift": "054976307197cebc5e34bca966a354ba9518e0e462bc6df350cb1b97fe96ef15",
            "Interfaces/TapLockPreferencesHost/PSViewController.h": "e1694c2e656c15ec16a92236159a6bd31d9a1125625ca80e154530b953074cf0",
            "Shared/Preferences.swift": "227f50e3b867615426e4860f01b515a71c81844d64522b3269309ba6651aada5",
            "Makefile": "0f835fbf44bf22e0535f7cf0d395ed0ec96fe20d23d9214d83bbd8df7eabe6c8",
            "Preferences/Makefile": "044e5562d1ea542b56b1283793cce69ba61eb899beb5c9d527002d81e02e95b8",
            "Interfaces/TapLockPreferencesHost/module.modulemap": "a8eaa6b0f7925ffa1ec469469e2f694abc02448ca89cfd1d5cbe2e4d4257b303",
        }
        # Retire only the intentionally replaced Orion entry owner. Keep the
        # old Home/Makefile digests by inverting only the authorized exact hunks.
        inverses = {
            "Sources/HomeDoubleTap.swift": [
                ('              (location as String == "SBIconLocationRoot" ||\n'
                 '               location as String == "SBIconLocationRootWithWidgets"),',
                 '              location as String == "SBIconLocationRoot",'),
                ('              let switcherType = NSClassFromString("SBMainSwitcherViewController"),\n'
                 '              let switcher = PrivateAPI.object(switcherType as AnyObject, "sharedInstanceIfExists"),',
                 '              let switcher = PrivateAPI.object(UIApplication.shared, "_switcherController"),'),
            ],
            "Makefile": [
                ('Sources/NativeHook.swift Sources/Bootstrap.swift', 'Sources/Tweak.x.swift'),
                ('TapLock_LIBRARIES = substrate\n', ''),
                ('TapLock_SWIFTFLAGS = -IInterfaces -enable-experimental-feature SymbolLinkageMarkers\n', ''),
            ],
        }
        for name, digest in frozen.items():
            data = (ROOT / name).read_bytes()
            if name in inverses:
                text = data.decode()
                for after, before in inverses[name]:
                    self.assertEqual(text.count(after), 1, name)
                    text = text.replace(after, before, 1)
                data = text.encode()
            self.assertEqual(hashlib.sha256(data).hexdigest(), digest, name)
        self.assertFalse((ROOT / "Sources/Tweak.x.swift").exists())
        text = (ROOT / "Preferences/SettingsController.swift").read_text()
        suffix = text[text.index("    override func loadView() {"):]
        self.assertEqual(hashlib.sha256(suffix.encode()).hexdigest(),
                         "e4ffae1a0bb6059351f00f55281b8429b6563cd085c982ee55527554ffc4130c")


if __name__ == "__main__":
    unittest.main(verbosity=2)
