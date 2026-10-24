"""Explicit full-file 0.1.9 inverse; never opt historical helpers in silently."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_text(encoding='utf-8'))
AUTHORIZED_PATHS = frozenset({
    'Preferences/SettingsController.swift',
    'control',
    'Preferences/Resources/Info.plist',
})


def invert_settings_layout(relative, text):
    """Restore this round's authorized files; leave all other bytes untouched."""
    relative = str(relative)
    if relative not in AUTHORIZED_PATHS:
        return text
    if FIXTURE.get('baseline') != 'f3a2e138fa9ac93d250645e9c66226b074d429ee':
        raise AssertionError('Unexpected settings-layout baseline')
    for key in ('before_text', 'candidate_sha256'):
        if not isinstance(FIXTURE.get(key), dict) or set(FIXTURE[key]) != AUTHORIZED_PATHS:
            raise AssertionError('Unexpected settings-layout authorization: ' + key)
    if not isinstance(FIXTURE.get('frozen'), dict):
        raise AssertionError('Missing settings-layout frozen SHA-256 map')
    for path in AUTHORIZED_PATHS:
        before = FIXTURE['before_text'][path]
        if (not isinstance(before, str) or
                hashlib.sha256(before.encode('utf-8')).hexdigest() != FIXTURE['frozen'].get(path)):
            raise AssertionError('Unexpected settings-layout before SHA-256: ' + path)
    if hashlib.sha256(text.encode('utf-8')).hexdigest() != FIXTURE['candidate_sha256'][relative]:
        raise AssertionError('Unexpected settings-layout candidate SHA-256: ' + relative)
    return FIXTURE['before_text'][relative]


def accepted_source(relative):
    """Read current source, then explicitly undo only this round's exact delta.

    Call this at the outermost historical-test input, before any older inverse
    or mutation. Decode bytes directly so newline translation cannot hide drift.
    """
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f'Missing implementation: {relative}')
    return invert_settings_layout(relative, path.read_bytes().decode('utf-8'))
