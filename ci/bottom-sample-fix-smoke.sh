#!/bin/bash
# Execute the new behavioral test on the frozen failed seam, then current code.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test "$(uname -s)" = Darwin
: "${RUNNER_TEMP:?Cloud Mac scratch required}"
: "${OUT_DIR:?Evidence directory required}"
: "${GITHUB_SHA:?Exact source identity required}"
mkdir -p "$OUT_DIR"
RED="$RUNNER_TEMP/bottom-sample-red"
python3 -B "$ROOT/ci/bottom_sample_fix.py" red-fixture --output "$RED" --source-sha "$GITHUB_SHA" > "$OUT_DIR/BOTTOM_SAMPLE_RED_SCOPE.json"
bash "$RED/ci/bottom-gesture-native-smoke.sh" 2>&1 | tee "$OUT_DIR/BOTTOM_SAMPLE_RED_TESTS.txt"
bash "$ROOT/ci/bottom-gesture-native-smoke.sh" 2>&1 | tee "$OUT_DIR/BOTTOM_SAMPLE_GREEN_TESTS.txt"
