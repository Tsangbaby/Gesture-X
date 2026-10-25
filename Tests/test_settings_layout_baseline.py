"""Exact-byte authorization tests, not Swift/UIKit execution proof.

Historical-input inventory:
* test_app_switcher, test_screenshot, test_notification_center,
  test_control_center, test_open_app, test_settings_hierarchy and
  test_settings_construction read accepted_source at the outermost inverse or
  mutation boundary; every older inverse and mutation remains stage-local.
* test_source and feature/native-app UI token checks opt in explicitly with
  source(..., settings_layout=True), before comment filtering.
* Active metadata/version assertions and generic current-source safety scans
  remain live-source checks. test_reference_settings preserves its original
  eight-action catalog through an explicit flashlight-only outer read;
  test_flashlight/test_flashlight_ui cover the current nine-action candidate.
"""
import hashlib
import importlib
import importlib.util
import unittest
from unittest import mock


class SettingsLayoutInverseTests(unittest.TestCase):
    def layout(self):
        self.assertIsNotNone(importlib.util.find_spec('settings_layout_baseline'),
                             'Missing exact settings-layout inverse')
        return importlib.import_module('settings_layout_baseline')

    def fixture(self):
        before = {
            'Preferences/SettingsController.swift': 'accepted 0.1.8 UI\n',
            'control': 'Version: 0.1.8\n',
            'Preferences/Resources/Info.plist': '<version>0.1.8</version>\n',
        }
        candidate = {
            'Preferences/SettingsController.swift': 'rewritten 0.1.9 UI\nrow A\nrow B\n',
            'control': 'Version: 0.1.9\n',
            'Preferences/Resources/Info.plist': '<version>0.1.9</version>\n',
        }
        fixture = {
            'baseline': 'f3a2e138fa9ac93d250645e9c66226b074d429ee',
            'frozen': {path: hashlib.sha256(text.encode()).hexdigest()
                       for path, text in before.items()},
            'before_text': before,
            'candidate_sha256': {path: hashlib.sha256(text.encode()).hexdigest()
                                 for path, text in candidate.items()},
        }
        return fixture, candidate

    def test_exact_candidate_restores_only_frozen_before_text(self):
        layout = self.layout()
        fixture, candidate = self.fixture()
        with mock.patch.object(layout, 'FIXTURE', fixture):
            for path, text in candidate.items():
                with self.subTest(path=path):
                    self.assertEqual(layout.invert_settings_layout(path, text),
                                     fixture['before_text'][path])

    def test_rejects_missing_duplicate_reordered_and_unrelated_candidate_bytes(self):
        layout = self.layout()
        fixture, candidate = self.fixture()
        with mock.patch.object(layout, 'FIXTURE', fixture):
            for path, text in candidate.items():
                mutations = (text[:-1], text + text, text + '// unrelated drift\n',
                             text.replace('0.1.9', '0.1.8'),
                             fixture['before_text'][path])
                if path.endswith('.swift'):
                    mutations += (text.replace('row A\nrow B', 'row B\nrow A'),)
                for mutation in mutations:
                    with self.subTest(path=path, mutation=mutation), self.assertRaises(AssertionError):
                        layout.invert_settings_layout(path, mutation)

    def test_before_text_must_match_frozen_sha256_for_each_authorized_path(self):
        layout = self.layout()
        for path in self.fixture()[1]:
            fixture, candidate = self.fixture()
            fixture['before_text'][path] += '// hidden drift\n'
            with self.subTest(path=path), mock.patch.object(layout, 'FIXTURE', fixture):
                with self.assertRaises(AssertionError):
                    layout.invert_settings_layout(path, candidate[path])

    def test_manifest_cannot_change_baseline_or_expand_authorization(self):
        layout = self.layout()
        path = 'Preferences/SettingsController.swift'
        for mutation in ('baseline', 'extra-before', 'extra-candidate', 'missing-before',
                         'missing-candidate', 'missing-frozen'):
            fixture, candidate = self.fixture()
            if mutation == 'baseline':
                fixture['baseline'] = '0' * 40
            elif mutation.startswith('extra-'):
                key = 'before_text' if mutation == 'extra-before' else 'candidate_sha256'
                fixture[key]['Sources/HomeDoubleTap.swift'] = 'not authorized'
            else:
                key = {'missing-before': 'before_text', 'missing-candidate': 'candidate_sha256',
                       'missing-frozen': 'frozen'}[mutation]
                del fixture[key][path]
            with self.subTest(mutation=mutation), mock.patch.object(layout, 'FIXTURE', fixture):
                with self.assertRaises(AssertionError):
                    layout.invert_settings_layout(path, candidate[path])

    def test_unauthorized_paths_are_identity_even_when_manifest_mentions_them(self):
        layout = self.layout()
        fixture, _ = self.fixture()
        paths = ('Sources/HomeDoubleTap.swift', 'Preferences/NewSettingsController.swift',
                 'SettingsController.swift', '../Preferences/SettingsController.swift',
                 '/Preferences/SettingsController.swift', 'Preferences/SettingsController.swift.bak')
        with mock.patch.object(layout, 'FIXTURE', fixture):
            for path in paths:
                fixture['before_text'][path] = 'must never substitute'
                text = 'unrelated source drift\r\n'
                with self.subTest(path=path):
                    self.assertIs(layout.invert_settings_layout(path, text), text)

    def test_accepted_source_reads_current_bytes_and_inverts_exactly_once(self):
        layout = self.layout()
        self.assertTrue(callable(getattr(layout, 'accepted_source', None)),
                        'Missing explicit current-source inverse entry point')
        fixture, candidate = self.fixture()
        path = 'Preferences/SettingsController.swift'
        with mock.patch.object(layout, 'FIXTURE', fixture), mock.patch.object(layout, 'ROOT') as root:
            file = root.__truediv__.return_value
            file.is_file.return_value = True
            file.read_bytes.return_value = candidate[path].encode()
            with mock.patch.object(layout, 'invert_settings_layout', wraps=layout.invert_settings_layout) as inverse:
                self.assertEqual(layout.accepted_source(path), fixture['before_text'][path])
            inverse.assert_called_once_with(path, candidate[path])
            file.read_bytes.assert_called_once_with()
            file.read_text.assert_not_called()

    def test_accepted_source_rejects_crlf_and_missing_current_file(self):
        layout = self.layout()
        fixture, candidate = self.fixture()
        path = 'Preferences/SettingsController.swift'
        with mock.patch.object(layout, 'FIXTURE', fixture), mock.patch.object(layout, 'ROOT') as root:
            file = root.__truediv__.return_value
            file.is_file.return_value = True
            file.read_bytes.return_value = candidate[path].replace('\n', '\r\n').encode()
            with self.assertRaises(AssertionError):
                layout.accepted_source(path)
            file.is_file.return_value = False
            with self.assertRaisesRegex(AssertionError, 'Missing implementation'):
                layout.accepted_source(path)

    def test_source_default_reads_current_ui_without_any_inverse(self):
        from test_source import source
        with mock.patch('test_source.ROOT') as root, mock.patch('test_source.accepted_source', create=True) as inverse:
            file = root.__truediv__.return_value
            file.is_file.return_value = True
            file.read_text.return_value = 'current UI // discard comment\n"keep // string"\n'
            self.assertEqual(source('Preferences/SettingsController.swift'),
                             'current UI \n"keep // string"\n')
            inverse.assert_not_called()

    def test_source_settings_layout_opt_in_is_explicit_and_precedes_comment_filter(self):
        import inspect
        from test_source import source
        self.assertIn('settings_layout', inspect.signature(source).parameters,
                      'Historical UI needs an explicit opt-in, not a global source replacement')
        with mock.patch('test_source.accepted_source', create=True,
                        return_value='accepted UI // discard comment\n"keep // string"\n') as inverse:
            self.assertEqual(source('Preferences/SettingsController.swift', settings_layout=True),
                             'accepted UI \n"keep // string"\n')
            inverse.assert_called_once_with('Preferences/SettingsController.swift', media_play_pause=True, media_tracks=True, flashlight=True)

    def test_historical_helpers_require_explicit_outermost_layout_inverse(self):
        from app_switcher_baseline import invert_app_switcher
        from screenshot_baseline import invert_screenshot
        from notification_center_baseline import invert_notification_center
        from control_center_baseline import invert_control_center
        from open_app_baseline import invert_open_app
        from settings_hierarchy_baseline import FIXTURE as hierarchy, invert_settings_hierarchy
        layout = self.layout()
        fixture, candidate = self.fixture()
        path = 'Preferences/SettingsController.swift'
        # The real frozen 0.1.8 text, with an independently exact mock rewrite,
        # proves the old helpers are untouched and cannot silently undo 0.1.9.
        fixture['before_text'] = dict(layout.FIXTURE['before_text'])
        fixture['frozen'] = dict(layout.FIXTURE['frozen'])
        for inverse in (invert_app_switcher, invert_screenshot, invert_notification_center,
                        invert_control_center, invert_open_app):
            with self.subTest(inverse=inverse.__name__), self.assertRaises(AssertionError):
                inverse(path, candidate[path])
        with self.assertRaises(AssertionError):
            invert_settings_hierarchy(candidate[path])
        with mock.patch.object(layout, 'FIXTURE', fixture):
            accepted = layout.invert_settings_layout(path, candidate[path])
            restored = invert_settings_hierarchy(invert_open_app(
                path, accepted, control_center=True, notification_center=True,
                screenshot=True, app_switcher=True))
            self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), hierarchy['baseline_sha256'])
            with self.assertRaises(AssertionError):
                layout.invert_settings_layout(path, accepted)


