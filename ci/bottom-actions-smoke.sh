#!/bin/bash
# Real production UIKit App. Uses installed tools/runtimes only; no downloads.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" = --verify-output ]; then
    python3 - "$2" "$3" <<'PY'
import re
import sys
from pathlib import Path
status = int(sys.argv[1])
text = Path(sys.argv[2]).read_text(errors='replace')
markers = [line for line in text.splitlines() if 'BOTTOM_ACTIONS_UIKIT_PASS' in line or 'BOTTOM_ACTIONS_UIKIT_FAIL' in line]
if status != 0 or len(markers) != 1 or not re.fullmatch(r'BOTTOM_ACTIONS_UIKIT_PASS: assertions=[1-9][0-9]*', markers[0]):
    raise SystemExit('Bottom actions execution incomplete/failed: transport or unique positive marker rejected')
print('Bottom actions completion guard accepted')
PY
    exit $?
fi
if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' 'UNSUPPORTED_HOST: bottom actions UIKit requires macOS + Xcode iOS Simulator SDK; no tests executed.' >&2
    exit 69
fi
for tool in xcrun codesign python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'MISSING_APPLE_PREREQUISITE: %s; no tests executed.\n' "$tool" >&2
        exit 69
    fi
done
xcrun --find swiftc >/dev/null
xcrun --find simctl >/dev/null
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="$(uname -m)-apple-ios15.0-simulator"
WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:?Apple temporary directory required}}/bottom-actions.XXXXXX")"
DEVICE=""
cleanup() {
    if [ -n "$DEVICE" ]; then
        xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
        xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
xcrun simctl list runtimes --json > "$WORK/runtimes.json"
RUNTIME="$(python3 - "$WORK/runtimes.json" <<'PY'
import json, os, sys
runtimes = [r for r in json.load(open(sys.argv[1]))['runtimes'] if r.get('isAvailable') and r['name'].startswith('iOS ') and int(r['version'].split('.')[0]) >= 15]
requested = os.environ.get('BOTTOM_ACTIONS_RUNTIME')
if requested:
    runtimes = [r for r in runtimes if r['identifier'] == requested]
if not runtimes:
    raise SystemExit('No compatible installed iOS simulator runtime; no download attempted')
print(max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier'])
PY
)"
DEVICE_TYPE="${BOTTOM_ACTIONS_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-13}"
DEVICE="$(xcrun simctl create "BottomActions-${GITHUB_RUN_ID:-local}" "$DEVICE_TYPE" "$RUNTIME")"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
APP="$WORK/BottomActions.app"
mkdir -p "$APP"
python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
values = dict(CFBundleExecutable='BottomActions', CFBundleName='BottomActions',
    CFBundleIdentifier='com.tsangbaby.taplock.bottom-actions-tests', CFBundlePackageType='APPL',
    CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0',
    LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={},
    UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False,
        UISceneConfigurations={'UIWindowSceneSessionRoleApplication': [dict(
            UISceneConfigurationName='BottomActions', UISceneDelegateClassName='BottomActions.BottomActionsApp')]}))
with open(sys.argv[1], 'wb') as output:
    plistlib.dump(values, output)
PY
# Include all unchanged real providers: no reimplemented provider fixtures.
xcrun swiftc -parse-as-library -swift-version 5 -module-name BottomActions -target "$TARGET" -sdk "$SDK" \
    "$ROOT/Shared/Preferences.swift" \
    "$ROOT/Shared/BottomGesturePreferences.swift" \
    "$ROOT/Sources/PrivateAPI.swift" \
    "$ROOT/Sources/LockAction.swift" \
    "$ROOT/Sources/AppAction.swift" \
    "$ROOT/Sources/ControlCenterAction.swift" \
    "$ROOT/Sources/NotificationCenterAction.swift" \
    "$ROOT/Sources/ScreenshotAction.swift" \
    "$ROOT/Sources/AppSwitcherAction.swift" \
    "$ROOT/Sources/MediaPlayPauseAction.swift" \
    "$ROOT/Sources/FlashlightAction.swift" \
    "$ROOT/Sources/SystemMuteAction.swift" \
    "$ROOT/Sources/BottomActions.swift" \
    "$ROOT/Tests/BottomActionsApp.swift" \
    -o "$APP/BottomActions"
codesign --force --sign - "$APP"
xcrun simctl install "$DEVICE" "$APP"
set +e
python3 - "$DEVICE" "$WORK/console.txt" <<'PY'
import subprocess, sys
from pathlib import Path
try:
    result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
        sys.argv[1], 'com.tsangbaby.taplock.bottom-actions-tests'], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=180)
    text, status = result.stdout, result.returncode
except subprocess.TimeoutExpired as error:
    text = error.stdout or b''
    if isinstance(text, bytes):
        text = text.decode(errors='replace')
    status = 124
Path(sys.argv[2]).write_text(text)
print(text, end='', flush=True)
raise SystemExit(status)
PY
STATUS=$?
set -e
bash "$0" --verify-output "$STATUS" "$WORK/console.txt"
printf 'UIKit execution evidence: %s\n' "$WORK/console.txt"
