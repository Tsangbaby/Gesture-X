"""Exact ordered flashlight inverse to the accepted predecessor bytes.

No Git history is needed at runtime. The added provider has no predecessor:
verify its own candidate digest and preserve its bytes, never fabricate a file.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_bytes().decode('utf-8'))

FROZEN_PATHS = frozenset({
    'Interfaces/TapLockNativeRuntime/NativeRuntime.h',
    'Interfaces/TapLockNativeRuntime/module.modulemap',
    'Interfaces/TapLockPreferencesHost/PSViewController.h',
    'Interfaces/TapLockPreferencesHost/module.modulemap',
    'Makefile',
    'Preferences/ApplicationIcons.swift',
    'Preferences/Makefile',
    'Preferences/Resources/Info.plist',
    'Preferences/Resources/SettingsReference.json',
    'Preferences/SettingsController.swift',
    'Shared/Applications.swift',
    'Shared/Preferences.swift',
    'Sources/AppAction.swift',
    'Sources/AppSwitcherAction.swift',
    'Sources/Bootstrap.swift',
    'Sources/ControlCenterAction.swift',
    'Sources/HomeDoubleTap.swift',
    'Sources/LockAction.swift',
    'Sources/MediaPlayPauseAction.swift',
    'Sources/NativeHook.swift',
    'Sources/NotificationCenterAction.swift',
    'Sources/PrivateAPI.swift',
    'Sources/ScreenshotAction.swift',
    'TapLock.plist',
    'control',
    'layout/Library/PreferenceLoader/Preferences/TapLock.plist',
})
AUTHORIZED_PATHS = frozenset({
    'Makefile',
    'Preferences/Resources/Info.plist',
    'Preferences/Resources/SettingsReference.json',
    'Preferences/SettingsController.swift',
    'Shared/Preferences.swift',
    'Sources/HomeDoubleTap.swift',
    'control',
})
ADDED_PATHS = frozenset({'Sources/FlashlightAction.swift'})
HUNK_COUNTS = {
    'Makefile': 1,
    'Preferences/Resources/Info.plist': 1,
    'Preferences/Resources/SettingsReference.json': 1,
    'Preferences/SettingsController.swift': 2,
    'Shared/Preferences.swift': 3,
    'Sources/HomeDoubleTap.swift': 1,
    'control': 1,
}
FROZEN_MAP_SHA256 = '360fba1a23059c1a0e3fc05540c3c0ede5a6140cfbbe9d965f3b2472dd8cc0e3'



def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def _line_starts(text, anchor):
    """Find complete-line sequences, never indented substring matches."""
    lines = text.splitlines(keepends=True)
    needle = anchor.splitlines(keepends=True)
    return [index for index in range(len(lines) - len(needle) + 1)
            if lines[index:index + len(needle)] == needle]


def _validate_fixture():
    assert FIXTURE.get('baseline') == '925df18141606b75f71c77ddd998ad2baa237efe', 'Unexpected flashlight baseline'
    for key, paths in (('frozen', FROZEN_PATHS), ('hunks', AUTHORIZED_PATHS),
                       ('candidate_added_sha256', ADDED_PATHS)):
        assert isinstance(FIXTURE.get(key), dict) and set(FIXTURE[key]) == paths, ('Unexpected flashlight authorization', key)
    assert hashlib.sha256(json.dumps(FIXTURE['frozen'], sort_keys=True).encode()).hexdigest() == FROZEN_MAP_SHA256, 'Changed inherited flashlight hashes'
    for path, count in HUNK_COUNTS.items():
        edits = FIXTURE['hunks'][path]
        assert isinstance(edits, list) and len(edits) == count, ('Unexpected flashlight hunk count', path)
        for edit in edits:
            assert isinstance(edit, dict) and set(edit) == {'before', 'after', 'count'}, ('Malformed flashlight hunk', path)
            assert type(edit['count']) is int and edit['count'] == 1, ('Non-unit flashlight hunk', path)
            assert all(isinstance(edit[key], str) and edit[key].endswith('\n')
                       for key in ('before', 'after')), ('Incomplete flashlight hunk lines', path)
            assert edit['before'] != edit['after'], ('Identity flashlight hunk', path)


def invert_flashlight(relative, text):
    """Undo exactly this candidate; unrelated/unlisted paths remain identity."""
    if relative not in FROZEN_PATHS | ADDED_PATHS:
        return text
    _validate_fixture()
    if relative in ADDED_PATHS:
        assert digest(text) == FIXTURE['candidate_added_sha256'][relative], ('Added flashlight provider byte drift', relative)
        return text
    edits = FIXTURE['hunks'].get(relative, [])
    end = -1
    for edit in edits:
        assert edit['count'] == 1, ('Non-unit flashlight hunk', relative)
        assert edit['before'] and edit['after'] and edit['before'] != edit['after']
        starts = _line_starts(text, edit['after'])
        assert len(starts) == 1, ('Missing or duplicate flashlight hunk', relative)
        start = starts[0]
        assert start >= end, ('Out-of-order flashlight hunk', relative)
        end = start + len(edit['after'].splitlines(keepends=True))
    lines = text.splitlines(keepends=True)
    for edit in reversed(edits):
        start = _line_starts(''.join(lines), edit['after'])[0]
        width = len(edit['after'].splitlines(keepends=True))
        lines[start:start + width] = edit['before'].splitlines(keepends=True)
    restored = ''.join(lines)
    assert digest(restored) == FIXTURE['frozen'][relative], ('Unrelated flashlight-candidate byte drift', relative)
    return restored


def accepted_source(relative):
    """Read candidate bytes, then explicitly reconstruct the predecessor."""
    path = ROOT / relative
    assert path.is_file(), f'Missing implementation: {relative}'
    return invert_flashlight(relative, path.read_bytes().decode('utf-8'))


def accepted_media_tracks_source(relative):
    """Explicit current -> accepted predecessor -> pre-track source read."""
    from media_tracks_baseline import invert_media_tracks
    return invert_media_tracks(relative, accepted_source(relative))
