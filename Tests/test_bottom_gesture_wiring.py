"""Bottom integration SOURCE contracts; these do not execute Swift or UIKit."""
import json
import re
import runpy
import subprocess
import sys
import unittest
from pathlib import Path

from test_system_mute import body, code

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return (ROOT / relative).read_bytes().decode('utf-8')


ROOT_SELECT = 'func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)'
BOTTOM_ROUTE = 'case "bottom" where page == .root && row.id == "bottomOptions":'
NEXT_ROUTE = 'case "actions" where page == .homeScreen:'


def root_bottom_route(source):
    """Only executable text in the unique production delegate/bottom branch."""
    source = code(source)
    assert source.count(ROOT_SELECT) == 1, 'root delegate anchor must be unique'
    selection = body(source, ROOT_SELECT)
    assert selection.count(BOTTOM_ROUTE) == 1, 'bottom route anchor must be unique'
    assert selection.count(NEXT_ROUTE) == 1, 'next route anchor must be unique'
    start = selection.index(BOTTOM_ROUTE) + len(BOTTOM_ROUTE)
    end = selection.index(NEXT_ROUTE, start)
    return selection[start:end]


ROOT_ADMISSION_PREDICATES = (
    'isViewLoaded', 'tableView === view',
    'let navigationController = navigationController',
    'navigationController.topViewController === self',
    'let window = tableView.window',
    'navigationController.viewIfLoaded?.window === window',
    'let cell = tableView.cellForRow(at: indexPath)',
    'tableView.indexPath(for: cell) == indexPath',
    'tableView.visibleCells.contains(where: { $0 === cell })',
    'cell.isDescendant(of: tableView)', 'cell.window === window',
    'cell.accessibilityIdentifier == row.id', 'cell.isUserInteractionEnabled',
)
ROOT_TARGET_PREDICATES = (
    '!current.isHidden', 'current.alpha > 0.01', 'current.isUserInteractionEnabled',
)


def assert_root_admission_contract(case, source):
    route = root_bottom_route(source)
    admission = route.split('else { return }', 1)[0]
    for predicate in ROOT_ADMISSION_PREDICATES:
        case.assertIn(predicate, admission, 'root admission missing: ' + predicate)
    case.assertEqual(route.count('while let current = target'), 1, 'unique root target walk required')
    walk = body(route, 'while let current = target')
    target_guard = walk.split('else { return }', 1)[0]
    for predicate in ROOT_TARGET_PREDICATES:
        case.assertIn(predicate, target_guard, 'root admission missing: ' + predicate)
    for predicate in (
        'cell.convert(cell.bounds, to: window)',
        '.intersection(tableView.convert(tableView.bounds, to: window))',
        '.intersection(window.bounds)',
        'if current.clipsToBounds',
        'visibleRect = visibleRect.intersection(current.convert(current.bounds, to: window))',
        'if current === window { break }', 'target = current.superview',
        'guard !visibleRect.isNull, !visibleRect.isEmpty else { return }',
    ):
        case.assertIn(predicate, route, 'root admission missing: ' + predicate)
    push = 'navigationController.pushViewController(BottomGestureSettingsController(), animated: true)'
    case.assertEqual(route.count(push), 1, 'root must push exactly once through its admitted owner')
    case.assertLess(route.index('guard !visibleRect.isNull'), route.index(push))


