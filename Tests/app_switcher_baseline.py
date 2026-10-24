"""Invert only exact counted App Switcher hunks back to device-accepted 0.1.7."""
import json
from pathlib import Path

FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_text())


def invert_app_switcher(relative, text):
    hunks = FIXTURE['hunks'].get(relative, [])
    cursor = -1
    for hunk in hunks:
        if text.count(hunk['after']) != 1:
            raise AssertionError('Unexpected App Switcher hunk/count: ' + relative)
        position = text.index(hunk['after'])
        if position <= cursor:
            raise AssertionError('Unexpected App Switcher hunk order: ' + relative)
        cursor = position
    for hunk in reversed(hunks):
        text = text.replace(hunk['after'], hunk['before'], 1)
    return text
