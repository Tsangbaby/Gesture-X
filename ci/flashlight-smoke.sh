#!/bin/bash
# Apple Swift execution only; Bash 3.2 compatible, disposable receiver copies.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'flashlight smoke requires Darwin/Apple Swift; no native result produced' >&2
    exit 2
fi
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
: "${GITHUB_SHA:?Exact cloud source commit is required}"
[[ "${CI:-}" == true ]] || { printf '%s\n' 'flashlight smoke requires an isolated cloud CI host' >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-flashlight.XXXXXX")"
BASELINE=925df18141606b75f71c77ddd998ad2baa237efe
RESULTS="$RUNNER_TEMP/FLASHLIGHT_TESTS.txt"
trap 'rm -rf -- "$WORK"' EXIT
# A failed preparation/compiler must not leave a previous completed report.
rm -f -- "$RESULTS"
# Do not append toolchain diagnostics to the exact-record execution report.
xcrun swiftc --version
if ! git -C "$ROOT" cat-file -e "$BASELINE:Shared/Preferences.swift"; then
    git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
fi
python3 -B "$ROOT/ci/flashlight_guard.py" --prepare-sources "$ROOT" "$WORK" "$RESULTS" "$GITHUB_SHA"
xcrun swiftc -parse-as-library -swift-version 5 -O -DFLASHLIGHT_BASELINE \
    "$WORK/LegacyPreferences.swift" "$ROOT/Tests/FlashlightRuntimeTests.swift" \
    -o "$WORK/baseline-tests"
python3 -B "$ROOT/ci/flashlight_guard.py" "$WORK/baseline-tests" "$RESULTS" --baseline
xcrun swiftc -parse-as-library -swift-version 5 -O \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/LockAction.swift" "$WORK/FlashlightAction.swift" \
    "$ROOT/Tests/FlashlightRuntimeTests.swift" -o "$WORK/current-tests"
python3 -B "$ROOT/ci/flashlight_guard.py" "$WORK/current-tests" "$RESULTS" --current
python3 -B "$ROOT/ci/flashlight_guard.py" --complete-suite "$RESULTS" "$GITHUB_SHA"
python3 -B "$ROOT/ci/flashlight_guard.py" --validate-suite "$RESULTS" "$GITHUB_SHA"
