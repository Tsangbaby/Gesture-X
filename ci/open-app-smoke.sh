#!/bin/bash
# Real production Swift on cloud macOS; LaunchServices receivers are fixtures.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
xcrun swiftc -parse-as-library -swift-version 5 \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$ROOT/Shared/Applications.swift" "$ROOT/Tests/ApplicationsRuntimeTests.swift" \
    -o "$RUNNER_TEMP/open-app-tests"
"$RUNNER_TEMP/open-app-tests" | tee "$RUNNER_TEMP/OPEN_APP_TESTS.txt"
