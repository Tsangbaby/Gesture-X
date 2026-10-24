"""Source/resource contracts only. These do NOT compile or execute Swift/UIKit."""
import re
import plistlib
import unittest
from pathlib import Path
from settings_layout_baseline import accepted_source
from release_contract import EXPECTED_RELEASE_VERSION

ROOT = Path(__file__).resolve().parents[1]


def source(relative, *, settings_layout=False):
    """Current source by default; historical UI must explicitly undo 0.1.9."""
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"Missing implementation: {relative}")
    text = accepted_source(relative) if settings_layout else path.read_text(encoding="utf-8")
    # Retain quoted strings; discard comments so comments cannot satisfy guards.
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda match: match[0] if match[0].startswith('"') else '',
                  text, flags=re.S)


class PreferenceContracts(unittest.TestCase):
    def test_default_off_and_single_cross_process_domain(self):
        text = source("Shared/Preferences.swift")
        self.assertIn('static let domain = "com.tsangbaby.taplock"', text)
        self.assertIn('static let enabledKey = "Enabled"', text)
        self.assertIn('static let defaultEnabled = false', text)
        self.assertIn("kCFPreferencesCurrentUser", text)
        self.assertIn("kCFPreferencesAnyHost", text)
        self.assertIn("CFBooleanGetTypeID()", text)
        self.assertIn("CFPreferencesSynchronize", text)
        self.assertLess(text.index("guard synchronize() else"),
                        text.index("CFNotificationCenterPostNotification"))
        self.assertIn("CFPreferencesSetValue(enabledKey as CFString, previous", text)


class RuntimeContracts(unittest.TestCase):
    def test_private_dispatch_checks_each_abi_component(self):
        text = source("Sources/PrivateAPI.swift")
        for token in ("method_getNumberOfArguments", "method_copyReturnType",
                      "method_copyArgumentType", "object_getClass",
                      'returns: "@"', 'returns: "B"', "takeUnretainedValue()"):
            self.assertIn(token, text)
        self.assertIn('["@", ":"] + arguments', text)
        self.assertIn("String(cString: raw) == expected", text)
        self.assertNotIn("perform(", text)

    def test_lock_request_is_typed_once_and_not_a_display_fake(self):
        text = source("Sources/LockAction.swift")
        self.assertIn("Thread.isMainThread", text)
        self.assertIn('"sharedInstanceIfExists"', text)
        self.assertIn('NSClassFromString("SpringBoard")', text)
        self.assertIn('"sharedApplication"', text)
        self.assertIn('"_simulateLockButtonPress"', text)
        self.assertIn("application.isKind(of: applicationType)", text)
        self.assertIn('returns: "v")', text)
        self.assertIn("@convention(c) (AnyObject, Selector) -> Void", text)
        self.assertEqual(text.count("invoke(application, selector)"), 1)
        self.assertLess(text.index("unlockedManager() != nil"),
                        text.index("invoke(application, selector)"))
        for selector in ("isUILocked", "isLockScreenVisible", "isUIUnlocking"):
            self.assertIn(f'"{selector}") == false', text)
        for forbidden in ("lockUIFromSource", "asyncAfter", "Timer", "brightness",
                          "sleepWakeButtonInteraction", "lockHardwareButton", "return true",
                          "ProcessInfo", "operatingSystemVersion", "IOHID", "UIView.animate"):
            self.assertNotIn(forbidden, text)


