"""Exact, ordered inverse of the two-track candidate to accepted 0.1.10 bytes."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = json.loads((ROOT / 'Tests/media_tracks_baseline.json').read_text())


def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def invert_media_tracks(relative, text):
    if relative not in FIXTURE['frozen']:
        return text
    edits = FIXTURE['hunks'].get(relative, [])
    end = -1
    for edit in edits:
        assert edit['count'] == 1, ('Non-unit track hunk', relative)
        assert edit['before'] != edit['after'] and edit['before'] and edit['after']
        assert text.count(edit['after']) == 1, ('Missing or duplicate track hunk', relative)
        start = text.index(edit['after'])
        assert start >= end, ('Out-of-order track hunk', relative)
        end = start + len(edit['after'])
    for edit in edits:
        text = text.replace(edit['after'], edit['before'], 1)
    assert digest(text) == FIXTURE['frozen'][relative], ('Unrelated track-candidate byte drift', relative)
    return text


def accepted_source(relative):
    return invert_media_tracks(relative, (ROOT / relative).read_bytes().decode('utf-8'))
