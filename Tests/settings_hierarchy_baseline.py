"""Exact, counted inverse for the user-authorized Settings-only UI change."""
import json
from pathlib import Path

FIXTURE = json.loads(Path(__file__).with_suffix(".json").read_text())


def invert_settings_hierarchy(text):
    for hunk in FIXTURE["hunks"]:
        if text.count(hunk["after"]) != 1:
            raise AssertionError("Unexpected Settings hierarchy hunk/count")
        text = text.replace(hunk["after"], hunk["before"], 1)
    return text