class GestureContracts(unittest.TestCase):
    def test_hook_is_local_gated_and_forwards_original_once(self):
        text = source("Sources/NativeHook.swift")
        self.assertIn("MSHookMessageEx", text)
        self.assertIn('"SBIconListView"', text)
        self.assertIn("PrivateAPI.checkedMethod", text)
        self.assertIn('"didMoveToWindow"', text)
        self.assertEqual(text.count("previous(view, selector)"), 1)
        self.assertIn("HomeDoubleTap.shared.attach(to: view)", text)
        self.assertIn("HomeDoubleTap.shared.start()", text)
        self.assertIn("DispatchQueue.main.async", source("Sources/Bootstrap.swift"))
        self.assertNotIn("fatalError", text)

    def test_blank_root_hit_and_direct_finger_only(self):
        text = source("Sources/HomeDoubleTap.swift")
        for token in ("touch.type == .direct", "touch.view === host",
                      '"iconLocation"', '"SBIconLocationRoot"',
                      "window.hitTest", "=== host", "host.bounds.contains(point)"):
            self.assertIn(token, text)

    def test_home_portrait_unlocked_and_not_editing(self):
        text = source("Sources/HomeDoubleTap.swift")
        for token in ("Thread.isMainThread", "!UIAccessibility.isVoiceOverRunning",
                      "scene.interfaceOrientation.isPortrait", ".foregroundActive",
                      '"SBHomeScreenWindow"', '"isShowingHomescreen") == true',
                      '"SBMainSwitcherViewController"', '"isMainSwitcherVisible") == false',
                      '"iconManager"', '"isEditing") == false',
                      "LockAction.unlockedManager() != nil", "scroll.isDragging",
                      "scroll.isDecelerating", ".began", ".changed"):
            self.assertIn(token, text)

    def test_native_touches_and_gesture_graph_are_not_taken_over(self):
        text = source("Sources/HomeDoubleTap.swift")
        for token in ("numberOfTapsRequired = 2", "numberOfTouchesRequired = 1",
                      "cancelsTouchesInView = false", "delaysTouchesBegan = false",
                      "delaysTouchesEnded = false", "shouldRecognizeSimultaneouslyWith"):
            self.assertIn(token, text)
        for forbidden in ("require(toFail:", "Timer(", "asyncAfter", "addSubview(",
                          "IOHID", "sendEvent(", "method_exchangeImplementations"):
            self.assertNotIn(forbidden, text)

    def test_registry_type_accepts_native_peers_and_delegate_parameters(self):
        text = source("Sources/HomeDoubleTap.swift")
        declaration = re.search(r"let recognizers = NSHashTable<(\w+)>\.weakObjects", text)
        self.assertIsNotNone(declaration)
        self.assertEqual(declaration[1], "UIGestureRecognizer")
        delegate_types = set(re.findall(r"_ gestureRecognizer:\s*(\w+)", text))
        self.assertEqual(delegate_types, {declaration[1]})
        self.assertIn("view.gestureRecognizers ?? [] where !recognizers.contains(peer)", text)
        self.assertNotIn("as! UITapGestureRecognizer", text)

    def test_weak_ownership_no_duplicate_install_and_cancel_on_reload(self):
        text = source("Sources/HomeDoubleTap.swift")
        for token in ("NSHashTable<UIGestureRecognizer>.weakObjects()",
                      "first(where:", "removeGestureRecognizer", "recognizers.remove",
                      "guard !started", "CFNotificationCenterAddObserver",
                      "UIApplication.willResignActiveNotification",
                      "UIApplication.didBecomeActiveNotification"):
            self.assertIn(token, text)
        reload_body = text.split("func reloadPreferences()", 1)[1].split("\n    }", 1)[0]
        self.assertLess(reload_body.index("cancelAll()"),
                        reload_body.index("TapLockPreferences.readEnabled()"))
        self.assertIn("refreshRecognizers()", reload_body)

    def test_recognized_event_rechecks_before_single_lock_request(self):
        text = source("Sources/HomeDoubleTap.swift")
        body = text.split("func recognized(", 1)[1].split("\n    }", 1)[0]
        for token in ("sender.state == .ended", "!isDispatchingAction",
                      "recognizers.contains(sender)", "isEligible(in: host)",
                      "isBlankHit(in: host", "defer { isDispatchingAction = false }"):
            self.assertIn(token, body)
        self.assertEqual(body.count("LockAction.requestLock()"), 1)
        self.assertLess(body.index("isEligible(in: host)"), body.index("LockAction.requestLock()"))