class BottomGestureWiringTests(unittest.TestCase):
    def test_root_bottom_entry_requires_active_owner_and_visible_owned_target(self):
        assert_root_admission_contract(self, read('Preferences/SettingsController.swift'))

    def test_root_bottom_missing_guard_mutants_fail_the_target_assertion(self):
        source = code(read('Preferences/SettingsController.swift'))
        route = root_bottom_route(source)
        self.assertEqual(source.count(route), 1, 'mutation must affect only the admitted bottom route')
        assert_root_admission_contract(self, source)
        predicates = [p for p in ROOT_ADMISSION_PREDICATES
                      if not p.startswith('let ') and p != 'cell.isUserInteractionEnabled']
        predicates += list(ROOT_TARGET_PREDICATES)
        mutations = [(p, 'true /* ' + p + ' */') for p in predicates]
        mutations += [
            ('.intersection(tableView.convert(tableView.bounds, to: window))', ''),
            ('.intersection(window.bounds)', ''),
            ('if current.clipsToBounds', 'if false /* if current.clipsToBounds */'),
            ('visibleRect = visibleRect.intersection(current.convert(current.bounds, to: window))', ''),
            ('target = current.superview', 'target = nil'),
            ('guard !visibleRect.isNull, !visibleRect.isEmpty else { return }', ''),
        ]
        for predicate, replacement in mutations:
            with self.subTest(missing_guard=predicate):
                self.assertEqual(route.count(predicate), 1, 'missing-guard mutation anchor must be unique')
                mutant = source.replace(route, route.replace(predicate, replacement, 1), 1)
                # Only the intended missing predicate counts as a kill; parser,
                # anchor, import or unrelated assertion errors must escape.
                with self.assertRaisesRegex(AssertionError, re.escape('root admission missing: ' + predicate)):
                    assert_root_admission_contract(self, mutant)

    def test_root_admission_extraction_ignores_comments_and_rejects_ambiguous_anchors(self):
        source = read('Preferences/SettingsController.swift')
        comments = '// ' + ROOT_SELECT + ' { \\"\n/* ' + BOTTOM_ROUTE + ' /* nested } */ ' + NEXT_ROUTE + ' */\n'
        assert_root_admission_contract(self, comments + source)
        with self.assertRaisesRegex(AssertionError, 'root delegate anchor must be unique'):
            root_bottom_route(source + '\n' + ROOT_SELECT + ' {}')
        with self.assertRaisesRegex(AssertionError, 'bottom route anchor must be unique'):
            root_bottom_route(source.replace(BOTTOM_ROUTE, BOTTOM_ROUTE + BOTTOM_ROUTE, 1))

    def test_root_admission_uikit_regression_is_on_the_main_run_path(self):
        # Authored UIKit coverage only; these source assertions do not compile
        # or execute the app, and cannot establish UIKit behavior on Linux.
        harness = code(read('Tests/BottomGestureSettingsApp.swift'))
        self.assertIn('@main\n@MainActor\nfinal class BottomGestureSettingsApp:', harness)
        self.assertEqual(harness.count('private func testRootEntryAdmission()'), 1)
        run = body(harness, 'private func run()')
        self.assertEqual(run.count('testRootEntryAdmission()'), 1)
        launch = body(harness, 'func application(')
        self.assertIn('Task { @MainActor in await self.run() }', launch)
        self.assertIn('private func run() async', harness)
        self.assertLess(run.index('testMainQueueProgress()'), run.index('testRootEntryAdmission()'))
        regression = body(harness, 'private func testRootEntryAdmission()')
        for token in (
            'let originalRoot = TapLockSettingsController()', 'show(originalRoot)',
            'let rootTable = await table(originalRoot)', 'let retainedCell = await ownedCell(rootTable, path)',
            'let rootDelegate = rootTable.delegate', 'nav.pushViewController(other, animated: false)',
            'rootTable.cellForRow(at: path) === retainedCell',
            'rootTable.window === nav.view.window', 'nav.topViewController === other',
            'nav.view.addSubview(rootTable)', 'rootTable.removeFromSuperview()',
            'nav.topViewController === originalRoot && rootTable.window == nil',
            'foreignTable.dataSource = foreignSource', 'foreignTable.delegate = originalRoot',
            'ownedCell(foreignTable, path)',
            '"foreign-table"', '"stale-after-push"', '"in-window-non-top"', '"detached-root"',
            '"hidden-cell"', '"disabled-cell"', '"zero-alpha-cell"', '"clipped-out-cell"',
            '"detached-cell"', '"hidden-table"', '"disabled-table"', '"zero-alpha-table"',
            'retainedCell.isHidden = true', 'retainedCell.isUserInteractionEnabled = false',
            'retainedCell.alpha = 0', 'retainedCell.removeFromSuperview()',
            '!rootTable.bounds.intersects(rootTable.convert(retainedCell.bounds, from: retainedCell))',
            'rootDelegate?.tableView?(rootTable, didSelectRowAt: path)',
            'nav.viewControllers.count == 2', 'nav.viewControllers.first === originalRoot',
            'nav.topViewController is BottomGestureSettingsController',
            'require(samePreferences(before)', 'reject(rootTable, "duplicate-after-valid-push")',
        ):
            self.assertIn(token, regression, 'missing authored real UIKit root regression: ' + token)
        reject = body(regression, 'func reject(')
        for token in ('let stack = nav.viewControllers',
                      'rootDelegate?.tableView?(eventTable, didSelectRowAt: path)',
                      'nav.viewControllers.count == stack.count',
                      'zip(nav.viewControllers, stack).allSatisfy({ $0.0 === $0.1 })',
                      'require(samePreferences(before)'):
            self.assertIn(token, reject, 'rejected delegate must preserve actual stack objects/preferences')

    def test_original_phone_only_root_row_routes_to_real_bottom_page(self):
        data = json.loads(read('Preferences/Resources/SettingsReference.json'))
        rows = [r for s in data['rootSections'] for r in s['rows']]
        self.assertEqual([r['id'] for r in rows if r['available']],
                         ['homescreenOptions', 'bottomOptions'])
        bottom = next(r for r in rows if r['id'] == 'bottomOptions')
        self.assertEqual((bottom['kind'], bottom['title'], bottom['phoneOnly'], bottom['destination']),
                         ('link', '底部上划手势', True, 'bottom'))
        text = read('Preferences/SettingsController.swift')
        gate = body(text, 'private func rowIsAvailable(')
        branch = body(gate, 'if row.id == "bottomOptions"')
        for token in ['row.kind == "link"', 'row.destination == "bottom"',
                      'row.phoneOnly == true', 'UIDevice.current.userInterfaceIdiom == .phone']:
            self.assertIn(token, branch)
        select = body(text, 'func tableView(_ tableView: UITableView, didSelectRowAt')
        self.assertIn('case "bottom" where page == .root && row.id == "bottomOptions":', select)
        bottom_route = select.split('case "bottom" where', 1)[1].split('case "actions"', 1)[0]
        for token in ['tableView === view', 'tableView.cellForRow(at: indexPath)',
                      'cell.accessibilityIdentifier == row.id', 'cell.isUserInteractionEnabled',
                      'pushViewController(BottomGestureSettingsController(), animated: true)']:
            self.assertIn(token, bottom_route)
        self.assertEqual(select.count('BottomGestureSettingsController()'), 1)

    def test_tweak_compiles_the_same_shared_bottom_models(self):
        match = re.search(r'^TapLock_FILES = (.+)$', read('Makefile'), re.M)
        assert match is not None, 'Missing tweak target source list'
        paths = match[1].split()
        self.assertEqual(len(paths), len(set(paths)))
        for path in ['Shared/BottomGesturePreferences.swift', 'Shared/BottomGestureGeometry.swift']:
            self.assertIn(path, paths)
        self.assertNotIn('Shared/Applications.swift', paths)

    def test_preferences_compiles_new_controller_with_the_same_shared_store(self):
        makefile = read('Preferences/Makefile')
        match = re.search(r'^TapLockPrefs_FILES = (.+)$', makefile, re.M)
        assert match is not None, 'Missing Preferences target source list'
        paths = match[1].split()
        self.assertEqual(len(paths), len(set(paths)))
        self.assertEqual(set(paths), {'../Shared/Preferences.swift', '../Shared/Applications.swift',
                                     '../Sources/PrivateAPI.swift', 'ApplicationIcons.swift',
                                     'SettingsController.swift', '../Shared/BottomGesturePreferences.swift',
                                     'BottomGestureSettingsController.swift'})
        self.assertIn('TapLockPrefs_RESOURCE_DIRS = Resources', makefile)

    def test_reference_uikit_preserves_old_root_gate_and_checks_new_available_entry(self):
        harness = read('Tests/ReferenceSettingsApp.swift')
        roundtrip = body(harness, 'private func runRoundTrip(')
        expected = '''        #if REFERENCE_SETTINGS_CURRENT
        checkSections(rootTable, key: "rootSections", nav: nav, allowed: ["homescreenOptions", "bottomOptions"])
        #else
        checkSections(rootTable, key: "rootSections", nav: nav, allowed: ["homescreenOptions"])
        #endif'''
        self.assertIn(expected, roundtrip)

    def test_real_reference_runner_arguments_close_current_preferences_graph(self):
        runner = read('ci/settings-construction-smoke.sh').split('run_reference_case() {', 1)[1]
        selection = '    local compile_flag=' + runner.split('    local compile_flag=', 1)[1].split('    python3 - ', 1)[0]
        command = '    xcrun swiftc' + runner.split('    xcrun swiftc', 1)[1].split('\n    codesign', 1)[0]
        # Run the actual shell expansion with an argv recorder, NOT a compiler.
        shell = '''set -euo pipefail
xcrun() { "$PYTHON" -B -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"; }
probe() {
    local label="$1" source_root=/source ROOT=/root app=/app TARGET=target SDK=sdk WORK=/work
''' + selection + command + '''
}
probe system-mute-baseline
probe reference-fixed
'''
        import os
        p = subprocess.run(['/bin/bash', '-c', shell], capture_output=True, text=True,
                           env={**os.environ, 'PYTHON': sys.executable}, timeout=10)
        self.assertEqual(p.returncode, 0, p.stderr)
        commands = [json.loads(line) for line in p.stdout.splitlines()]
        self.assertEqual(len(commands), 2)
        actual = [[a.removeprefix('/source/') for a in args if a.startswith('/source/') and a.endswith('.swift')]
                  for args in commands]
        old = ['Shared/Preferences.swift', 'Shared/Applications.swift', 'Sources/PrivateAPI.swift',
               'Preferences/ApplicationIcons.swift', 'Preferences/SettingsController.swift']
        self.assertEqual(actual[0], old)
        self.assertEqual(actual[1], old + ['Shared/BottomGesturePreferences.swift',
                                         'Preferences/BottomGestureSettingsController.swift'])
        self.assertEqual([a for a in commands[0] if a.startswith('-D')], ['-DSYSTEM_MUTE_BASELINE'])
        self.assertEqual([a for a in commands[1] if a.startswith('-D')], ['-DREFERENCE_SETTINGS_CURRENT'])

    def test_current_reference_fixture_copies_both_reachable_page_resources(self):
        runner = read('ci/settings-construction-smoke.sh').split('run_reference_case() {', 1)[1]
        self.assertIn('cp "$ROOT/Preferences/Resources/SettingsReference.json" "$app/SettingsReference.json"', runner)
        self.assertIn('''    if [ "$label" = reference-fixed ]; then
        cp "$ROOT/Preferences/Resources/BottomGestureReference.json" "$app/BottomGestureReference.json"
    fi''', runner)

    def test_package_gate_requires_exact_bottom_resource_and_closed_control_structure(self):
        module = runpy.run_path(str(ROOT / 'ci/verify_package.py'))
        verify = module.get('verify_bottom_gesture_reference_resource')
        self.assertTrue(callable(verify), 'Missing extracted bottom resource package gate')
        assert callable(verify)
        original = (ROOT / 'Preferences/Resources/BottomGestureReference.json').read_bytes()
        result = verify(original, original)
        assert isinstance(result, dict), 'Package resource verifier must return its checked counts'
        self.assertEqual((result['root_controls'], result['numeric_controls'], result['side_gestures']), (17, 12, 6))
        for payload in [b'', original + b'\n', original.replace(b'"defaultNumber": 30', b'"defaultNumber": 31', 1)]:
            with self.subTest(payload=payload[:30]), self.assertRaises(ValueError):
                verify(payload, original)
        for change in ['schema', 'section-order', 'hidden-condition', 'numeric-type', 'missing-gesture',
                       'side-hidden-condition', 'link-hidden-condition', 'switch-hidden-condition', 'default-on']:
            data = json.loads(original)
            if change == 'schema': data['schemaVersion'] = True
            elif change == 'section-order': data['sections'][0], data['sections'][1] = data['sections'][1], data['sections'][0]
            elif change == 'hidden-condition': data['sections'][5]['rows'][0]['visibleWhen'] = 'Enabled'
            elif change == 'numeric-type': data['sections'][3]['rows'][0]['defaultNumber'] = True
            elif change == 'missing-gesture': data['sides']['left']['sections'].pop()
            elif change == 'side-hidden-condition': data['sides']['left']['sections'][0]['rows'][0]['visibleWhen'] = 'notADeclaredBooleanKey'
            elif change == 'link-hidden-condition': data['sections'][0]['rows'][0]['visibleWhen'] = 'bottomUpOnLandscapeEnabled'
            elif change == 'switch-hidden-condition': data['sections'][2]['rows'][0]['visibleWhen'] = 'bottomUpOnLandscapeEnabled'
            else: data['sides']['right']['sections'][0]['rows'][0]['defaultBoolean'] = True
            malformed = json.dumps(data, ensure_ascii=False).encode()
            with self.subTest(change=change), self.assertRaises(ValueError):
                verify(malformed, malformed)
        package_body = read('ci/verify_package.py')
        self.assertIn('Library/PreferenceBundles/TapLockPrefs.bundle/BottomGestureReference.json', package_body)
        self.assertIn('verify_bottom_gesture_reference_resource((dest / required[6]).read_bytes()', package_body)
        self.assertIn('"bottom_gesture_reference_resource": bottom_reference', package_body)


if __name__ == '__main__':
    unittest.main()
