"""Invert only the counted Control Center delta to device-accepted 0.1.4."""
import json
from pathlib import Path

FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_text())


def invert_control_center(relative, text):
    hunks = FIXTURE['hunks'].get(relative, [])
    cursor = -1
    for hunk in hunks:
        if text.count(hunk['after']) != 1:
            raise AssertionError('Unexpected Control Center hunk/count: ' + relative)
        position = text.index(hunk['after'])
        if position <= cursor:
            raise AssertionError('Unexpected Control Center hunk order: ' + relative)
        cursor = position
    for hunk in reversed(hunks):
        text = text.replace(hunk['after'], hunk['before'], 1)
    return text
