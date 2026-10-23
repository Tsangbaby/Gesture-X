#!/bin/bash
# Execute actual production Swift; only OS receiver identities are fixtures.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-control-center.XXXXXX")"
BASELINE=b8d6994be7defcc37ceac3bb158c5526c952ac3a
RESULTS="$RUNNER_TEMP/CONTROL_CENTER_TESTS.txt"
git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
git -C "$ROOT" show "$BASELINE:Shared/Preferences.swift" > "$WORK/LegacyPreferences.swift"
xcrun swiftc -parse-as-library -swift-version 5 -DCONTROL_CENTER_BASELINE \
    "$WORK/LegacyPreferences.swift" "$ROOT/Tests/ControlCenterRuntimeTests.swift" \
    -o "$WORK/baseline-tests"
python3 - "$WORK/baseline-tests" "$RESULTS" <<'PY'
import subprocess, sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
expected = 'CONTROL_CENTER_RUNTIME_FAIL: persisted Control Center action is unavailable'
if p.returncode != 1 or expected not in p.stdout:
    raise SystemExit('Accepted baseline did not fail at the exact missing-action behavior assertion')
marker = 'CONTROL_CENTER_BASELINE_EXPECTED_FAILURE: unmodified 0.1.4 does not decode the new Control Center action'
with open(sys.argv[2], 'w') as f:
    f.write(p.stdout + marker + '\n')
print(marker, flush=True)
PY

# macOS/iOS may own private class names; keep every production method body,
# dispatch argument and ABI check byte-identical after inverse rebinding.
python3 - "$ROOT" "$WORK" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
for path, bindings in [
    ('Sources/LockAction.swift', [('"SBLockScreenManager"', '"TLControlCenterLockManagerFixture"', 1)]),
    ('Sources/ControlCenterAction.swift', [('"SBControlCenterController"', '"TLControlCenterControllerFixture"', 1)])
]:
    original = (root / path).read_text()
    text = original
    for old, new, count in bindings:
        assert original.count(old) == count and new not in original
        text = text.replace(old, new)
    restored = text
    for old, new, count in bindings:
        assert restored.count(new) == count
        restored = restored.replace(new, old)
    assert restored == original
    (work / Path(path).name).write_text(text)
PY
xcrun swiftc -parse-as-library -swift-version 5 \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/LockAction.swift" "$WORK/ControlCenterAction.swift" \
    "$ROOT/Tests/ControlCenterRuntimeTests.swift" -o "$WORK/current-tests"
python3 - "$WORK/current-tests" "$RESULTS" <<'PY'
import subprocess, sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
if p.returncode or not any(line.startswith('CONTROL_CENTER_RUNTIME_PASS: ') for line in p.stdout.splitlines()):
    raise SystemExit('Control Center test failed: nonzero exit or missing verified completion marker')
with open(sys.argv[2], 'a') as f:
    f.write(p.stdout)
PY
