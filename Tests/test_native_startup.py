"""Static native-startup wiring; execution is separately gated on the cloud Mac."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeStartupContracts(unittest.TestCase):
    def test_tweak_has_retained_native_entry_without_orion(self):
        control = (ROOT / "control").read_text()
        self.assertNotIn("ORION", control)
        self.assertNotIn("orion", control.lower())
        makefile = (ROOT / "Makefile").read_text()
        self.assertNotIn(".x.swift", makefile)
        self.assertIn("Sources/Bootstrap.swift", makefile)
        self.assertIn("Sources/NativeHook.swift", makefile)
        self.assertIn("SymbolLinkageMarkers", makefile)
        self.assertIn("TapLock_LIBRARIES = substrate", makefile)
        self.assertFalse((ROOT / "Sources/Tweak.x.swift").exists())
        for name in ("NativeHookFixture", "NativeHookReactivation", "NativeStartupApp"):
            self.assertNotIn(name, makefile)
        for directory in ("Sources", "Shared", "Preferences", "Interfaces"):
            for path in (ROOT / directory).rglob("*"):
                if path.is_file():
                    self.assertNotRegex(path.read_text(), r"\b(?:import\s+Orion|ClassHook|OrionHookError)\b")
        bootstrap = (ROOT / "Sources/Bootstrap.swift").read_text()
        for token in ('@_used', '"__DATA,__mod_init_func"',
                      '@convention(c) () -> Void', 'DispatchQueue.main.async', 'TapLockRuntime.activate()'):
            self.assertIn(token, bootstrap)
        self.assertNotIn("mod_init_funcs", bootstrap)
        self.assertNotIn("NSClassFromString", bootstrap)
        hook = (ROOT / "Sources/NativeHook.swift").read_text()
        for token in ("MSHookMessageEx", '"didMoveToWindow"', "PrivateAPI.checkedMethod",
                      "method_getImplementation", "previous(view, selector)", "attach(to: view)",
                      "guard !started", "HomeDoubleTap.shared.start()"):
            self.assertIn(token, hook)
        self.assertEqual(hook.count("previous(view, selector)"), 1)
        self.assertLess(hook.index("previous(view, selector)"), hook.index("attach(to: view)"))
        header = (ROOT / "Interfaces/TapLockNativeRuntime/NativeRuntime.h").read_text()
        self.assertIn("MSHookMessageEx(Class", header)
        self.assertNotIn("@implementation", header)

    def test_home_gate_uses_the_switcher_singleton_and_both_known_root_locations(self):
        text = (ROOT / "Sources/HomeDoubleTap.swift").read_text()
        self.assertNotIn('"_switcherController"', text)
        self.assertIn('"SBMainSwitcherViewController"', text)
        self.assertIn('"sharedInstanceIfExists"', text)
        self.assertIn('"isMainSwitcherVisible") == false', text)
        self.assertIn('location as String == "SBIconLocationRoot" ||', text)
        self.assertIn('location as String == "SBIconLocationRootWithWidgets"', text)
        self.assertNotIn('contains("SBIconLocationRoot")', text)

    def test_startup_smoke_reports_checkpoints_and_failure_details(self):
        app = (ROOT / "Tests/NativeStartupApp.swift").read_text()
        for token in ("NATIVE_STARTUP_CHECKPOINT:", 'checkpoint("application launched")',
                      'checkpoint("before dlopen")', 'checkpoint("after dlopen")',
                      'checkpoint("verify hook")'):
            self.assertIn(token, app)
        script = (ROOT / "ci/native-startup-smoke.sh").read_text()
        for token in ("simctl exit status:", "DiagnosticReports", "CrashReporter",
                      "NativeStartup", "log', 'show'", "timeout=30"):
            self.assertIn(token, script)

    def test_real_startup_and_original_forwarding_are_executed_before_package(self):
        import json
        workflow = json.loads((ROOT / ".github/workflows/build.yml").read_text())
        steps = workflow["jobs"]["roothide"]["steps"]
        settings = (ROOT / "ci/settings-construction-smoke.sh").read_text()
        self.assertIn('bash "$ROOT/ci/native-startup-smoke.sh" "$DEVICE"', settings)
        smoke = (ROOT / "ci/native-startup-smoke.sh").read_text()
        for token in ("Makefile", "-O", "-dead_strip", "SymbolLinkageMarkers",
                      "Tests/NativeHookFixture.m", "Tests/NativeStartupApp.swift",
                      "NATIVE_STARTUP_PASS", "NATIVE_STARTUP_TESTS.txt", "simctl", "--console"):
            self.assertIn(token, smoke)
        self.assertEqual(smoke.count('-I "$ROOT/Interfaces"'), 2,
                         "Both the dylib and its test app must load the declaration module map")
        app = (ROOT / "Tests/NativeStartupApp.swift").read_text()
        for token in ("dlopen", "TLHookInstallCount", "originalCalls", "recognizersBeforeOriginal",
                      "numberOfTapsRequired", "removeFromSuperview", "NATIVE_STARTUP_PASS"):
            self.assertIn(token, app)
        build = next(s["run"] for s in steps if s.get("name") == "Compile and package RootHide")
        self.assertIn("NATIVE_STARTUP_TESTS.txt", build)


if __name__ == "__main__":
    unittest.main(verbosity=2)
