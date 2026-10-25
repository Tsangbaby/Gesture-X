"""Bottom model SOURCE contracts; only the Darwin smoke executes Swift bodies.

No Python geometry/codec replica: behavioral assertions live in the Swift harness.
"""
import json
import os
import re
import tempfile
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFS = ROOT / 'Shared/BottomGesturePreferences.swift'
GEOMETRY = ROOT / 'Shared/BottomGestureGeometry.swift'
HARNESS = ROOT / 'Tests/BottomGestureModelTests.swift'
RUNNER = ROOT / 'ci/bottom-gesture-model-smoke.sh'
IDS = ['bottomLeftUp', 'bottomLeftUpExtra', 'bottomLeftUpExtraPlus',
       'bottomRightUp', 'bottomRightUpExtra', 'bottomRightUpExtraPlus']
DEFAULTS = {
    'bottomTriggerPosition': (0, 50, 30),
    'bottomTriggerRightPosition': (0, 50, 30),
    'bottomTriggerSensitivity': (0, 10, 7),
    'bottomTriggerArea': (0, 100, 18),
    'bottomTriggerExtraArea': (0, 100, 40),
    'bottomTriggerExtraPlusArea': (0, 100, 60),
    'bottomTriggerPositionLandscape': (0, 50, 20),
    'bottomTriggerRightPositionLandscape': (0, 50, 20),
    'bottomTriggerSensitivityLandscape': (0, 10, 7),
    'bottomTriggerAreaLandscape': (0, 100, 40),
    'bottomTriggerExtraAreaLandscape': (0, 100, 70),
    'bottomTriggerExtraPlusAreaLandscape': (0, 100, 100),
}


def read(path):
    return path.read_text() if path.exists() else ''


def code(text):
    """Strip nested Swift comments without losing strings or their contents."""
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
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|[{}]', text[start + 1:]):
        if token.group() == '{': depth += 1
        elif token.group() == '}': depth -= 1
        if depth == 0: return text[start + 1:start + 1 + token.start()]
    raise AssertionError('unbalanced implementing function: ' + signature)


