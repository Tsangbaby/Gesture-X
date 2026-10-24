#!/bin/bash
# Execute actual production Swift; only OS receiver identities are fixtures.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'Screenshot runtime tests require macOS, Apple Swift and the Objective-C runtime.' >&2
    exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-screenshot.XXXXXX")"
BASELINE=078b98fb67582422a577b70ae3335ecc0d1e2ab9
# Derived from git show 078b98fb67582422a577b70ae3335ecc0d1e2ab9:Shared/Preferences.swift.
BASELINE_PREFERENCES_SHA256=11db8944458ba92051d6189ed788d20fd2ebd9f1fc2e1272591577f24ff5c6ed
RESULTS="$RUNNER_TEMP/SCREENSHOT_TESTS.txt"
finish() {
    status=$?
    if [[ "$status" -ne 0 ]]; then
        printf 'SCREENSHOT_RUNNER_FAIL: exit status %s; no completed runtime proof\n' "$status" >> "$RESULTS"
    fi
    rm -rf -- "$WORK"
    exit "$status"
}
trap finish EXIT
printf 'SCREENSHOT_SOURCE_COMMIT: %s\n' "$(git -C "$ROOT" rev-parse HEAD)" >> "$RESULTS"
printf '%s\n' 'SCREENSHOT_EXECUTION_BOUNDARY: real macOS Swift executable tests of production preferences, PrivateAPI, LockAction and ScreenshotAction with Objective-C receiver fixtures; NOT handset screenshot creation, image rendering/saving, flash/animation, or iOS compatibility proof.' >> "$RESULTS"
xcrun swiftc --version >> "$RESULTS"

git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
[[ "$(git -C "$ROOT" cat-file -t "$BASELINE")" == commit ]]
git -C "$ROOT" show "$BASELINE:Shared/Preferences.swift" > "$WORK/LegacyPreferences.swift"
python3 - "$WORK/LegacyPreferences.swift" "$BASELINE_PREFERENCES_SHA256" "$RESULTS" <<'PY'
from pathlib import Path
import hashlib
import sys
source = Path(sys.argv[1]).read_bytes()
actual = hashlib.sha256(source).hexdigest()
if actual != sys.argv[2]:
    raise SystemExit(f'Unmodified baseline preferences digest mismatch: {actual}')
marker = f'SCREENSHOT_BASELINE_BYTES_VERIFIED: 078b98fb67582422a577b70ae3335ecc0d1e2ab9 Shared/Preferences.swift sha256={actual}'
with open(sys.argv[3], 'a') as results:
    results.write(marker + '\n')
print(marker, flush=True)
PY
xcrun swiftc -parse-as-library -swift-version 5 -DSCREENSHOT_BASELINE \
    "$WORK/LegacyPreferences.swift" "$ROOT/Tests/ScreenshotRuntimeTests.swift" \
    -o "$WORK/baseline-tests"
python3 - "$WORK/baseline-tests" "$RESULTS" <<'PY'
import subprocess
import sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
with open(sys.argv[2], 'a') as results:
    results.write(p.stdout)
expected = 'SCREENSHOT_RUNTIME_FAIL: persisted screenshot action is unavailable'
if p.returncode != 1 or p.stdout.splitlines() != [expected]:
    raise SystemExit('Accepted baseline must exit 1 at the exact missing-action behavior assertion, not compile/harness failure')
marker = 'SCREENSHOT_BASELINE_EXPECTED_FAILURE: actual unmodified 0.1.6 preferences do not decode the persisted screenshot action'
with open(sys.argv[2], 'a') as results:
    results.write(marker + '\n')
print(marker, flush=True)
PY

# macOS may already own private class names. Replace ONLY these exact lookup
# literals in DISPOSABLE copies, with exact counts and byte-identical inversion.
# Current preferences and PrivateAPI compile directly from the checkout.
python3 - "$ROOT" "$WORK" "$RESULTS" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:3])
prefs = (root / 'Shared/Preferences.swift').read_bytes()
if prefs.count(b'static let domain = "com.tsangbaby.taplock"') != 1:
    raise SystemExit('The actual existing preference domain must not be rebound')
for path, bindings in [
    ('Sources/LockAction.swift', [
        (b'"SBLockScreenManager"', b'"TLSystemScreenshotLockManagerFixture"', 1),
        (b'"SpringBoard"', b'"TLSystemScreenshotApplicationFixture"', 1),
    ]),
    ('Sources/ScreenshotAction.swift', [
        (b'"SpringBoard"', b'"TLSystemScreenshotApplicationFixture"', 1),
    ]),
]:
    original = (root / path).read_bytes()
    text = original
    for old, new, count in bindings:
        assert original.count(old) == count, (path, old, original.count(old), count)
        assert new not in original, (path, 'fixture name already occurs in production')
        text = text.replace(old, new)
    restored = text
    for old, new, count in bindings:
        assert restored.count(new) == count, (path, new, restored.count(new), count)
        restored = restored.replace(new, old)
    assert restored == original, (path, 'inverse rebinding changed production bytes')
    (work / Path(path).name).write_bytes(text)
marker = 'SCREENSHOT_FIXTURE_REBINDING_VERIFIED: LockAction SBLockScreenManager=1 SpringBoard=1; ScreenshotAction SpringBoard=1; inverse copies equal original bytes'
with open(sys.argv[3], 'a') as results:
    results.write(marker + '\n')
print(marker, flush=True)
PY
xcrun swiftc -parse-as-library -swift-version 5 \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/LockAction.swift" "$WORK/ScreenshotAction.swift" \
    "$ROOT/Tests/ScreenshotRuntimeTests.swift" -o "$WORK/current-tests"
python3 - "$WORK/current-tests" "$RESULTS" <<'PY'
import re
import subprocess
import sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
with open(sys.argv[2], 'a') as results:
    results.write(p.stdout)
pattern = r'SCREENSHOT_RUNTIME_PASS: ([1-9][0-9]*) assertions against production Swift; OS receivers are fixtures, NOT handset screenshot proof'
lines = p.stdout.splitlines()
if p.returncode != 0 or len(lines) != 1 or re.fullmatch(pattern, lines[0]) is None:
    raise SystemExit('Screenshot runtime tests failed: nonzero exit or missing/extraneous exact completion marker')
marker = 'SCREENSHOT_SWIFT_EXECUTION_PASS: baseline behavior RED and candidate runtime GREEN executed as real Swift; handset screenshot and iOS system integration remain unverified'
with open(sys.argv[2], 'a') as results:
    results.write(marker + '\n')
print(marker, flush=True)
PY