class SettingsLayoutCurrentSourceContracts(unittest.TestCase):
    """Integration checks read real current bytes, never an old UI masquerade."""

    def test_manifest_scope_and_all_before_bytes_match_frozen_018(self):
        from settings_layout_baseline import FIXTURE
        paths = {'Preferences/SettingsController.swift', 'control', 'Preferences/Resources/Info.plist'}
        self.assertEqual(FIXTURE['baseline'], 'f3a2e138fa9ac93d250645e9c66226b074d429ee')
        self.assertEqual(len(FIXTURE['frozen']), 24)
        self.assertEqual(set(FIXTURE['before_text']), paths)
        self.assertEqual(set(FIXTURE['candidate_sha256']), paths)
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256(FIXTURE['before_text'][path].encode()).hexdigest(),
                                 FIXTURE['frozen'][path])
                self.assertNotEqual(FIXTURE['candidate_sha256'][path], FIXTURE['frozen'][path],
                                    'Finalize the real 0.1.9 candidate; do not authorize the placeholder')

    def test_explicit_inverse_restores_all_24_device_accepted_018_files(self):
        from settings_layout_baseline import FIXTURE
        from system_mute_baseline import accepted_layout_source as accepted_source
        for path, digest in FIXTURE['frozen'].items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256(accepted_source(path, media_play_pause=True, media_tracks=True, flashlight=True).encode()).hexdigest(), digest)

    def test_any_current_authorized_byte_drift_is_rejected(self):
        from settings_layout_baseline import FIXTURE, ROOT, invert_settings_layout
        from media_play_pause_baseline import invert_media_play_pause
        for path in FIXTURE['before_text']:
            from system_mute_baseline import accepted_media_tracks_source as track_accepted_source
            text = invert_media_play_pause(path, track_accepted_source(path))
            # Validate before entering assertRaises so stale manifest/current
            # source mismatch cannot masquerade as a successful negative test.
            self.assertEqual(invert_settings_layout(path, text), FIXTURE['before_text'][path])
            for kind, mutation in (('missing', text[:-1]), ('duplicate', text + text),
                                   ('unrelated', text + '\n// unrelated drift\n'),
                                   ('line endings', text.replace('\n', '\r\n'))):
                with self.subTest(path=path, mutation=kind), self.assertRaises(AssertionError):
                    invert_settings_layout(path, mutation)

    def test_old_helpers_still_reject_unrestored_current_ui_by_default(self):
        from settings_layout_baseline import ROOT, invert_settings_layout
        from media_play_pause_baseline import invert_media_play_pause
        from app_switcher_baseline import invert_app_switcher
        from screenshot_baseline import invert_screenshot
        from notification_center_baseline import invert_notification_center
        from control_center_baseline import invert_control_center
        from open_app_baseline import invert_open_app
        from settings_hierarchy_baseline import invert_settings_hierarchy
        path = 'Preferences/SettingsController.swift'
        from system_mute_baseline import accepted_media_tracks_source as track_accepted_source
        text = invert_media_play_pause(path, track_accepted_source(path))
        invert_settings_layout(path, text)
        for inverse in (invert_app_switcher, invert_screenshot, invert_notification_center,
                        invert_control_center, invert_open_app):
            with self.subTest(inverse=inverse.__name__), self.assertRaises(AssertionError):
                inverse(path, text)
        with self.assertRaises(AssertionError):
            invert_settings_hierarchy(text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