class BottomGestureSourceTests(unittest.TestCase):
    def test_source_geometry_imports_coregraphics_equatable_overlay_on_darwin(self):
        # The cloud-Mac model target compiles without UIKit. Foundation alone
        # leaves CGSize without the CoreGraphics overlay's Equatable conformance.
        # This is a source guard; the actual Apple compiler remains the gate.
        text = code(read(GEOMETRY))
        self.assertRegex(text, r'(?m)^import CoreGraphics$',
                         'geometry requires the explicit CoreGraphics value-type overlay')
        self.assertIn('struct Bounds: Equatable', text)

    def test_source_preferences_contract_defaults_and_independent_keys(self):
        text = code(read(PREFS))
        self.assertIn('enum BottomGesturePreferences', text, 'SOURCE RED: preferences model missing')
        ids = body(text, 'enum GestureID: String, CaseIterable')
        self.assertEqual(re.findall(r'^\s*case (\w+)\s*$', ids, re.M), IDS)
        self.assertIn('rawValue + "Enabled"', ids)
        self.assertIn('rawValue + "FlowEnabled"', ids)
        numeric = body(text, 'enum NumericKey: String, CaseIterable')
        self.assertEqual(re.findall(r'^\s*case (\w+)\s*$', numeric, re.M), list(DEFAULTS))
        for key, (low, high, default) in DEFAULTS.items():
            self.assertIn(f'case .{key}: return ({low}, {high}, {default},', numeric)
        for name, value in [('ignoreEdgeProtect', 'true'), ('disableBottomWhenLocked', 'true'),
                            ('bottomUpOnLandscapeEnabled', 'false')]:
            self.assertIn(f'case .{name}: return {value}', text)
        self.assertNotIn('"DoubleTapAction"', text)
        self.assertNotIn('"Enabled" as CFString', text)


    def test_source_numeric_titles_match_original_bound_resource(self):
        data = json.loads((ROOT / 'Preferences/Resources/BottomGestureReference.json').read_text())
        rows = [row for section in data['sections'] for row in section['rows']
                if row['kind'] == 'slider']
        self.assertEqual(len(rows), 12)
        text = body(read(PREFS), 'private var metadata:')
        for row in rows:
            self.assertRegex(text, rf'case \.{row["key"]}: return \([^\n]+, "{re.escape(row["title"])}"\)',
                             'original title mismatch: ' + row['key'])


    def test_source_snapshot_requires_strict_types_and_ordered_codec(self):
        text = read(PREFS)
        snapshot = body(text, 'static func readSnapshot(using store: Store)')
        for token in ['store.synchronize()', 'store.copyValues(allKeys)',
                      'decodeNumber(value)', 'decodeBoolean(value)', 'decodeActions(value)',
                      'return .unavailable']:
            self.assertIn(token, snapshot, 'SOURCE RED: strict snapshot missing ' + token)
        boolean = body(text, 'static func decodeBoolean(')
        number = body(text, 'static func decodeNumber(')
        self.assertIn('CFBooleanGetTypeID()', boolean)
        self.assertIn('CFNumberGetTypeID()', number)
        self.assertIn('number.doubleValue.isFinite', number)
        decode = body(text, 'static func decodeActions(')
        self.assertIn('CFArrayGetTypeID()', decode)
        self.assertIn('CFDictionaryGetTypeID()', decode)
        self.assertIn('record.count == 2', decode)
        self.assertIn('record.count == 1', decode)
        self.assertIn('validBundleIdentifier(identifier)', decode)
        self.assertIn('result.append(action)', decode)
        self.assertNotIn('sorted', code(text))
        self.assertNotIn('readAction()', code(text))
        for kind in ['lock', 'controlCenter', 'notificationCenter', 'screenshot', 'appSwitcher',
                     'playPause', 'previousTrack', 'nextTrack', 'flashlight', 'systemMute']:
            self.assertIn(f'case "{kind}": action = .{kind}', decode)


    def test_source_writers_validate_then_rollback_before_notify(self):
        text = read(PREFS)
        for signature in [
            'static func writeNumber(_ value: Double, for key: NumericKey) -> Bool',
            'static func writeBoolean(_ value: Bool, for key: BooleanKey) -> Bool',
            'static func writeEnabled(_ value: Bool, for id: GestureID) -> Bool',
            'static func writeFlowEnabled(_ value: Bool, for id: GestureID) -> Bool',
            'static func writeActions(_ actions: [TapLockPreferences.Action], for id: GestureID) -> Bool',
        ]:
            self.assertIn('using: .live', body(text, signature), 'SOURCE RED: writer missing')
        persist = body(text, 'static func persist(')
        self.assertIn('guard store.synchronize() else', persist)
        self.assertEqual(persist.count('store.setValue('), 2)
        self.assertLess(persist.index('let previous = store.copyValue(key)'), persist.index('store.setValue(key, value)'))
        self.assertLess(persist.index('store.setValue(key, previous)'), persist.index('store.notify()'))
        self.assertRegex(persist, r'_ = store\.synchronize\(\)\s+return false')
        encode = body(text, 'static func encodeActions(')
        self.assertIn('case .unavailable: return nil', encode)
        self.assertIn('validBundleIdentifier(identifier)', encode)
        self.assertIn('records.append(record)', encode)
        self.assertNotIn('sorted', encode)


    def test_source_geometry_reference_space_bounds_and_displacement(self):
        text = code(read(GEOMETRY))
        self.assertIn('import Foundation', text, 'SOURCE RED: geometry model missing')
        self.assertNotIn('UIKit', text)
        bounds = body(text, 'static func bounds(')
        for token in ['referenceSize.width', 'referenceSize.height', '/ 100',
                      'bottomTriggerPositionLandscape', 'bottomTriggerRightPositionLandscape',
                      'bottomTriggerSensitivityLandscape', 'bottomTriggerExtraPlusAreaLandscape',
                      'orientationRaw == 4']:
            self.assertIn(token, bounds)
        side = body(text, 'static func side(')
        for token in ['origin.y > bounds.leftBoundary', 'origin.y < bounds.rightBoundary',
                      'origin.y < bounds.leftBoundary', 'origin.y > bounds.rightBoundary',
                      'origin.x < bounds.leftBoundary', 'origin.x > bounds.rightBoundary']:
            self.assertIn(token, side)
        displacement = body(text, 'static func displacement(')
        self.assertIn('case 3: value = current.x - origin.x', displacement)
        self.assertIn('case 4: value = origin.x - current.x', displacement)
        self.assertIn('case 1, 2: value = origin.y - current.y', displacement)
        self.assertIn('value.isFinite', displacement)
        for forbidden in ['readSnapshot(', 'CFPreferences', 'UserDefaults', 'FileManager', 'sorted(']:
            self.assertNotIn(forbidden, text)


    def test_source_tier_policy_and_classification_are_fail_closed(self):
        text = code(read(GEOMETRY))
        tier = body(text, 'static func tier(')
        for token in ['displacement.isFinite', 'displacement > bounds.h0',
                      'displacement < bounds.h3', 'displacement < bounds.h1',
                      'displacement < bounds.h2', 'return .extraPlus']:
            self.assertIn(token, tier)
        classify = body(text, 'static func classify(')
        for token in ['bounds(snapshot: snapshot', 'side(origin: origin',
                      'displacement(origin: origin', 'tier(displacement: displacement',
                      'snapshot.selection(id)', 'selection.enabled', '!selection.actions.isEmpty',
                      'case .unavailable: return false', 'validBundleIdentifier(identifier)']:
            self.assertIn(token, classify)
        bounds = body(text, 'static func bounds(')
        for token in ['snapshot.available', 'referenceSize.width.isFinite',
                      'referenceSize.height.isFinite', 'bottomUpOnLandscapeEnabled',
                      'value >= key.minValue', 'value <= key.maxValue',
                      'minimum < extra', 'extra < extraPlus', 'extraPlus < maximum']:
            self.assertIn(token, bounds)

    def test_source_runner_reports_failed_swift_output_before_exit(self):
        runner = read(RUNNER)
        self.assertIn('if ! "$WORK/model-tests" > "$WORK/result.txt" 2>&1; then', runner)
        self.assertIn('sys.stderr.write(pathlib.Path(sys.argv[1]).read_text())', runner)
        self.assertIn('exit 1', runner)

    def test_source_harness_declares_unedited_production_graph_and_calls_all_groups(self):
        runner = read(RUNNER)
        for path in ['Shared/Preferences.swift', 'Shared/BottomGesturePreferences.swift',
                     'Shared/BottomGestureGeometry.swift', 'Tests/BottomGestureModelTests.swift']:
            self.assertEqual(runner.count(f'"$ROOT/{path}"'), 1)
        self.assertIn('"$WORK/model-tests"', runner)
        self.assertIn('mktemp -d "$TMPDIR/', runner)
        self.assertNotIn('/tmp/', runner)
        harness = read(HARNESS)
        main = body(harness, 'static func main()')
        for name in ['defaults', 'strictSnapshot', 'persistence', 'geometryReferenceBounds',
                     'geometrySideAndDirection', 'geometryTierBoundaries',
                     'geometrySelectionFailClosed', 'independentSnapshots']:
            self.assertIn(name + '()', main)
            self.assertIn('require(', body(harness, 'static func ' + name + '('))
        for method in ['bounds', 'side', 'displacement', 'tier', 'gestureID', 'classify']:
            self.assertIn('G.' + method + '(', code(harness))
        self.assertNotIn('enum BottomGestureGeometry', code(harness))
        self.assertNotIn('enum BottomGesturePreferences', code(harness))

    def test_runner_syntax_and_missing_tool_refusal(self):
        subprocess.run(['bash', '-n', str(RUNNER)], check=True, capture_output=True, text=True)
        env = dict(os.environ, SWIFTC=str(ROOT / 'no-such-swiftc'))
        result = subprocess.run(['bash', str(RUNNER)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('swiftc is required; Swift was NOT executed', result.stderr)
        self.assertNotIn('BOTTOM_GESTURE_MODEL_PASS', result.stdout + result.stderr)
        if sys.platform != 'darwin':
            # An existing executable must still not bypass the Darwin API gate.
            result = subprocess.run(['bash', str(RUNNER)], env=dict(os.environ, SWIFTC=sys.executable),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('Darwin Foundation/CoreFoundation is required; Swift was NOT executed', result.stderr)
            self.assertNotIn('BOTTOM_GESTURE_MODEL_PASS', result.stdout + result.stderr)

    def test_runner_actual_marker_guard_rejects_false_completion(self):
        # Unit fixtures exercise only the runner's parser, never stand in for Swift.
        parser = read(RUNNER).split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
        fixtures = [
            ('BOTTOM_GESTURE_MODEL_PASS assertions=1\n', True),
            ('', False), ('OTHER_PASS assertions=3\n', False),
            ('BOTTOM_GESTURE_MODEL_PASS assertions=0\n', False),
            ('BOTTOM_GESTURE_MODEL_PASS assertions=-1\n', False),
            ('BOTTOM_GESTURE_MODEL_PASS assertions=abc\n', False),
            ('BOTTOM_GESTURE_MODEL_PASS assertions=2\n' * 2, False),
            ('BOTTOM_GESTURE_MODEL_FAIL: wrong\nBOTTOM_GESTURE_MODEL_PASS assertions=2\n', False),
        ]
        scratch = os.environ.get('TMPDIR')
        self.assertTrue(scratch and Path(scratch).is_dir(), 'TMPDIR scratch directory required')
        with tempfile.TemporaryDirectory(prefix='bottom-marker-guard-', dir=scratch) as work:
            target = Path(work) / 'result.txt'
            for output, accepted in fixtures:
                target.write_text(output)
                result = subprocess.run([sys.executable, '-B', '-c', parser, str(target)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, accepted, repr(output))


if __name__ == '__main__':
    unittest.main()