class SettingsAndBuildContracts(unittest.TestCase):
    def test_settings_uses_real_loader_superclass_and_one_switch(self):
        text = source("Preferences/SettingsController.swift", settings_layout=True)
        self.assertIn("import TapLockPreferencesHost", text)
        self.assertIn("@objc(TapLockSettingsController)", text)
        self.assertIn("TapLockSettingsController: PSViewController", text)
        self.assertIn("return 1", text)
        self.assertEqual(text.count("UISwitch()"), 1)
        self.assertIn(".valueChanged", text)
        self.assertIn("TapLockPreferences.readEnabled()", text)
        self.assertIn("TapLockPreferences.writeEnabled(sender.isOn)", text)
        self.assertIn("UIAlertController", text)
        header = source("Interfaces/TapLockPreferencesHost/PSViewController.h")
        self.assertIn("@interface PSViewController : UIViewController", header)
        self.assertNotIn("initForContentSize:", header)
        self.assertIn("@objc(initForContentSize:)", text)
        self.assertIn("convenience init(contentSize: CGSize)", text)
        self.assertIn("self.init(nibName: nil, bundle: nil)", text)
        self.assertNotIn("super.init(contentSize:", text)
        self.assertNotIn("@implementation", header)
        self.assertIn('header "PSViewController.h"',
                      source("Interfaces/TapLockPreferencesHost/module.modulemap"))

    def test_all_production_swift_files_are_in_the_correct_target(self):
        def members(makefile, variable):
            text = source(makefile).replace("\\\n", " ")
            match = re.search(rf"^{variable}_FILES\s*=\s*(.+)$", text, re.M)
            self.assertIsNotNone(match)
            parent = (ROOT / makefile).parent
            return {(parent / item).resolve() for item in match[1].split()}
        self.assertEqual(members("Makefile", "TapLock"),
                         {p.resolve() for directory in ("Shared", "Sources")
                          for p in (ROOT / directory).glob("*.swift")
                          if p != ROOT / "Shared/Applications.swift"})
        self.assertEqual(members("Preferences/Makefile", "TapLockPrefs"),
                         {(ROOT / "Shared/Preferences.swift").resolve(),
                          (ROOT / "Shared/Applications.swift").resolve(),
                          (ROOT / "Sources/PrivateAPI.swift").resolve(),
                          (ROOT / "Preferences/ApplicationIcons.swift").resolve(),
                          (ROOT / "Preferences/SettingsController.swift").resolve()})
        self.assertEqual(members("Makefile", "TapLock") | members("Preferences/Makefile", "TapLockPrefs"),
                         {p.resolve() for directory in ("Shared", "Sources", "Preferences")
                          for p in (ROOT / directory).glob("*.swift")})
        for makefile in ("Makefile", "Preferences/Makefile"):
            self.assertIn("iphone:clang:latest:15.0", source(makefile))
            self.assertIn("arm64 arm64e", source(makefile))
        self.assertIn("-IInterfaces", source("Makefile"))
        self.assertIn("TapLock_LIBRARIES = substrate", source("Makefile"))
        self.assertIn("TapLockNativeRuntime", source("Sources/NativeHook.swift"))
        self.assertIn("SUBPROJECTS += Preferences", source("Makefile"))

    def test_loader_identity_filter_and_version_match(self):
        paths = ("TapLock.plist", "Preferences/Resources/Info.plist",
                 "layout/Library/PreferenceLoader/Preferences/TapLock.plist")
        for path in paths:
            self.assertTrue((ROOT / path).is_file(), f"Missing plist: {path}")
        tweak, info, entry = [plistlib.loads((ROOT / path).read_bytes()) for path in paths]
        self.assertEqual(tweak["Filter"], {"Bundles": ["com.apple.springboard"]})
        self.assertEqual(entry["entry"]["detail"], info["NSPrincipalClass"])
        self.assertEqual(entry["entry"]["bundle"], info["CFBundleExecutable"])
        self.assertIs(entry["entry"]["isController"], True)
        self.assertEqual(info["MinimumOSVersion"], "15.0")
        control = source("control")
        version = re.search(r"^Version: (.+)$", control, re.M)[1]
        self.assertEqual(version, EXPECTED_RELEASE_VERSION)
        self.assertEqual(info["CFBundleVersion"], version)
        self.assertEqual(info["CFBundleShortVersionString"], version)
        self.assertIn("mobilesubstrate", control)
        self.assertNotIn("ORION", control)
        self.assertIn("preferenceloader", control)
        self.assertIn("firmware (>= 15.0)", control)

    def test_no_handwritten_non_swift_implementations_or_build_outputs(self):
        for path in ROOT.rglob("*"):
            if not path.is_file():
                continue
            # Native implementations are allowlisted simulator fixtures only.
            if path in {ROOT / "Tests/SettingsConstructionFixture.m",
                        ROOT / "Tests/NativeHookFixture.m"}:
                continue
            self.assertNotIn(path.suffix, (".m", ".mm", ".c", ".cpp", ".xm", ".x",
                                           ".deb", ".dylib", ".o", ".zip"), str(path))
        production = [p for folder in ("Sources", "Shared", "Preferences")
                      for p in (ROOT / folder).rglob("*.swift")]
        for path in production:
            text = source(path.relative_to(ROOT))
            for forbidden in ("TODO", "FIXME", "fatalError(", "try!", "password",
                              "http://", "https://", "URLSession"):
                self.assertNotIn(forbidden, text, str(path))


if __name__ == "__main__":
    unittest.main(verbosity=2)
