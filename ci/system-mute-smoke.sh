#!/bin/bash
# Apple Swift execution only; Bash 3.2 compatible, disposable receiver copies.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'system-mute smoke requires Darwin/Apple Swift; no native result produced' >&2
    exit 2
fi
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
: "${GITHUB_SHA:?Exact cloud source commit is required}"
[[ "${CI:-}" == true ]] || { printf '%s\n' 'system-mute smoke requires an isolated cloud CI host' >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-system-mute.XXXXXX")"
BASELINE=0cc50fbd3e82c336f89394f80cb298aa150a1c70
RESULTS="$RUNNER_TEMP/SYSTEM_MUTE_TESTS.txt"
trap 'rm -rf -- "$WORK"' EXIT
rm -f -- "$RESULTS"
xcrun swiftc --version
if ! git -C "$ROOT" cat-file -e "$BASELINE:Shared/Preferences.swift"; then
    git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
fi
python3 -B "$ROOT/ci/system_mute_guard.py" --prepare-sources "$ROOT" "$WORK" "$RESULTS" "$GITHUB_SHA"
xcrun swiftc -parse-as-library -swift-version 5 -O -DSYSTEM_MUTE_BASELINE \
    "$WORK/LegacyPreferences.swift" "$ROOT/Tests/SystemMuteRuntimeTests.swift" \
    -o "$WORK/baseline-tests"
python3 -B "$ROOT/ci/system_mute_guard.py" "$WORK/baseline-tests" "$RESULTS" --baseline
xcrun swiftc -parse-as-library -swift-version 5 -O \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/LockAction.swift" "$WORK/SystemMuteAction.swift" \
    "$ROOT/Tests/SystemMuteRuntimeTests.swift" -o "$WORK/current-tests"
python3 -B "$ROOT/ci/system_mute_guard.py" "$WORK/current-tests" "$RESULTS" --current
python3 -B "$ROOT/ci/system_mute_guard.py" --complete-suite "$RESULTS" "$GITHUB_SHA"
python3 -B "$ROOT/ci/system_mute_guard.py" --validate-suite "$RESULTS" "$GITHUB_SHA"
