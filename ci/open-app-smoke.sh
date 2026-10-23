#!/bin/bash
# Real production Swift on cloud macOS; LaunchServices receivers are fixtures.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-app-runtime.XXXXXX")"
# macOS itself already owns the LS class names. Bind only those two lookup
# constants to unique fixtures, proving all other source bytes are unchanged.
python3 - "$ROOT/Shared/Applications.swift" "$WORK/Applications.swift" <<'PY'
from pathlib import Path
import sys
original = Path(sys.argv[1]).read_text()
bindings = [('"LSApplicationProxy"', '"TLTapLockApplicationProxyFixture"', 2),
            ('"LSApplicationWorkspace"', '"TLTapLockApplicationWorkspaceFixture"', 1)]
text = original
for old, new, count in bindings:
    assert original.count(old) == count and new not in original
    text = text.replace(old, new)
restored = text
for old, new, count in bindings:
    assert restored.count(new) == count
    restored = restored.replace(new, old)
assert restored == original
Path(sys.argv[2]).write_text(text)
PY
xcrun swiftc -parse-as-library -swift-version 5 \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/Applications.swift" "$ROOT/Tests/ApplicationsRuntimeTests.swift" \
    -o "$RUNNER_TEMP/open-app-tests"
"$RUNNER_TEMP/open-app-tests" | tee "$RUNNER_TEMP/OPEN_APP_TESTS.txt"
