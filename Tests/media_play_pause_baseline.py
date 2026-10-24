"""Exact media-only inverse to device-accepted 0.1.9; never applied implicitly."""
import hashlib
import json
from pathlib import Path

FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_text())
AUTHORIZED_PATHS = frozenset({
    'Makefile', 'Shared/Preferences.swift', 'Sources/HomeDoubleTap.swift',
    'Preferences/SettingsController.swift', 'Preferences/Resources/SettingsReference.json',
    'control', 'Preferences/Resources/Info.plist',
})


def invert_media_play_pause(relative, text):
    relative = str(relative)
    if FIXTURE['baseline'] != '1e2b7ef11a5f743b8db122c02d9a5478d2f20bfa' or set(FIXTURE['hunks']) != AUTHORIZED_PATHS:
        raise AssertionError('Unexpected media inverse scope/baseline')
    hunks = FIXTURE['hunks'].get(relative, [])
    cursor = -1
    for hunk in hunks:
        if text.count(hunk['after']) != 1:
            raise AssertionError('Unexpected media hunk/count: ' + relative)
        position = text.index(hunk['after'])
        if position <= cursor:
            raise AssertionError('Unexpected media hunk order: ' + relative)
        cursor = position
    for hunk in reversed(hunks):
        text = text.replace(hunk['after'], hunk['before'], 1)
    if relative in FIXTURE['frozen'] and hashlib.sha256(text.encode('utf-8')).hexdigest() != FIXTURE['frozen'][relative]:
        raise AssertionError('Unrelated protected-source drift: ' + relative)
    return text
