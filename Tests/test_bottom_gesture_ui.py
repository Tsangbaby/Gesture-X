"""Source wiring contracts only; UIKit behavior runs on Apple via the smoke app."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / 'Preferences/BottomGestureSettingsController.swift'

# Accepted resource identity frozen before review repair, not re-derived from
# the resource under test or from the production validation constants.
ACCEPTED_CATALOG_SHA256 = '7a4ce768ab3e3ea4e659f5d2c352d05f038813adbaf030608d087b0dbedf2638'
ACCEPTED_BASIC_IDS = (
    'HI_CLIPBOARD', 'HI_FULLSCREEN_OCR', 'HI_FULLSCREEN_TRANSLATE',
    'SHOW_COPYVAULT', 'SHOW_COPYVAULT_HISTORY', 'SHOW_COPYVAULT_ARCHIVE',
    'SYSTEM_SCREENSHOT', 'SYSTEM_SCREENSHOT_COPYONLY', 'SYSTEM_SCREENSHOT_ANDEDIT',
    'SYSTEM_CONTROLCENTER', 'SYSTEM_COVER', 'SYSTEM_SPOTLIGHT',
    'SYSTEM_RECORDSCREEN', 'SYSTEM_RECORDSCREEN_WITHMIC', 'SYSTEM_LOCKSCREEN',
    'TOGGLE_VPN', 'TOGGLE_FLASHLIGHT', 'SYSTEM_REACHABILITY', 'ROTATION_LOCK',
    'PLAYPAUSE_MEDIA', 'PREVIOUS_MEDIA', 'NEXT_MEDIA', 'APP_LIBRARY',
    'KILL_BACKGROUND', 'REOPEN_CURRENT_APP', 'RESPRING_ALL', 'RESPRING_SB',
    'REBOOT_USERSPACE', 'REBOOT', 'SHUTDOWN', 'SAFEMODE', 'REBUILD_UICACHE',
    'SYSTEM_MUTE', 'VOLUME_MUTE', 'SYSTEM_LOWPOWER', 'SYSTEM_LOCATION',
    'SYSTEM_DARKMODE', 'SYSTEM_SIRI', 'SYSTEM_APAY', 'SYSTEM_ACCESSIBILITY',
    'SYSTEM_SWITCHER', 'SYSTEM_HOME', 'SNAPPER_INSTANT', 'SNAPPER_COMMON',
    'SNAPPER_FREEZE', 'SNAPPER_HISTORY', 'SNAPPER_CLOSE_ALL', 'SNAPPER_OPEN_LAST',
    'SHOW_KAYOKO', 'SHOW_COPYLOG', 'AUDIORECORDERXS_MEMO', 'AUDIORECORDERXS_UI',
    'REVERIE_SLEEP', 'SHOW_CARDCULATOR', 'TROLLRECORD_START', 'TROLLRECORD_STOP',
    'TROLLRECORD_TOGGLE', 'ZETSU_WINDOW_MODE', 'PULLOVER_MINIVIEW', 'SVP_MINIVIEW',
    'FV_MINIVIEW', 'SVP_ARCMENU', 'FV_LEFT_ARCMENU', 'FV_RIGHT_ARCMENU',
    'WECHAT_SCAN', 'WECHAT_QRCODE', 'ALIPAY_SCAN', 'ALIPAY_QRCODE',
)
ACCEPTED_SUPPORTED_KINDS = {
    'SYSTEM_SCREENSHOT': 'screenshot', 'SYSTEM_CONTROLCENTER': 'controlCenter',
    'SYSTEM_COVER': 'notificationCenter', 'SYSTEM_LOCKSCREEN': 'lock',
    'TOGGLE_FLASHLIGHT': 'flashlight', 'PLAYPAUSE_MEDIA': 'playPause',
    'PREVIOUS_MEDIA': 'previousTrack', 'NEXT_MEDIA': 'nextTrack',
    'SYSTEM_MUTE': 'systemMute', 'SYSTEM_SWITCHER': 'appSwitcher',
}


def production_source():
    text = CONTROLLER.read_text()
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda match: match[0] if match[0].startswith('"') else '', text, flags=re.S)


def swift_body(source, anchor):
    """Extract a scoped Swift body, ignoring braces in strings/comments."""
    source = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                    lambda match: match[0] if match[0].startswith('"') else '', source, flags=re.S)
    start = source.find(anchor)
    if start < 0:
        raise AssertionError('missing Swift scope: ' + anchor)
    start = source.find('{', start + len(anchor))
    if start < 0:
        raise AssertionError('missing Swift body: ' + anchor)
    depth = 1
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|[{}]', source[start + 1:]):
        if token[0] == '{':
            depth += 1
        elif token[0] == '}':
            depth -= 1
        if depth == 0:
            return source[start + 1:start + 1 + token.start()]
    raise AssertionError('unclosed Swift body: ' + anchor)


def assert_visibility_contract(case, source):
    validation = swift_body(swift_body(source, 'private struct BottomUIReference:'), 'var isValid: Bool')
    sides = swift_body(validation, 'for (section, id) in zip(side.sections, ids)')
    case.assertRegex(sides, r'section\.rows\.allSatisfy\(\{[^}]*\$0\.visibleWhen == nil[^}]*\}\)',
                     'every side switch/action/flow row must reject every visibility condition')
    links = swift_body(validation, 'for (index, side) in ["left", "right"].enumerated()')
    case.assertIn('rows[index].visibleWhen == nil', links,
                  'root links must reject every visibility condition')


def assert_catalog_contract(case, source):
    catalog = swift_body(source, 'private struct BottomActionCatalog:')
    validation = swift_body(catalog, 'var isValid: Bool')
    case.assertIn('let expectedKind = Self.supportedKindsByID[item.id]', validation,
                  'catalog must bind the action kind to its exact original ID')
    case.assertIn('basicActions.map({ $0.id }) == Self.acceptedBasicIDs', validation,
                  'missing exact original ID order predicate')
    mapping_guard = swift_body(validation, 'basicActions.allSatisfy(')
    for predicate in ('item.available == (expectedKind != nil)', 'item.actionKind == expectedKind'):
        case.assertIn(predicate, mapping_guard, 'missing exact per-ID availability/kind predicate')
    ids = re.search(r'static let acceptedBasicIDs\s*=\s*\[(.*?)\]', catalog, re.S)
    if ids is None:
        raise AssertionError('missing independently frozen production ID order')
    case.assertEqual(tuple(re.findall(r'"([^"]+)"', ids[1])), ACCEPTED_BASIC_IDS,
                     'production ID order differs from accepted original IDs')
    mapping = re.search(r'static let supportedKindsByID:\s*\[String:\s*String\]\s*=\s*\[(.*?)\]', catalog, re.S)
    if mapping is None:
        raise AssertionError('missing exact supported ID -> kind production map')
    pairs = re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', mapping[1])
    case.assertEqual(len(pairs), len(ACCEPTED_SUPPORTED_KINDS), 'production map must contain exactly accepted IDs')
    case.assertEqual(dict(pairs), ACCEPTED_SUPPORTED_KINDS, 'production map differs from exact original ID kinds')


class BottomGestureUISourceTests(unittest.TestCase):
    def test_uikit_suite_runs_from_runloop_timer_not_one_main_queue_block(self):
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        launch = swift_body(harness, 'func application(')
        self.assertIn('perform(#selector(run), with: nil, afterDelay: 0)', launch)
        self.assertIn('@objc private func run()', harness)
        self.assertNotIn('DispatchQueue.main.async { self.run() }', launch)
        run = swift_body(harness, 'private func run()')
        self.assertIn('testMainQueueProgress()', run)

    def test_uikit_host_measures_main_queue_progress_before_interactions(self):
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        probe = swift_body(harness, 'private func testMainQueueProgress()')
        for token in ('DispatchQueue.main.async', 'progressed = true', 'settle()', 'require(progressed,'):
            self.assertIn(token, probe)
        run = swift_body(harness, 'private func run()')
        self.assertLess(run.index('testMainQueueProgress()'), run.index('testRootEntryAdmission()'))
        entry = swift_body(harness, 'private func entry(')
        for token in ('numeric editor did not present: id=', 'input=', 'control=', 'presented=', 'assertions='):
            self.assertIn(token, entry)

    def test_table_owner_failure_reports_actual_identity_without_relaxing_admission(self):
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        helper = swift_body(harness, 'private func table(')
        self.assertIn('table.delegate === controller && ownsDataSource', helper)
        for token in ('wrong table owner: controller=', 'delegate=', 'dataSource=', 'assertions='):
            self.assertIn(token, helper)

    def test_table_controller_ownership_uses_public_owned_table_not_adapter_identity(self):
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        helper = swift_body(harness, 'private func table(')
        self.assertIn('let ownsDataSource = table.dataSource === controller ||', helper)
        self.assertIn('(controller as? UITableViewController)?.tableView === table', helper)
        self.assertIn('table.dataSource != nil', helper)
        self.assertIn('table.delegate === controller && ownsDataSource', helper)
        self.assertNotIn('_UIFilteredDataSource', helper,
                         'do not grant admission by guessing a private adapter class name')
        self.assertNotIn('table.dataSource = controller', helper,
                         'a test must not rewrite production datasource ownership')

    def test_discovery_and_foreign_fixture_cannot_reparent_production_cached_controls(self):
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        discovery = swift_body(harness, 'private func find(')
        self.assertNotIn('source.tableView(', discovery,
                         'discovery must not ask the datasource for shadow cells with live cached controls')
        for token in ('for path in paths(table)', 'table.scrollToRow(at: path',
                      'table.layoutIfNeeded()', 'table.cellForRow(at: path)'):
            self.assertIn(token, discovery)
        admission = swift_body(harness, 'private func testRootEntryAdmission()')
        self.assertIn('foreignTable.dataSource = foreignSource', admission)
        self.assertIn('foreignTable.delegate = originalRoot', admission)
        self.assertNotIn('foreignTable.dataSource = originalRoot', admission)
        for token in ('cachedRootToggle.isDescendant(of: originalSwitchCell)',
                      'cachedRootToggle.superview === originalSwitchOwner'):
            self.assertIn(token, admission, 'missing executed UIKit control-ownership regression')
        foreign = swift_body(harness, 'private final class BottomRootForeignDataSource:')
        self.assertIn('UITableViewCell(style:', foreign)
        self.assertNotIn('UISwitch(', foreign)

    def test_bottom_simulators_use_sdk_matching_runtime_not_highest_foreign_runtime(self):
        for runner, override in [('bottom-gesture-settings', 'BOTTOM_UI_RUNTIME'),
                                 ('bottom-gesture-native', 'BOTTOM_NATIVE_RUNTIME'),
                                 ('bottom-actions', 'BOTTOM_ACTIONS_RUNTIME')]:
            script = (ROOT / ('ci/' + runner + '-smoke.sh')).read_text()
            with self.subTest(runner=runner):
                selector = re.search(r'RUNTIME="\$\(python3[^\n]*<<\x27PY\x27\n(.*?)\nPY\n\)"', script, re.S)
                self.assertIsNotNone(selector)
                assert selector is not None
                runtime = lambda version: {'name': 'iOS ' + version, 'version': version,
                                          'identifier': 'test.runtime.' + version, 'isAvailable': True}
                with tempfile.TemporaryDirectory() as work:
                    path = Path(work) / 'runtimes.json'
                    path.write_text(json.dumps({'runtimes': [runtime('18.4'), runtime('18.5'), runtime('26.0')]}))
                    env = os.environ.copy()
                    env.pop(override, None)
                    def select(requested=None):
                        current = env.copy()
                        if requested is not None:
                            current[override] = requested
                        return subprocess.run([sys.executable, '-', str(path), '18.5'],
                                              input=selector[1], text=True, capture_output=True, env=current)
                    result = select()
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), 'test.runtime.18.5')
                    self.assertEqual(select('test.runtime.18.4').stdout.strip(), 'test.runtime.18.4')
                    self.assertNotEqual(select('test.runtime.26.0').returncode, 0)
                    path.write_text(json.dumps({'runtimes': [runtime('26.0')]}))
                    self.assertNotEqual(select().returncode, 0)
                self.assertIn('SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"', script)
                self.assertIn('"$WORK/runtimes.json" "$SDK_VERSION"', script)

    def test_cloud_diagnosis_runs_bottom_ui_first_without_changing_any_gate(self):
        workflow = json.loads((ROOT / '.github/workflows/build.yml').read_bytes())
        steps = workflow['jobs']['roothide']['steps']
        names = [step['name'] for step in steps]
        self.assertLess(names.index('Source and real Swift runtime tests'),
                        names.index('Bottom gesture model and UIKit gates'))
        self.assertLess(names.index('Bottom gesture model and UIKit gates'),
                        names.index('Settings constructor regression (iOS Simulator fixture)'))
        self.assertLess(names.index('Settings constructor regression (iOS Simulator fixture)'),
                        names.index('Install packaging tools and pinned RootHide Theos'))
        # Freeze all existing commands, assertions, timeouts, permissions, refs,
        # job conditions and toolchain pins; only the step ordering may differ.
        steps.sort(key=lambda step: step['name'])
        canonical = json.dumps(workflow, sort_keys=True, separators=(',', ':')).encode()
        self.assertEqual(hashlib.sha256(canonical).hexdigest(),
                         'b32b28a264ad8049570d4a52092445d31cc23733674b3ca6005673b651f0a02c')

    def test_uikit_incomplete_execution_retains_host_only_discriminating_evidence(self):
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        script = (ROOT / 'ci/bottom-gesture-settings-smoke.sh').read_text()
        self.assertIn('BOTTOM_UIKIT_CHECKPOINT:', harness)
        checkpoint = swift_body(harness, 'private func checkpoint(')
        self.assertIn('fflush(stdout)', checkpoint)
        run = swift_body(harness, 'private func run()')
        for name in ('testRootEntryAdmission', 'testRootEntry', 'testNumbers',
                     'testDisabledAndStaleNumericEntry', 'testSixIndependentLists',
                     'testDisabledAndSearch', 'testAppSnapshot', 'testIllegalVisibilityResources',
                     'testBasicIdentityResources', 'testInvalidResources', 'testSaveFailure',
                     'testNarrowDynamicType'):
            self.assertIn('checkpoint("before ' + name + '")\n        ' + name + '()', run)
        self.assertIn('BOTTOM_UIKIT_TRANSPORT_STATUS:', script)
        self.assertIn('BottomGestureSettings crash report:', script)
        self.assertIn("['sample', pid, '1', '1', '-file'", script)
        self.assertIn('timeout=240', script)
        self.assertIn('status = 124', script)
        self.assertIn('bash "$0" --verify-output "$STATUS" "$WORK/console.txt"', script)
        for relative in ('Makefile', 'Preferences/Makefile'):
            self.assertNotIn('Tests/', (ROOT / relative).read_text())

    def test_catalog_freezes_exact_id_order_and_action_identity(self):
        source = production_source()
        assert_catalog_contract(self, source)
        mutations = [
            ('ID order guard removed', 'basicActions.map({ $0.id }) == Self.acceptedBasicIDs,', ''),
            ('ID order swapped', '"HI_CLIPBOARD", "HI_FULLSCREEN_OCR"', '"HI_FULLSCREEN_OCR", "HI_CLIPBOARD"'),
            ('unavailable alias', '"SYSTEM_LOCKSCREEN": "lock"', '"HI_CLIPBOARD": "lock"'),
            ('supported kind alias', '"SYSTEM_LOCKSCREEN": "lock"', '"SYSTEM_LOCKSCREEN": "screenshot"'),
            ('availability predicate removed', 'item.available == (expectedKind != nil) &&', ''),
            ('kind predicate removed', 'item.actionKind == expectedKind &&', ''),
        ]
        for label, before, after in mutations:
            with self.subTest(mutant=label):
                self.assertEqual(source.count(before), 1)
                with self.assertRaisesRegex(AssertionError, r'exact|original'):
                    assert_catalog_contract(self, source.replace(before, after, 1))
        payload = (ROOT / 'Preferences/Resources/SettingsReference.json').read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(), ACCEPTED_CATALOG_SHA256)
        rows = json.loads(payload)['basicActions']
        self.assertEqual(tuple(row['id'] for row in rows), ACCEPTED_BASIC_IDS)
        for row in rows:
            expected = ACCEPTED_SUPPORTED_KINDS.get(row['id'])
            self.assertIs(row['available'], expected is not None)
            self.assertEqual(row['actionKind'], expected)
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        for token in ('testBasicIdentityResources()', 'availability-alias', 'supported-kind-swap',
                      'id-order-swap', 'expectedAction', 'actions == beforeActions + [expectedAction]'):
            self.assertIn(token, harness, 'missing real UIKit identity regression: ' + token)

    def test_side_and_root_links_cannot_be_conditionally_hidden(self):
        source = production_source()
        assert_visibility_contract(self, source)
        for guard in ('rows[index].visibleWhen == nil,', '$0.visibleWhen == nil && '):
            with self.subTest(removed_guard=guard):
                self.assertEqual(source.count(guard), 1)
                mutant = source.replace(guard, '', 1)
                with self.assertRaisesRegex(AssertionError, r'root links|every side'):
                    assert_visibility_contract(self, mutant)
        harness = (ROOT / 'Tests/BottomGestureSettingsApp.swift').read_text()
        for token in ('testIllegalVisibilityResources()', 'notADeclaredBooleanKey',
                      'for sideName in ["left", "right"]', 'for sectionIndex in 0..<3',
                      'for rowIndex in 0..<3', 'bottomUpOnLandscapeEnabled',
                      'assertRejectedResource', 'writes == 0', '!item.isEnabled',
                      '!cell.isUserInteractionEnabled'):
            self.assertIn(token, harness, 'missing real UIKit malformed-resource coverage: ' + token)

    def test_production_bottom_controller_exists(self):
        self.assertTrue(CONTROLLER.is_file(), 'missing production bottom Settings controller')
        source = production_source()
        self.assertIn('final class BottomGestureSettingsController: UITableViewController', source)
        self.assertIn('init()', source)

    def test_resource_driven_pages_and_fractional_save_wiring(self):
        source = production_source()
        for token in ('BottomGestureReference', 'SettingsReference', 'JSONDecoder()',
                      'snapshot.number(', 'snapshot.boolean(', 'snapshot.selection(',
                      'P.writeNumber', 'P.writeBoolean', 'P.writeEnabled', 'P.writeFlowEnabled',
                      'visibleWhen', 'isFinite', 'Double(text)', 'min(key.maxValue, max(key.minValue, value))',
                      '%.1f', '%.2f', 'NSLayoutConstraint.activate', 'adjustsFontForContentSizeCategory',
                      'tableView.cellForRow(at:', 'tableView.indexPath(for:', 'sender.isEnabled',
                      'reloadPersistedState', '保存失败', '配置资源不可用'):
            self.assertTrue(token in source, 'missing production wiring: ' + token)
        self.assertNotIn('key.title', source, 'UI labels must come from the original resource')
        self.assertNotIn('SettingsReference.load()', source, 'old private renderer must stay private')

    def test_ordered_action_editor_and_picker_are_save_only(self):
        source = production_source()
        for token in ('P.writeActions', 'commit editingStyle', 'moveRowAt sourceIndexPath',
                      'canMoveRowAt', 'override func setEditing', 'editingIndex', 'expectedActions', 'actions.remove(at:',
                      'actions.insert(', 'actions.append(', 'UISearchController',
                      'InstalledApplications.choices()', 'InstalledApplications.choice(identifier:',
                      'ApplicationIcons()', 'referenceSlot', 'basicActions.count == 68',
                      'supportedKinds', 'toggle.isEnabled = usable'):
            self.assertTrue(token in source, 'missing production wiring: ' + token)
        for forbidden in ('import TapLockPreferencesHost', 'ActionExecutor', 'performAction(',
                          'TapLockPreferences.writeAction', 'TapLockPreferences.writeEnabled',
                          'DoubleTapAction', 'dlopen(', 'dlsym('):
            self.assertNotIn(forbidden, source)

    def test_numeric_commit_and_stale_list_admission_are_production_seams(self):
        source = production_source()
        for token in ('editingDidEndOnExit', 'numberSubmitted',
                      'fresh.selection(id).actions != snapshot.selection(id).actions',
                      'alert?.textFields?.first === field',
                      'field.isEnabled, field.isUserInteractionEnabled',
                      'self.presentedViewController === alert'):
            self.assertTrue(token in source, 'missing production guard: ' + token)

    def test_production_fails_closed_without_crash_or_repeated_app_lookups(self):
        source = production_source()
        self.assertNotIn('fatalError(', source)
        self.assertIn('applicationNames[identifier]', source)
        self.assertIn('missingApplicationNames.contains(identifier)', source)

    def test_actual_runner_terminal_guard_truth_table(self):
        runner = ROOT / 'ci/bottom-gesture-settings-smoke.sh'
        cases = [
            (0, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=1\n', True),
            (0, 'launch transport success\n', False),
            (0, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=0\n', False),
            (0, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=-2\n', False),
            (0, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=abc\n', False),
            (0, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=01\n', False),
            (0, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=2\n' * 2, False),
            (0, 'BOTTOM_GESTURE_UIKIT_FAIL: failed\nBOTTOM_GESTURE_UIKIT_PASS: assertions=3\n', False),
            (0, 'WRONG_BOTTOM_GESTURE_UIKIT_PASS: assertions=1\n', False),
            (0, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=3 trailing\n', False),
            (1, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=1\n', False),
            (124, 'BOTTOM_GESTURE_UIKIT_PASS: assertions=1\n', False),
        ]
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as work:
            log = Path(work) / 'console.txt'
            for status, output, accepted in cases:
                with self.subTest(status=status, output=output):
                    log.write_text(output)
                    result = subprocess.run(['bash', str(runner), '--verify-output', str(status), str(log)],
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)

    def test_runner_embedded_python_is_syntactically_valid(self):
        runner = (ROOT / 'ci/bottom-gesture-settings-smoke.sh').read_text()
        blocks = re.findall(r"<<'PY'\n(.*?)\nPY", runner, re.S)
        self.assertGreater(len(blocks), 0)
        for index, block in enumerate(blocks):
            compile(block, f'bottom-runner-heredoc-{index}', 'exec')

    @unittest.skipIf(sys.platform == 'darwin', 'unsupported-host rejection only applies outside Apple')
    def test_actual_runner_refuses_non_apple_host_without_skipping(self):
        result = subprocess.run(['bash', str(ROOT / 'ci/bottom-gesture-settings-smoke.sh')],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 69)
        self.assertIn('UNSUPPORTED_HOST:', result.stderr)
        self.assertIn('no tests executed.', result.stderr)
        self.assertNotIn('BOTTOM_GESTURE_UIKIT_PASS:', result.stdout)

    def test_uikit_harness_and_runner_exist_with_complete_production_graph(self):
        app = ROOT / 'Tests/BottomGestureSettingsApp.swift'
        runner = ROOT / 'ci/bottom-gesture-settings-smoke.sh'
        self.assertTrue(app.is_file(), 'missing executable UIKit harness')
        self.assertTrue(runner.is_file(), 'missing Apple-host runner')
        harness = app.read_text()
        script = runner.read_text()
        for token in ('@main', 'TapLockSettingsController', 'BottomGestureSettingsController',
                      'cellForRow(at:', 'sendActions(for:', 'didSelectRowAt:',
                      'testNumbers', 'testSixIndependentLists', 'testInvalidResources',
                      'testAppSnapshot', 'testSaveFailure', 'BOTTOM_GESTURE_UIKIT_PASS: assertions=',
                      'item["image"] as? String == nil'):
            self.assertTrue(token in harness, 'missing UIKit coverage: ' + token)
        for path in ('Shared/Preferences.swift', 'Shared/Applications.swift',
                     'Shared/BottomGesturePreferences.swift', 'Sources/PrivateAPI.swift',
                     'Preferences/SettingsController.swift', 'Preferences/ApplicationIcons.swift',
                     'Preferences/BottomGestureSettingsController.swift',
                     'Tests/BottomGestureSettingsApp.swift', 'Tests/SettingsConstructionFixture.m'):
            self.assertTrue(path in script, 'missing compile input: ' + path)
        self.assertIn('--verify-output', script)
        self.assertIn('Darwin', script)
        self.assertNotIn('git fetch', script)


if __name__ == '__main__':
    unittest.main()
