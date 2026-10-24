"""Native-launch/icon regression wiring; not handset freeze or launch proof."""
import re
import unittest
from pathlib import Path
from test_source import source

ROOT = Path(__file__).resolve().parents[1]


class NativeAppContracts(unittest.TestCase):
    def test_springboard_compile_graph_contains_no_launchservices_or_catalog(self):
        makefile = source('Makefile')
        paths = re.search(r'^TapLock_FILES = (.+)$', makefile, re.M)[1].split()
        self.assertIn('Sources/AppAction.swift', paths)
        self.assertNotIn('Shared/Applications.swift', paths)
        text = '\n'.join(source(path) for path in paths)
        for forbidden in ('LSApplicationWorkspace', 'LSApplicationProxy', 'LSApplicationRecord',
                          'InstalledApplications', 'openApplicationWithBundleID:'):
            self.assertNotIn(forbidden, text)
        body = source('Sources/HomeDoubleTap.swift').split('func recognized(', 1)[1]
        self.assertEqual(body.count('AppAction.open(identifier: identifier)'), 1)

    def test_native_entry_requires_owned_springboard_method_and_exact_bool_abi(self):
        text = source('Sources/AppAction.swift')
        for token in ('Thread.isMainThread', 'validBundleIdentifier(identifier)',
                      'NSClassFromString("SpringBoard")', '"sharedApplication"',
                      'application.isKind(of: springBoardType)', 'class_copyMethodList',
                      'class_getSuperclass', 'method_getName', 'ObjectIdentifier(springBoardType)',
                      '"launchApplicationWithIdentifier:suspended:"',
                      'returns: "B", arguments: ["@", "B"]',
                      '@convention(c) (AnyObject, Selector, NSString, Bool) -> Bool'):
            self.assertIn(token, text)
        self.assertEqual(text.count('invoke(application, selector, identifier as NSString, false)'), 1)
        for forbidden in ('InstalledApplications', 'LSApplication', 'LockAction', 'DispatchQueue',
                          'asyncAfter', 'Timer(', 'semaphore', '.wait(', 'sleep(', 'openURL', 'URL('):
            self.assertNotIn(forbidden, text)

    def test_settings_loads_cached_real_icons_with_checked_int32_and_double_abi(self):
        text = source('Preferences/ApplicationIcons.swift')
        for token in ('final class ApplicationIcons', 'private var cache:', 'cache[identifier]',
                      '"_applicationIconImageForBundleIdentifier:format:scale:"',
                      'returns: "@", arguments: ["@", "i", "d"]',
                      'Int32, CGFloat', 'UIGraphicsImageRenderer', 'CGSize(width: 32, height: 32)',
                      '.alwaysOriginal', '"app.dashed"', 'Thread.isMainThread'):
            self.assertIn(token, text)
        for forbidden in ('InstalledApplications', 'allApplications', 'LSApplication', 'LockAction'):
            self.assertNotIn(forbidden, text)
        settings = source('Preferences/SettingsController.swift', settings_layout=True)
        self.assertIn('private let applicationIcons = ApplicationIcons()', settings)
        self.assertIn('cell.imageView?.image = applicationIcons.image(identifier: choice.identifier)', settings)
        self.assertIn('cell.imageView?.contentMode = .scaleAspectFit', settings)
        self.assertIn('ApplicationIcons.swift', source('Preferences/Makefile'))
        self.assertNotIn('AppAction.swift', source('Preferences/Makefile'))

    def test_cloud_executes_native_behavior_and_old_missing_icon_regression(self):
        script = (ROOT / 'ci/open-app-smoke.sh').read_text()
        for token in ('Tests/NativeAppRuntimeTests.swift', 'Sources/AppAction.swift',
                      'NATIVE_APP_BASELINE_EXPECTED_FAILURE', 'NATIVE_APP_TESTS.txt',
                      'SpringBoard action touched LaunchServices', 'restored == original'):
            self.assertIn(token, script)
        ui = (ROOT / 'ci/settings-construction-smoke.sh').read_text()
        for token in ('-DAPP_ICONS', 'Preferences/ApplicationIcons.swift', 'icon-baseline',
                      'SETTINGS_CONSTRUCTION_FAIL: App picker icon missing'):
            self.assertIn(token, ui)
        app = (ROOT / 'Tests/SettingsConstructionApp.swift').read_text()
        for token in ('App picker icon missing', 'App picker icon canvas must be 32 points',
                      'repeated App cell rendering must reuse the cached icon'):
            self.assertIn(token, app)
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertIn('NATIVE_APP_TESTS.txt', workflow)


if __name__ == '__main__':
    unittest.main(verbosity=2)
