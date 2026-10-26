"""Exact observation-only inverse to the failed bottomfix1 source, never a repair."""
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BASE = 'b606238d93bb71e7caf1c219767aefaad63a0bb7'
MANIFEST_SHA256 = 'c0eb3439b2f906f5277229f443f3d49b0f9b6598916c666fa1281dedea4643dc'
FROZEN = {'Sources/BottomGestureSession.swift': '793b955b60e71c32927a9e5215c311f78f302e8d9299e275e655f552478ff543', 'Sources/BottomGestureNative.swift': 'd0673687b9c42ec7de020529a2c4ae810c3ce6adb192ff88987df1c454e06e3f', 'Sources/BottomActions.swift': 'bd8f20d4fa05c5b3531cc18ff84c3b4806ba70012b7e725ccde6759aa6906aaf'}
COUNTS = {'Sources/BottomGestureSession.swift': 10, 'Sources/BottomGestureNative.swift': 12, 'Sources/BottomActions.swift': 9}


def restore(relative, text):
    if relative not in FROZEN:
        return text
    raw = Path(__file__).with_suffix('.json').read_bytes()
    assert hashlib.sha256(raw).hexdigest() == MANIFEST_SHA256, 'Diagnostic manifest drift'
    manifest = json.loads(raw)
    assert manifest['observation_base'] == BASE and set(manifest['files']) == set(FROZEN)
    record = manifest['files'][relative]
    assert record['base_sha256'] == FROZEN[relative]
    assert len(record['hunks']) == COUNTS[relative]
    for edit in reversed(record['hunks']):
        assert text.count(edit['after']) == 1, ('Diagnostic inverse anchor', relative)
        text = text.replace(edit['after'], edit['before'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == FROZEN[relative], ('Non-observation drift', relative)
    return text


def source(relative):
    return restore(relative, (ROOT / relative).read_bytes().decode())
