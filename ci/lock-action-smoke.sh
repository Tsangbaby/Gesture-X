#!/usr/bin/env bash
# Execute the same behavioral test against the old and new production actions.
set -euo pipefail
: "${RUNNER_TEMP:?Cloud macOS runner required}"
test "$(uname -s)" = Darwin
BASELINE=fa26d99a0642aad0ed0e9abf7c73d7883bf5ee65
ROOT=$(git rev-parse --show-toplevel)
WORK="$RUNNER_TEMP/lock-button-regression"
mkdir -p "$WORK"
git fetch --no-tags --depth=1 origin "$BASELINE"
git show "$BASELINE:Sources/LockAction.swift" > "$WORK/LegacyLockAction.swift"
python3 -B - "$WORK/LegacyLockAction.swift" <<'PY'
import hashlib, sys
from pathlib import Path
assert hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() == \
    "532850be046aa6fcd67946d7e9e665a54193052df868fa2525e7d86f1a162dc4"
PY
xcrun swiftc -swift-version 5 "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/LegacyLockAction.swift" "$ROOT/Tests/LockActionRuntimeTests.swift" -o "$WORK/legacy"
if "$WORK/legacy" > "$WORK/legacy.log" 2>&1; then
    printf 'ERROR: old production action unexpectedly passed the button contract\n' >&2
    exit 1
fi
python3 -B - "$WORK/legacy.log" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
assert "LOCK_BUTTON_FAIL: one system button action instead of direct UI lock" in text, text
print("LOCK_BUTTON_BASELINE_EXPECTED_FAILURE: old production action fails the button contract")
PY
xcrun swiftc -swift-version 5 "$ROOT/Sources/PrivateAPI.swift" \
    "$ROOT/Sources/LockAction.swift" "$ROOT/Tests/LockActionRuntimeTests.swift" -o "$WORK/current"
"$WORK/current" | tee "$RUNNER_TEMP/LOCK_BUTTON_TESTS.txt"
