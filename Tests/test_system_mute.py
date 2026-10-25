"""Focused source contracts, not Apple execution or handset effect proof."""
import hashlib
import json
import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def code(text):
    # Preserve strings; ignore nested Swift comments, including braces/quotes.
    out, i, depth = [], 0, 0
    while i < len(text):
        if depth:
            if text.startswith('/*', i): depth += 1; i += 2
            elif text.startswith('*/', i): depth -= 1; i += 2
            else: i += 1
        elif text.startswith('//', i):
            end = text.find('\n', i)
            i = len(text) if end < 0 else end
        elif text.startswith('/*', i): depth = 1; i += 2
        elif text[i] == '"':
            start = i; i += 1
            while i < len(text):
                if text[i] == '\\': i += 2
                elif text[i] == '"': i += 1; break
                else: i += 1
            out.append(text[start:i])
        else: out.append(text[i]); i += 1
    return ''.join(out)


def body(text, signature):
    text = code(text)
    start = text.find(signature)
    assert start >= 0, 'missing implementing function: ' + signature
    start = text.find('{', start)
    depth = 1
    # A string cannot supply braces for function scope.
    tokens = re.finditer(r'"(?:\\.|[^"\\])*"|[{}]', text[start + 1:])
    for token in tokens:
        if token.group() == '{': depth += 1
        elif token.group() == '}': depth -= 1
        if depth == 0: return text[start + 1:start + 1 + token.start()]
    raise AssertionError('unbalanced function: ' + signature)


def read(path):
    p = ROOT / path
    return p.read_text() if p.exists() else ''


def preference_contract(text):
    assert 'case systemMute' in code(text), 'systemMute action case missing'
    assert 'if kind == "systemMute", record.count == 1 { return .systemMute }' in body(text, 'static func readAction()'), 'exact one-field systemMute decode missing'
    assert 'case .systemMute:\n            record = ["kind": "systemMute"]' in body(text, 'static func writeAction('), 'single-record systemMute persistence missing'


def provider_contract(text):
    toggle = body(text, 'static func toggle() -> Bool')
    required = ['Thread.isMainThread', 'LockAction.unlockedManager() != nil',
                'NSClassFromString("SpringBoard")', 'PrivateAPI.object(applicationType as AnyObject, "sharedApplication")',
                'application.isKind(of: applicationType)', 'class_getInstanceMethod(applicationClass, ringerSelector) != nil',
                'PrivateAPI.object(application, "ringerControl")', 'NSClassFromString("SBMainWorkspace")',
                'PrivateAPI.object(workspaceType as AnyObject, "sharedInstanceIfExists")',
                'workspace.isKind(of: workspaceType)', 'PrivateAPI.object(workspace, "ringerControl")',
                'NSClassFromString("SBRingerControl")', 'controller.isKind(of: controllerType)',
                'returns: "B"', 'returns: "v", arguments: ["B"]', 'returns: "v", arguments: ["i"]',
                '@convention(c) (AnyObject, Selector) -> Bool',
                '@convention(c) (AnyObject, Selector, Bool) -> Void',
                '@convention(c) (AnyObject, Selector, Int32) -> Void',
                'let old = readMuted(controller, mutedSelector)',
                'setMuted(controller, setMutedSelector, !old)',
                'showHUD(controller, hudSelector, Int32(old ? 1 : 0))', 'return true']
    compact = lambda x: re.sub(r'\s+', ' ', x)
    for token in required:
        assert compact(token) in compact(toggle), 'provider contract missing: ' + token
    assert toggle.index('Thread.isMainThread') < toggle.index('LockAction.unlockedManager()') < toggle.index('NSClassFromString("SpringBoard")')
    direct = body(toggle, 'if class_getInstanceMethod(applicationClass, ringerSelector) != nil')
    assert 'return false' in direct and 'SBMainWorkspace' not in direct, 'direct failure must not use fallback'
    assert toggle.index('arguments: ["i"]') < toggle.index('let old =') < toggle.index('setMuted(controller,') < toggle.index('showHUD(controller,')
    for call in ['readMuted(controller,', 'setMuted(controller,', 'showHUD(controller,']:
        assert toggle.count(call) == 1, 'native invocation not exactly once: ' + call
    for banned in ['value(forKey', 'perform(', 'DispatchQueue', 'Timer', 'setRingerMuted:reason:', 'setVolume', 'dlsym', 'MSHook', 'print(']:
        assert banned not in code(text), 'forbidden mechanism: ' + banned


