#!/bin/bash
# Host execution of the actual collector; no Simulator and no handset claim.
set -euo pipefail
: "${RUNNER_TEMP:?Cloud Mac runner required}"
: "${GITHUB_SHA:?Exact source SHA required}"
test "$(uname -s)" = Darwin
ROOT=$(git rev-parse --show-toplevel)
WORK="$RUNNER_TEMP/bottom-panel-diag-runtime"
python3 -B ci/bottom_panel_diagnostic.py extract --output "$WORK" --source-sha "$GITHUB_SHA"
xcrun swiftc -swift-version 5 -parse-as-library -DBOTTOM_PANEL_DIAGNOSTIC -DBOTTOM_DIAGNOSTIC_TESTS \
    "$WORK/Collector.swift" "$WORK/Build.swift" Tests/BottomPanelDiagnosticRuntimeTests.swift -o "$WORK/enabled"
"$WORK/enabled" "$WORK" | tee "$RUNNER_TEMP/taplock-artifacts/BOTTOM_DIAGNOSTIC_RUNTIME.txt"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$WORK/Collector.swift" "$WORK/Build.swift" Tests/BottomPanelDiagnosticRuntimeTests.swift -o "$WORK/disabled"
"$WORK/disabled" "$WORK/disabled-root" | tee "$RUNNER_TEMP/taplock-artifacts/BOTTOM_DIAGNOSTIC_DISABLED.txt"
python3 -B - "$RUNNER_TEMP/taplock-artifacts" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1])
for file,pattern in [('BOTTOM_DIAGNOSTIC_RUNTIME.txt', r'BOTTOM_DIAGNOSTIC_RUNTIME_PASS: assertions=[1-9][0-9]*\n'),
                     ('BOTTOM_DIAGNOSTIC_DISABLED.txt', r'BOTTOM_DIAGNOSTIC_DISABLED_PASS: assertions=[1-9][0-9]*\n')]:
    assert re.fullmatch(pattern, (p/file).read_text()), 'Missing unique positive collector execution marker'
print('DIAGNOSTIC_COLLECTOR_EXECUTED: enabled and disabled production collector on macOS; not handset injection')
PY

# Execute the identical closed-flow integration test on the untouched failure
# baseline and the observer. These must agree; this lane must not repair behavior.
for mode in native-off native-on; do
    stage="$RUNNER_TEMP/bottom-panel-$mode"
    python3 -B ci/bottom_panel_diagnostic.py "$mode" --output "$stage" --source-sha "$GITHUB_SHA" > "$RUNNER_TEMP/taplock-artifacts/$mode-scope.json"
    bash "$stage/ci/bottom-gesture-native-smoke.sh" 2>&1 | tee "$RUNNER_TEMP/taplock-artifacts/$mode-UIKit.txt"
done
