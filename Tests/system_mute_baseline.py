"""Exact system-mute inverse; all historical compositions are explicit opt-ins."""
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
    'Makefile', 'Preferences/ApplicationIcons.swift', 'Preferences/Makefile',
    'Preferences/Resources/Info.plist', 'Preferences/Resources/SettingsReference.json',
    'Preferences/SettingsController.swift', 'Shared/Applications.swift', 'Shared/Preferences.swift',
    'Sources/AppAction.swift', 'Sources/AppSwitcherAction.swift', 'Sources/Bootstrap.swift',
    'Sources/ControlCenterAction.swift', 'Sources/FlashlightAction.swift', 'Sources/HomeDoubleTap.swift',
    'Sources/LockAction.swift', 'Sources/MediaPlayPauseAction.swift', 'Sources/NativeHook.swift',
    'Sources/NotificationCenterAction.swift', 'Sources/PrivateAPI.swift', 'Sources/ScreenshotAction.swift',
    'TapLock.plist', 'control', 'layout/Library/PreferenceLoader/Preferences/TapLock.plist',
})
HUNK_COUNTS = {
    'Makefile': 1, 'Preferences/Resources/Info.plist': 1,
    'Preferences/Resources/SettingsReference.json': 1, 'Preferences/SettingsController.swift': 2,
    'Shared/Preferences.swift': 3, 'Sources/HomeDoubleTap.swift': 1, 'control': 1,
}
AUTHORIZED_PATHS = frozenset(HUNK_COUNTS)
ADDED_PATHS = frozenset({'Sources/SystemMuteAction.swift'})
FROZEN_MAP_SHA256 = '94412089e3957967dddc98c7a94d7d996be5432c1725e5ea5cc41486eb7a67f5'
ADDED_SHA256 = {'Sources/SystemMuteAction.swift': 'b10b9b5499a7bfa31ba698efb6e13a20d1220002ad78507213bde49223f75460'}


def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def _line_starts(text, anchor):
    lines, needle = text.splitlines(keepends=True), anchor.splitlines(keepends=True)
    return [i for i in range(len(lines) - len(needle) + 1) if lines[i:i + len(needle)] == needle]


def _validate_fixture():
    assert isinstance(FIXTURE, dict) and set(FIXTURE) == {'baseline', 'frozen', 'hunks', 'candidate_added_sha256'}, 'Malformed system-mute schema'
    assert FIXTURE['baseline'] == '0cc50fbd3e82c336f89394f80cb298aa150a1c70', 'Unexpected system-mute baseline'
    for key, paths in (('frozen', FROZEN_PATHS), ('hunks', AUTHORIZED_PATHS), ('candidate_added_sha256', ADDED_PATHS)):
        assert isinstance(FIXTURE[key], dict) and set(FIXTURE[key]) == paths, ('Unexpected system-mute authorization', key)
    assert hashlib.sha256(json.dumps(FIXTURE['frozen'], sort_keys=True).encode()).hexdigest() == FROZEN_MAP_SHA256, 'Changed inherited system-mute hashes'
    assert FIXTURE['candidate_added_sha256'] == ADDED_SHA256, 'Changed added system-mute hash'
    for path, count in HUNK_COUNTS.items():
        edits = FIXTURE['hunks'][path]
        assert isinstance(edits, list) and len(edits) == count, ('Unexpected system-mute hunk count', path)
        for edit in edits:
            assert isinstance(edit, dict) and set(edit) == {'before', 'after', 'count'}, ('Malformed system-mute hunk', path)
            assert type(edit['count']) is int and edit['count'] == 1, ('Non-unit system-mute hunk', path)
            assert all(isinstance(edit[key], str) and edit[key] and edit[key].endswith('\n') for key in ('before', 'after')), ('Incomplete system-mute hunk lines', path)
            assert edit['before'] != edit['after'], ('Identity system-mute hunk', path)


def invert_system_mute(relative, text):
    """Restore only the frozen predecessor; preserve added provider as itself."""
    if relative not in FROZEN_PATHS | ADDED_PATHS:
        return text
    _validate_fixture()
    if relative in ADDED_PATHS:
        assert digest(text) == ADDED_SHA256[relative], ('Added system-mute provider byte drift', relative)
        return text
    edits = FIXTURE['hunks'].get(relative, [])
    end = -1
    for edit in edits:
        starts = _line_starts(text, edit['after'])
        assert len(starts) == 1, ('Missing or duplicate system-mute hunk', relative)
        assert starts[0] >= end, ('Out-of-order system-mute hunk', relative)
        end = starts[0] + len(edit['after'].splitlines(keepends=True))
    lines = text.splitlines(keepends=True)
    for edit in reversed(edits):
        start = _line_starts(''.join(lines), edit['after'])[0]
        lines[start:start + len(edit['after'].splitlines(keepends=True))] = edit['before'].splitlines(keepends=True)
    restored = ''.join(lines)
    assert digest(restored) == FIXTURE['frozen'][relative], ('Unrelated system-mute candidate byte drift', relative)
    return restored


def accepted_source(relative):
    """Read current bytes and restore only the accepted pre-system-mute stage."""
    path = ROOT / relative
    assert path.is_file(), f'Missing implementation: {relative}'
    return invert_system_mute(relative, path.read_bytes().decode('utf-8'))


def accepted_flashlight_source(relative):
    from flashlight_baseline import invert_flashlight
    return invert_flashlight(relative, accepted_source(relative))


def accepted_media_tracks_source(relative):
    from media_tracks_baseline import invert_media_tracks
    return invert_media_tracks(relative, accepted_flashlight_source(relative))


def accepted_layout_source(relative, *, media_play_pause=False, media_tracks=False, flashlight=False):
    """Explicit current -> mute -> optional flashlight/tracks/playPause -> layout."""
    from settings_layout_baseline import invert_settings_layout
    text = accepted_source(relative)
    if flashlight:
        from flashlight_baseline import invert_flashlight
        text = invert_flashlight(relative, text)
    if media_tracks:
        from media_tracks_baseline import invert_media_tracks
        text = invert_media_tracks(relative, text)
    if media_play_pause:
        from media_play_pause_baseline import invert_media_play_pause
        text = invert_media_play_pause(relative, text)
    return invert_settings_layout(relative, text)
