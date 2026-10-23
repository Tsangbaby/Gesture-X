"""Invert only the counted, user-authorized Open-App delta before old guards."""
import json
from pathlib import Path
from control_center_baseline import invert_control_center

FIXTURE = json.loads(Path(__file__).with_suffix('.json').read_text())


def invert_open_app(relative, text, *, control_center=False):
    if control_center:
        text = invert_control_center(relative, text)
    hunks = FIXTURE['hunks'].get(relative, [])
    cursor = -1
    for hunk in hunks:
        if text.count(hunk['after']) != 1:
            raise AssertionError('Unexpected Open-App hunk/count: ' + relative)
        position = text.index(hunk['after'])
        if position <= cursor:
            raise AssertionError('Unexpected Open-App hunk order: ' + relative)
        cursor = position
    for hunk in reversed(hunks):
        text = text.replace(hunk['after'], hunk['before'], 1)
    return text
