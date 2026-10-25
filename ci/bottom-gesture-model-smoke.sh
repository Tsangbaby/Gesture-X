#!/bin/bash
# Local-only execution of real production Swift. Never downloads a toolchain.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-$(command -v swiftc || true)}"
if [[ -z "$SWIFTC" || ! -x "$SWIFTC" ]]; then
    printf '%s\n' 'BOTTOM_GESTURE_MODEL_UNAVAILABLE: swiftc is required; Swift was NOT executed' >&2
    exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'BOTTOM_GESTURE_MODEL_UNAVAILABLE: Darwin Foundation/CoreFoundation is required; Swift was NOT executed' >&2
    exit 2
fi
: "${TMPDIR:?Set TMPDIR to an existing scratch directory}"
[[ -d "$TMPDIR" && -w "$TMPDIR" ]] || { printf '%s\n' 'TMPDIR is not writable' >&2; exit 2; }
WORK="$(mktemp -d "$TMPDIR/bottom-gesture-model.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
"$SWIFTC" -parse-as-library -swift-version 5 \
    "$ROOT/Shared/Preferences.swift" \
    "$ROOT/Shared/BottomGesturePreferences.swift" \
    "$ROOT/Shared/BottomGestureGeometry.swift" \
    "$ROOT/Tests/BottomGestureModelTests.swift" -o "$WORK/model-tests"
if ! "$WORK/model-tests" > "$WORK/result.txt" 2>&1; then
    python3 -B -c 'import pathlib, sys; sys.stderr.write(pathlib.Path(sys.argv[1]).read_text())' "$WORK/result.txt"
    printf '%s\n' 'Swift model execution failed' >&2
    exit 1
fi
python3 -B - "$WORK/result.txt" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
markers = re.findall(r'^BOTTOM_GESTURE_MODEL_PASS assertions=([1-9][0-9]*)$', text, re.M)
if len(markers) != 1 or 'BOTTOM_GESTURE_MODEL_FAIL' in text or text.count('BOTTOM_GESTURE_MODEL_PASS') != 1:
    print(text, file=sys.stderr)
    raise SystemExit('Swift did not emit exactly one valid model completion marker')
print(text, end='')
PY
