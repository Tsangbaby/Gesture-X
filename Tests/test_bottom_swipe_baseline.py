"""Bottom outer byte inverse; Python contracts, not Swift/device proof."""
import copy
import hashlib
import importlib
import importlib.util
import inspect
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '470f00764d17f597286b93eb7a5c0c56654f4a9a'
FROZEN_MAP_SHA = '83e1e56ff8ec3f5eb945e20c02f341d00666e0e4eb62009cbecd6692575f31e4'
IMMUTABLE_MAP_SHA = '8339fc1b137b839acfd9dd2755d7865766584c462de66275be08bc79310c52a5'
HUNKS_SHA = 'c4513e8893f662a25c6d833634b6f05429fe7316c58f729af4effccf9ab272ca'
HUNK_COUNTS = {'Makefile': 1, 'Preferences/Makefile': 1,
               'Preferences/Resources/SettingsReference.json': 1,
               'Preferences/SettingsController.swift': 2, 'Sources/NativeHook.swift': 1}


def byte_mutants(text, edits):
    mutants = [('unrelated', text + '\n// unrelated drift\n'),
               ('noise', '// unrelated header\n' + text),
               ('deleted', text[:-1]),
               ('duplicate-file', text + text),
               ('byte', ('X' if text[0] != 'X' else 'Y') + text[1:]),
               ('crlf', text.replace('\n', '\r\n')),
               ('mixed-crlf', text.replace('\n', '\r\n', 1))]
    for i, edit in enumerate(edits):
        for label, replacement in (('missing', ''), ('duplicate', edit['after'] * 2),
                                   ('shifted', ' ' + edit['after']),
                                   ('renamed', edit['after'].replace('bottom', 'renamed', 1)
                                    if 'bottom' in edit['after'] else edit['after'].replace('Bottom', 'Renamed', 1))):
            if replacement != edit['after']:
                mutants.append((f'{label}-{i}', text.replace(edit['after'], replacement, 1)))
    if len(edits) > 1:
        mutants.append(('hunk-order', text.replace(edits[0]['after'], '__BOTTOM_SWAP__', 1)
                        .replace(edits[-1]['after'], edits[0]['after'], 1)
                        .replace('__BOTTOM_SWAP__', edits[-1]['after'], 1)))
    lines = text.splitlines(keepends=True)
    lines[0], lines[1] = lines[1], lines[0]
    mutants.append(('line-order', ''.join(lines)))
    return mutants