class SystemMuteSourceTests(unittest.TestCase):
    def test_provider_checked_owner_and_native_order(self):
        provider_contract(read('Sources/SystemMuteAction.swift'))

    def test_dispatch_settings_build_and_release(self):
        dispatch = body(read('Sources/HomeDoubleTap.swift'), 'private func recognized(')
        self.assertIn('case .systemMute:\n            SystemMuteAction.toggle()', dispatch)
        self.assertEqual(dispatch.count('SystemMuteAction.toggle()'), 1)
        settings = code(read('Preferences/SettingsController.swift'))
        self.assertIn('case "systemMute": return .systemMute', settings)
        self.assertIn('basicActions.compactMap({ $0.action }).count == 10', settings)
        reference = json.loads(read('Preferences/Resources/SettingsReference.json'))
        row = reference['basicActions'][32]
        self.assertEqual((row['id'], row['referenceSlot'], row['available'], row.get('actionKind')), ('SYSTEM_MUTE', 32, True, 'systemMute'))
        self.assertEqual(sum(x['available'] for x in reference['basicActions']), 10)
        self.assertIn('Sources/SystemMuteAction.swift', read('Makefile').split('TapLock_FILES = ')[1].splitlines()[0])
        from release_contract import EXPECTED_RELEASE_VERSION
        self.assertIn('Version: ' + EXPECTED_RELEASE_VERSION + '\n', read('control'))
        info = plistlib.loads((ROOT / 'Preferences/Resources/Info.plist').read_bytes())
        for key in ['CFBundleVersion', 'CFBundleShortVersionString']:
            self.assertEqual(info[key], EXPECTED_RELEASE_VERSION)

    def test_provider_mutants_are_rejected(self):
        source = read('Sources/SystemMuteAction.swift')
        for before, after in [
            ('Thread.isMainThread,', ''), ('LockAction.unlockedManager() != nil,', ''),
            ('application.isKind(of: applicationType),', ''), ('workspace.isKind(of: workspaceType),', ''),
            ('controller.isKind(of: controllerType),', ''), ('returns: "B"', 'returns: "i"'),
            ('arguments: ["B"]', 'arguments: ["i"]'), ('arguments: ["i"]', 'arguments: ["q"]'),
            ('!old)', 'old)'), ('Int32(old ? 1 : 0)', 'Int32(old ? 0 : 1)'),
            ('class_getInstanceMethod(applicationClass, ringerSelector) != nil', 'PrivateAPI.object(application, "ringerControl") != nil'),
            ('let old = readMuted(controller, mutedSelector)', 'let old = false'),
        ]:
            self.assertIn(before, source)
            with self.assertRaises(AssertionError, msg=before):
                provider_contract(source.replace(before, after, 1))
        provider_contract('// setVolume { \'\n/* MSHook { */\n' + source)

    def test_old_owners_and_display_bytes_frozen(self):
        frozen = {
            'Sources/PrivateAPI.swift': 'a2b9fdeed907801f2259175f88e328123c6f0c759c9a3f1008b521a9f9db6aa7',
            'Sources/LockAction.swift': '8c902edd37e44ea4b5afc4e21b078fa6415b22e6efc55264b4af6d2d66e07387',
            'Sources/NativeHook.swift': '45f6dbe10dcdceb201edf0bb8ba539b7e8be6e1f5f968ddc76ecdb2753edccba',
            'Sources/Bootstrap.swift': 'c06f200f456f8103990378d60888e7810e0185ec3152a1026759e429c68d8e07',
            'Sources/FlashlightAction.swift': '6991354a10287c9e7dead5d27cc9654f3e8505f12cc51cc4d06280b2c8eadec7',
        }
        for path, digest in frozen.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest, path)
        home = (ROOT / 'Sources/HomeDoubleTap.swift').read_bytes()
        added = b'        case .systemMute:\n            SystemMuteAction.toggle()\n'
        self.assertEqual(home.count(added), 1)
        self.assertEqual(hashlib.sha256(home.replace(added, b'')).hexdigest(), '71f9027d460677dfc7107d0303f8f459f1935cddb976249a1ded2d7ff78fc87b')
        reference = (ROOT / 'Preferences/Resources/SettingsReference.json').read_bytes()
        before = b'"referenceActionNumber": 50,\n      "available": true,\n      "actionKind": "systemMute"'
        self.assertEqual(reference.count(before), 1)
        original = reference.replace(before, b'"referenceActionNumber": 50,\n      "available": false,\n      "actionKind": null')
        self.assertEqual(hashlib.sha256(original).hexdigest(), '19c1f055a515b3b96ca7b26f245ad110d5c3124ea33d9697dafca9639d1c741f')

    def test_native_harness_contract_not_execution(self):
        source = code(read('Tests/SystemMuteRuntimeTests.swift'))
        main = body(source, 'static func main()')
        self.assertIn('#if SYSTEM_MUTE_BASELINE', main)
        baseline = main.split('#if SYSTEM_MUTE_BASELINE', 1)[1].split('#else', 1)[0]
        self.assertNotIn('.systemMute', baseline)
        self.assertNotIn('SystemMuteAction', baseline)
        self.assertIn('raw(TapLockPreferences.actionKey, ["kind": "systemMute"] as CFDictionary)', baseline)
        self.assertIn('TapLockPreferences.readAction() != .unavailable, "persisted systemMute action is unavailable"', baseline)
        self.assertIn('actual production Swift/Objective-C fixtures, NOT handset ringer/HUD proof', main)
        for signature in ['static func preferences()', 'static func owners()', 'static func ringerABI()', 'static func admission()', 'static func isolatedGetters()']:
            self.assertTrue(body(source, signature).strip())
        prefs = body(source, 'static func preferences()')
        self.assertEqual(prefs.split('require(actions.count', 1)[0].count('["kind":'), 11)
        self.assertIn('actions.count == 11', prefs)
        self.assertIn('for enabled in [nil, kCFBooleanFalse, kCFBooleanTrue]', prefs)
        self.assertIn('for (before, record) in actions', prefs)
        self.assertIn('for (after, replacement) in actions', prefs)
        for literal in ['TLSystemMuteApplicationFixture', 'TLSystemMuteWorkspaceFixture', 'TLSystemMuteRingerFixture', 'TLSystemMuteLockFixture']:
            self.assertEqual(source.count('"' + literal + '"'), 1)
        self.assertNotIn('class_replaceMethod', source)
        self.assertNotIn('method_setImplementation', source)
        self.assertIn('let restore = cleanup; cleanup = nil', body(source, 'static func fail('))
        self.assertIn('return sync() && same(stored(TapLockPreferences.actionKey), action)', main)
        self.assertIn('fflush(stdout)', main)

    def test_preferences_single_record(self):
        preference_contract(read('Shared/Preferences.swift'))

    def test_comment_aware_function_scope(self):
        self.assertEqual(body('/* { \' */ func f() { let s = "}" // }\n return true } func g() {}', 'func f()').strip(), 'let s = "}" \n return true')
        with self.assertRaises(AssertionError):
            preference_contract('// case systemMute\nfunc f() {}')


if __name__ == '__main__':
    unittest.main()
