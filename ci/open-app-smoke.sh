#!/bin/bash
# Real production Swift on cloud macOS; LaunchServices receivers are fixtures.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-app-runtime.XXXXXX")"
BASELINE=fe7630b7658573915d23d5cc6e1b75a712a13c7f
git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
git -C "$ROOT" show "$BASELINE:Shared/Applications.swift" > "$WORK/LegacyApplications.swift"

compile_case() {
    local input="$1" label="$2"
    # macOS owns these LS class names. Rebind only lookup constants; prove
    # every other byte, including method bodies and ABI checks, is unchanged.
    python3 - "$input" "$WORK/$label-Applications.swift" "$label" <<'PY'
from pathlib import Path
import sys
original = Path(sys.argv[1]).read_text()
bindings = [('"LSApplicationProxy"', '"TLTapLockApplicationProxyFixture"', 2),
            ('"LSApplicationWorkspace"', '"TLTapLockApplicationWorkspaceFixture"', 1),
            ('"LSApplicationRecord"', '"TLTapLockApplicationRecordFixture"',
             1 if sys.argv[3] == 'current' else 0)]
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
        "$WORK/$label-Applications.swift" "$ROOT/Tests/ApplicationsRuntimeTests.swift" \
        -o "$WORK/$label-tests"
}
compile_case "$WORK/LegacyApplications.swift" baseline
python3 - "$WORK/baseline-tests" "$RUNNER_TEMP/OPEN_APP_TESTS.txt" <<'PY'
import subprocess, sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
if p.returncode != 1 or 'OPEN_APP_RUNTIME_FAIL: filter, sort or deduplication failed' not in p.stdout:
    raise SystemExit('Legacy proxy-property implementation did not fail at the expected catalog assertion')
with open(sys.argv[2], 'w') as f:
    f.write(p.stdout + 'OPEN_APP_BASELINE_EXPECTED_FAILURE: proxy-only admission rejects real record-backed Apps\n')
print('OPEN_APP_BASELINE_EXPECTED_FAILURE: proxy-only admission rejects real record-backed Apps', flush=True)
PY
compile_case "$ROOT/Shared/Applications.swift" current
"$WORK/current-tests" | tee -a "$RUNNER_TEMP/OPEN_APP_TESTS.txt"
