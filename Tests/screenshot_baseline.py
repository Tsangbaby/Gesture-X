"""Invert only exact counted Screenshot hunks; historical stages stay strict."""
import json
from pathlib import Path

FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_text())


def invert_screenshot(relative, text):
    hunks = FIXTURE['hunks'].get(relative, [])
    cursor = -1
    for hunk in hunks:
        if text.count(hunk['after']) != 1:
            raise AssertionError('Unexpected Screenshot hunk/count: ' + relative)
        position = text.index(hunk['after'])
        if position <= cursor:
            raise AssertionError('Unexpected Screenshot hunk order: ' + relative)
        cursor = position
    for hunk in reversed(hunks):
        text = text.replace(hunk['after'], hunk['before'], 1)
    return text
