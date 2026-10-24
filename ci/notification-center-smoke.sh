#!/bin/bash
# Execute actual production Swift; only OS receiver identities are fixtures.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-notification-center.XXXXXX")"
BASELINE=1b6615b46242abeb5b8ef0f0bf4afba14db18e2a
RESULTS="$RUNNER_TEMP/NOTIFICATION_CENTER_TESTS.txt"
git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
git -C "$ROOT" show "$BASELINE:Shared/Preferences.swift" > "$WORK/LegacyPreferences.swift"
xcrun swiftc -parse-as-library -swift-version 5 -DNOTIFICATION_CENTER_BASELINE \
    "$WORK/LegacyPreferences.swift" "$ROOT/Tests/NotificationCenterRuntimeTests.swift" \
    -o "$WORK/baseline-tests"
python3 - "$WORK/baseline-tests" "$RESULTS" <<'PY'
import subprocess, sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
expected = 'NOTIFICATION_CENTER_RUNTIME_FAIL: persisted Notification Center action is unavailable'
if p.returncode != 1 or expected not in p.stdout:
    raise SystemExit('Accepted baseline did not fail at the exact missing-action behavior assertion')
marker = 'NOTIFICATION_CENTER_BASELINE_EXPECTED_FAILURE: unmodified 0.1.5 does not decode the new Notification Center action'
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
    ('Sources/LockAction.swift', [('"SBLockScreenManager"', '"TLNotificationCenterLockManagerFixture"', 1)]),
    ('Sources/NotificationCenterAction.swift', [('"SBCoverSheetPresentationManager"', '"TLNotificationCenterPresentationManagerFixture"', 1)])
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
    "$WORK/LockAction.swift" "$WORK/NotificationCenterAction.swift" \
    "$ROOT/Tests/NotificationCenterRuntimeTests.swift" -o "$WORK/current-tests"
python3 - "$WORK/current-tests" "$RESULTS" <<'PY'
import subprocess, sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
if p.returncode or not any(line.startswith('NOTIFICATION_CENTER_RUNTIME_PASS: ') for line in p.stdout.splitlines()):
    raise SystemExit('Notification Center test failed: nonzero exit or missing verified completion marker')
with open(sys.argv[2], 'a') as f:
    f.write(p.stdout)
PY