class BottomSwipeBaselineContracts(unittest.TestCase):
    def helper(self):
        self.assertIsNotNone(importlib.util.find_spec('bottom_swipe_baseline'),
                             'Missing exact bottom-swipe outer inverse')
        return importlib.import_module('bottom_swipe_baseline')

    def test_legacy_disabled_rows_reader_is_one_explicit_historical_boundary(self):
        raw = (ROOT / 'Tests/test_reference_settings_rendering.py').read_bytes().decode('utf-8')
        before = '    def test_disabled_rows_have_ui_and_direct_delivery_guards(self):\n        source = SOURCE.read_text()\n'
        after = "    def test_disabled_rows_have_ui_and_direct_delivery_guards(self):\n        from bottom_swipe_baseline import system_mute_source\n        source = system_mute_source('Preferences/SettingsController.swift')\n"
        self.assertEqual(raw.count(after), 1, 'Missing precise historical reader boundary')
        self.assertEqual(raw.count('from bottom_swipe_baseline import system_mute_source'), 1)
        restored = raw.replace(after, before, 1)
        self.assertEqual(hashlib.sha256(restored.encode('utf-8')).hexdigest(),
                         'd653ae43a60619f0eb3857887273acd800405aef6ab599785d89f0d0df16a3e4',
                         'Legacy rendering assertions or other readers changed')

    def test_restores_accepted_system_mute_stage(self):
        h = self.helper()
        self.assertEqual(h.FIXTURE['baseline'], BASELINE)
        self.assertEqual(len(h.FIXTURE['frozen']), 28)
        for path, frozen in h.FIXTURE['frozen'].items():
            with self.subTest(path=path):
                self.assertEqual(h.digest(h.system_mute_source(path)), frozen)

    def test_manifest_and_historical_inputs_are_closed_and_byte_frozen(self):
        h = self.helper()
        import system_mute_baseline as old
        self.assertEqual(h.FROZEN_PATHS, old.FROZEN_PATHS | old.ADDED_PATHS)
        self.assertEqual(h.HUNK_COUNTS, HUNK_COUNTS)
        self.assertEqual({p: len(v) for p, v in h.FIXTURE['hunks'].items()}, HUNK_COUNTS)
        for key, sha in (('frozen', FROZEN_MAP_SHA), ('immutable', IMMUTABLE_MAP_SHA), ('hunks', HUNKS_SHA)):
            self.assertEqual(hashlib.sha256(json.dumps(h.FIXTURE[key], sort_keys=True).encode()).hexdigest(), sha)
        self.assertEqual(len(h.FIXTURE['immutable']), 23)
        expected = {'Tests/' + p.name for p in (ROOT / 'Tests').iterdir()
                    if not p.name.startswith(('test_', 'bottom_swipe_')) and
                    (p.name.endswith(('_baseline.py', '_baseline.json')) or 'oracle' in p.name)}
        self.assertEqual(set(h.FIXTURE['immutable']), expected)
        for path, sha in h.FIXTURE['immutable'].items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), sha)

    def test_all_source_mutations_reject_without_history(self):
        h = self.helper()
        originals = {p: (ROOT / p).read_bytes() for p in h.FROZEN_PATHS}
        with mock.patch('subprocess.run', side_effect=AssertionError('no history')), \
             mock.patch('subprocess.check_output', side_effect=AssertionError('no history')):
            for path, raw in originals.items():
                text = raw.decode('utf-8')
                self.assertEqual(h.digest(h.invert_bottom_swipe(path, text)), h.FIXTURE['frozen'][path])
                for kind, mutant in byte_mutants(text, h.FIXTURE['hunks'].get(path, [])):
                    self.assertNotEqual(mutant, text, (path, kind))
                    with self.subTest(path=path, mutation=kind), self.assertRaises(AssertionError):
                        h.invert_bottom_swipe(path, mutant)
        for path, raw in originals.items():
            self.assertEqual((ROOT / path).read_bytes(), raw)

    def test_manifest_schema_hunks_and_digest_mutations_reject(self):
        h = self.helper()
        mutants = []
        for key in h.FIXTURE:
            item = copy.deepcopy(h.FIXTURE); del item[key]
            mutants.append(('missing-' + key, item))
        item = copy.deepcopy(h.FIXTURE); item['unexpected'] = True
        mutants.append(('extra', item))
        item = copy.deepcopy(h.FIXTURE); item['baseline'] = '0' * 40
        mutants.append(('baseline', item))
        for key in ('frozen', 'immutable', 'hunks'):
            for operation in ('missing', 'extra', 'type', 'digest'):
                item = copy.deepcopy(h.FIXTURE)
                if operation == 'missing': del item[key][next(iter(item[key]))]
                elif operation == 'extra': item[key]['Unexpected.swift'] = 'not authorized'
                elif operation == 'type': item[key] = []
                else: item[key][next(iter(item[key]))] = '0' * 64
                mutants.append((key + '-' + operation, item))
        for path in HUNK_COUNTS:
            for value in ([], {}, None):
                item = copy.deepcopy(h.FIXTURE); item['hunks'][path] = value
                mutants.append((path + '-shape', item))
            for key, values in {'count': [True, False, 0, 2, '1', 1.0, None],
                                'before': [None, [], 1, '', 'no newline'],
                                'after': [None, [], 1, '', 'no newline']}.items():
                for value in values:
                    item = copy.deepcopy(h.FIXTURE); item['hunks'][path][0][key] = value
                    mutants.append((path + '-' + key, item))
            for operation in ('extra-key', 'missing-key', 'identity', 'forged-before', 'forged-after', 'crlf'):
                item = copy.deepcopy(h.FIXTURE); edit = item['hunks'][path][0]
                if operation == 'extra-key': edit['extra'] = True
                elif operation == 'missing-key': del edit['count']
                elif operation == 'identity': edit['before'] = edit['after']
                elif operation == 'crlf': edit['after'] = edit['after'].replace('\n', '\r\n')
                else: edit[operation.removeprefix('forged-')] += '// unauthorized anchor\n'
                mutants.append((path + '-' + operation, item))
        item = copy.deepcopy(h.FIXTURE)
        item['hunks']['Preferences/SettingsController.swift'].reverse()
        mutants.append(('hunk-order', item))
        for kind, fixture in mutants:
            with self.subTest(mutation=kind), mock.patch.object(h, 'FIXTURE', fixture):
                with self.assertRaises(AssertionError): h.system_mute_source('Shared/Preferences.swift')

    def test_hunks_are_unique_complete_lines_ordered_and_forward_replay_exact(self):
        h = self.helper()
        for path, edits in h.FIXTURE['hunks'].items():
            current = (ROOT / path).read_bytes().decode('utf-8')
            before = h.invert_bottom_swipe(path, current)
            for side, text in (('before', before), ('after', current)):
                end = -1
                for edit in edits:
                    self.assertEqual(edit['count'], 1)
                    self.assertTrue(edit[side].endswith('\n'))
                    starts = h._line_starts(text, edit[side])
                    self.assertEqual(len(starts), 1)
                    self.assertGreaterEqual(starts[0], end)
                    end = starts[0] + len(edit[side].splitlines(keepends=True))
            for edit in reversed(edits): before = before.replace(edit['before'], edit['after'], 1)
            self.assertEqual(before, current)

    def test_composition_restores_each_stage_before_calling_old_inverse(self):
        h = self.helper()
        import system_mute_baseline as mute
        import flashlight_baseline as light
        import media_tracks_baseline as tracks
        import media_play_pause_baseline as play
        import settings_layout_baseline as layout
        signature = inspect.signature(h.accepted_layout_source)
        for key in ('media_play_pause', 'media_tracks', 'flashlight'):
            self.assertIs(signature.parameters[key].default, False)
            self.assertEqual(signature.parameters[key].kind, inspect.Parameter.KEYWORD_ONLY)
        for path in h.FROZEN_PATHS:
            stage = h.system_mute_source(path)
            self.assertEqual(h.digest(stage), h.FIXTURE['frozen'][path])
            pre_mute = mute.invert_system_mute(path, stage)
            self.assertEqual(h.accepted_source(path), pre_mute)
            pre_light = light.invert_flashlight(path, pre_mute)
            self.assertEqual(h.accepted_flashlight_source(path), pre_light)
            pre_tracks = tracks.invert_media_tracks(path, pre_light)
            self.assertEqual(h.accepted_media_tracks_source(path), pre_tracks)
            for use_light, use_tracks, use_play in ((False, False, False), (True, False, False),
                                                   (True, True, False), (True, True, True)):
                text = pre_mute
                if use_light: text = light.invert_flashlight(path, text)
                if use_tracks: text = tracks.invert_media_tracks(path, text)
                if use_play: text = play.invert_media_play_pause(path, text)
                try:
                    expected = layout.invert_settings_layout(path, text)
                except AssertionError:
                    with self.assertRaises(AssertionError):
                        h.accepted_layout_source(path, flashlight=use_light, media_tracks=use_tracks, media_play_pause=use_play)
                else:
                    self.assertEqual(h.accepted_layout_source(path, flashlight=use_light, media_tracks=use_tracks, media_play_pause=use_play), expected)
            # Mutate only after a verified stage restoration, then call the OLD
            # inverse directly. A bottom rejection cannot satisfy these probes.
            for inverse, text in ((mute.invert_system_mute, stage),
                                  (light.invert_flashlight, pre_mute),
                                  (tracks.invert_media_tracks, pre_light)):
                self.assertIsInstance(inverse(path, text), str)
                protected = path in {'invert_system_mute': mute.FROZEN_PATHS | mute.ADDED_PATHS,
                                     'invert_flashlight': set(light.FIXTURE['frozen']) | { 'Sources/FlashlightAction.swift' },
                                     'invert_media_tracks': set(tracks.FIXTURE['frozen'])}[inverse.__name__]
                if protected:
                    with self.assertRaises(AssertionError): inverse(path, text + '// stage-local drift\n')

    def test_reader_preserves_raw_bytes_rejects_crlf_and_missing_inputs(self):
        h = self.helper(); path = 'Preferences/SettingsController.swift'
        raw = (ROOT / path).read_bytes()
        with mock.patch.object(h, 'ROOT') as root:
            file = root.__truediv__.return_value; file.is_file.return_value = True
            file.read_bytes.return_value = raw
            with mock.patch.object(h, 'invert_bottom_swipe', wraps=h.invert_bottom_swipe) as inverse:
                self.assertEqual(h.digest(h.system_mute_source(path)), h.FIXTURE['frozen'][path])
            inverse.assert_called_once_with(path, raw.decode('utf-8'))
            file.read_bytes.assert_called_once_with(); file.read_text.assert_not_called()
            file.read_bytes.return_value = raw.replace(b'\n', b'\r\n')
            with self.assertRaises(AssertionError): h.system_mute_source(path)
            file.is_file.return_value = False
            with self.assertRaisesRegex(AssertionError, 'Missing implementation'): h.system_mute_source(path)

    def test_unknown_paths_are_identity_not_aliases(self):
        h = self.helper(); text = 'unrelated\r\n'
        for path in ('Unexpected.swift', '../Makefile', '/Makefile', 'Makefile.bak',
                     'Preferences/RenamedSettingsController.swift'):
            self.assertIs(h.invert_bottom_swipe(path, text), text)

    def test_old_helpers_stay_strict_and_do_not_implicitly_strip_bottom(self):
        h = self.helper()
        import system_mute_baseline as old
        for path in HUNK_COUNTS:
            raw = (ROOT / path).read_bytes().decode('utf-8')
            old.invert_system_mute(path, h.system_mute_source(path))
            with self.assertRaises(AssertionError): old.invert_system_mute(path, raw)
            with self.assertRaises(AssertionError): old.accepted_source(path)

    def test_candidate_only_empty_path_without_git_runs_all_other_bottom_contracts(self):
        with tempfile.TemporaryDirectory(prefix='bottom-candidate-only-') as directory:
            candidate = Path(directory) / 'candidate'
            shutil.copytree(ROOT, candidate, ignore=shutil.ignore_patterns('.git', '__pycache__', '.theos', '.build'))
            self.assertFalse((candidate / '.git').exists())
            excluded = self._testMethodName
            code = ("import unittest; import test_bottom_swipe_baseline as t; "
                    "names=[n for n in unittest.defaultTestLoader.getTestCaseNames(t.BottomSwipeBaselineContracts) if n != " + repr(excluded) + "]; "
                    "assert len(names)==10; "
                    "r=unittest.TextTestRunner(verbosity=1).run(unittest.TestSuite(t.BottomSwipeBaselineContracts(n) for n in names)); "
                    "assert r.wasSuccessful() and not r.skipped")
            result = subprocess.run([str(Path(sys.executable).resolve()), '-B', '-c', code],
                                    cwd=candidate / 'Tests',
                                    env={**os.environ, 'PATH': '', 'PYTHONPATH': str(candidate / 'Tests'), 'PYTHONDONTWRITEBYTECODE': '1'},
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Ran 10 tests', result.stderr)
            self.assertNotIn('skipped', result.stderr.lower())


if __name__ == '__main__':
    unittest.main()
