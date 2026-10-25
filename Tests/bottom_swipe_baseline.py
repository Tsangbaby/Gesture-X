"""Exact bottom-only outer inverse for the authorized five-path snapshot.

Frozen from real 470f007 Git bytes, not runtime history. New feature readers
remain live; historical consumers explicitly opt into these stage boundaries.
Parent startup/build/metadata edits require a deliberate new hunk freeze.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_bytes().decode('utf-8'))
FROZEN_PATHS = frozenset(['Interfaces/TapLockNativeRuntime/NativeRuntime.h', 'Interfaces/TapLockNativeRuntime/module.modulemap', 'Interfaces/TapLockPreferencesHost/PSViewController.h', 'Interfaces/TapLockPreferencesHost/module.modulemap', 'Makefile', 'Preferences/ApplicationIcons.swift', 'Preferences/Makefile', 'Preferences/Resources/Info.plist', 'Preferences/Resources/SettingsReference.json', 'Preferences/SettingsController.swift', 'Shared/Applications.swift', 'Shared/Preferences.swift', 'Sources/AppAction.swift', 'Sources/AppSwitcherAction.swift', 'Sources/Bootstrap.swift', 'Sources/ControlCenterAction.swift', 'Sources/FlashlightAction.swift', 'Sources/HomeDoubleTap.swift', 'Sources/LockAction.swift', 'Sources/MediaPlayPauseAction.swift', 'Sources/NativeHook.swift', 'Sources/NotificationCenterAction.swift', 'Sources/PrivateAPI.swift', 'Sources/ScreenshotAction.swift', 'Sources/SystemMuteAction.swift', 'TapLock.plist', 'control', 'layout/Library/PreferenceLoader/Preferences/TapLock.plist'])
IMMUTABLE_PATHS = frozenset(['Tests/app_switcher_baseline.json', 'Tests/app_switcher_baseline.py', 'Tests/control_center_baseline.json', 'Tests/control_center_baseline.py', 'Tests/flashlight_baseline.json', 'Tests/flashlight_baseline.py', 'Tests/media_play_pause_baseline.json', 'Tests/media_play_pause_baseline.py', 'Tests/media_tracks_baseline.json', 'Tests/media_tracks_baseline.py', 'Tests/notification_center_baseline.json', 'Tests/notification_center_baseline.py', 'Tests/open_app_baseline.json', 'Tests/open_app_baseline.py', 'Tests/reference_settings_oracle.json', 'Tests/screenshot_baseline.json', 'Tests/screenshot_baseline.py', 'Tests/settings_hierarchy_baseline.json', 'Tests/settings_hierarchy_baseline.py', 'Tests/settings_layout_baseline.json', 'Tests/settings_layout_baseline.py', 'Tests/system_mute_baseline.json', 'Tests/system_mute_baseline.py'])
HUNK_COUNTS = {'Makefile': 1, 'Preferences/Makefile': 1,
               'Preferences/Resources/SettingsReference.json': 1,
               'Preferences/SettingsController.swift': 2, 'Sources/NativeHook.swift': 1}
AUTHORIZED_PATHS = frozenset(HUNK_COUNTS)
FROZEN_MAP_SHA256 = '83e1e56ff8ec3f5eb945e20c02f341d00666e0e4eb62009cbecd6692575f31e4'
IMMUTABLE_MAP_SHA256 = '8339fc1b137b839acfd9dd2755d7865766584c462de66275be08bc79310c52a5'
HUNKS_SHA256 = 'c4513e8893f662a25c6d833634b6f05429fe7316c58f729af4effccf9ab272ca'


def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def _line_starts(text, anchor):
    lines, needle = text.splitlines(keepends=True), anchor.splitlines(keepends=True)
    return [i for i in range(len(lines) - len(needle) + 1)
            if lines[i:i + len(needle)] == needle]


def _validate_fixture():
    assert isinstance(FIXTURE, dict) and set(FIXTURE) == {'baseline', 'frozen', 'hunks', 'immutable'}, 'Malformed bottom schema'
    assert FIXTURE['baseline'] == '470f00764d17f597286b93eb7a5c0c56654f4a9a', 'Unexpected bottom baseline'
    for key, paths in (('frozen', FROZEN_PATHS), ('hunks', AUTHORIZED_PATHS), ('immutable', IMMUTABLE_PATHS)):
        assert isinstance(FIXTURE[key], dict) and set(FIXTURE[key]) == paths, ('Unexpected bottom authorization', key)
    for key, expected in (('frozen', FROZEN_MAP_SHA256), ('immutable', IMMUTABLE_MAP_SHA256)):
        assert hashlib.sha256(json.dumps(FIXTURE[key], sort_keys=True).encode()).hexdigest() == expected, ('Changed bottom frozen hashes', key)
    for path, count in HUNK_COUNTS.items():
        edits = FIXTURE['hunks'][path]
        assert isinstance(edits, list) and len(edits) == count, ('Unexpected bottom hunk count', path)
        for edit in edits:
            assert isinstance(edit, dict) and set(edit) == {'before', 'after', 'count'}, ('Malformed bottom hunk', path)
            assert type(edit['count']) is int and edit['count'] == 1, ('Non-unit bottom hunk', path)
            assert all(isinstance(edit[key], str) and edit[key] and edit[key].endswith('\n') for key in ('before', 'after')), ('Incomplete bottom hunk lines', path)
            assert edit['before'] != edit['after'], ('Identity bottom hunk', path)
    assert hashlib.sha256(json.dumps(FIXTURE['hunks'], sort_keys=True).encode()).hexdigest() == HUNKS_SHA256, 'Changed bottom snapshot hunks'


def invert_bottom_swipe(relative, text):
    """Current authorized bytes -> accepted 0.1.13; unknown paths identity."""
    if relative not in FROZEN_PATHS:
        return text
    _validate_fixture()
    edits = FIXTURE['hunks'].get(relative, [])
    end = -1
    for edit in edits:
        starts = _line_starts(text, edit['after'])
        assert len(starts) == 1, ('Missing or duplicate bottom hunk', relative)
        assert starts[0] >= end, ('Out-of-order bottom hunk', relative)
        end = starts[0] + len(edit['after'].splitlines(keepends=True))
    lines = text.splitlines(keepends=True)
    for edit in reversed(edits):
        start = _line_starts(''.join(lines), edit['after'])[0]
        lines[start:start + len(edit['after'].splitlines(keepends=True))] = edit['before'].splitlines(keepends=True)
    restored = ''.join(lines)
    assert digest(restored) == FIXTURE['frozen'][relative], ('Unrelated bottom candidate byte drift', relative)
    return restored


def system_mute_source(relative):
    """Read bytes without newline normalization, restoring only bottom."""
    path = ROOT / relative
    assert path.is_file(), f'Missing implementation: {relative}'
    return invert_bottom_swipe(relative, path.read_bytes().decode('utf-8'))


def accepted_source(relative):
    from system_mute_baseline import invert_system_mute
    return invert_system_mute(relative, system_mute_source(relative))


def accepted_flashlight_source(relative):
    from flashlight_baseline import invert_flashlight
    return invert_flashlight(relative, accepted_source(relative))


def accepted_media_tracks_source(relative):
    from media_tracks_baseline import invert_media_tracks
    return invert_media_tracks(relative, accepted_flashlight_source(relative))


def accepted_layout_source(relative, *, media_play_pause=False, media_tracks=False, flashlight=False):
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
