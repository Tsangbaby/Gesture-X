#!/bin/bash
# Real UIKit simulator execution; never downloads tools/runtimes or fetches Git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The exact same terminal-marker guard is executable on Linux for unit tests.
# A successful simctl transport does NOT imply that the App completed its tests.
if [ "${1:-}" = --verify-output ]; then
    python3 - "$2" "$3" <<'PY'
import re
import sys
from pathlib import Path
status = int(sys.argv[1])
text = Path(sys.argv[2]).read_text(errors='replace')
terminal = [line for line in text.splitlines() if 'BOTTOM_GESTURE_UIKIT_PASS' in line or 'BOTTOM_GESTURE_UIKIT_FAIL' in line]
if status != 0 or len(terminal) != 1 or not re.fullmatch(r'BOTTOM_GESTURE_UIKIT_PASS: assertions=[1-9][0-9]*', terminal[0]):
    raise SystemExit('Bottom UIKit execution incomplete/failed: transport status or unique positive completion marker rejected')
print('Bottom UIKit completion guard accepted')
PY
    exit $?
fi
if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' 'UNSUPPORTED_HOST: bottom Settings UIKit execution requires macOS + Xcode iOS Simulator SDK; no tests executed.' >&2
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
WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:?Apple temporary directory required}}/bottom-settings.XXXXXX")"
DEVICE=""
cleanup() {
    if [ -n "$DEVICE" ]; then
        xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
        xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
xcrun simctl list runtimes --json > "$WORK/runtimes.json"
xcrun simctl list devicetypes --json > "$WORK/device-types.json"
RUNTIME="$(python3 - "$WORK/runtimes.json" <<'PY'
import json, os, sys
runtimes = [r for r in json.load(open(sys.argv[1]))['runtimes'] if r.get('isAvailable') and r['name'].startswith('iOS ') and int(r['version'].split('.')[0]) >= 15]
requested = os.environ.get('BOTTOM_UI_RUNTIME')
if requested:
    runtimes = [r for r in runtimes if r['identifier'] == requested]
if not runtimes:
    raise SystemExit('No compatible installed iOS simulator runtime; no download attempted')
print(max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier'])
PY
)"
DEVICE_TYPE="${BOTTOM_UI_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-13}"
python3 - "$WORK/device-types.json" "$DEVICE_TYPE" <<'PY'
import json, sys
if not any(d['identifier'] == sys.argv[2] for d in json.load(open(sys.argv[1]))['devicetypes']):
    raise SystemExit('Requested iPhone simulator device type not installed')
PY
DEVICE="$(xcrun simctl create "BottomGestureSettings-${GITHUB_RUN_ID:-local}" "$DEVICE_TYPE" "$RUNTIME")"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b

# Native Preferences superclass/factory fixture only; no production owner is
# rewritten. This is needed to exercise the actual old-root -> bottom push.
FRAMEWORK="$WORK/frameworks/Preferences.framework"
mkdir -p "$FRAMEWORK"
xcrun clang -target "$TARGET" -isysroot "$SDK" -fobjc-arc -dynamiclib \
    "$ROOT/Tests/SettingsConstructionFixture.m" -framework UIKit -framework Foundation \
    -install_name @rpath/Preferences.framework/Preferences -o "$FRAMEWORK/Preferences"
APP="$WORK/BottomGestureSettings.app"
mkdir -p "$APP/Frameworks"
python3 - "$FRAMEWORK/Info.plist" "$APP/Info.plist" <<'PY'
import plistlib, sys
framework = dict(CFBundleExecutable='Preferences', CFBundleName='Preferences',
    CFBundleIdentifier='com.tsangbaby.taplock.bottom-fixture', CFBundlePackageType='FMWK',
    CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0')
app = dict(CFBundleExecutable='BottomGestureSettings', CFBundleName='BottomGestureSettings',
    CFBundleIdentifier='com.tsangbaby.taplock.bottom-ui-tests', CFBundlePackageType='APPL',
    CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0',
    LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={})
for path, values in zip(sys.argv[1:], [framework, app]):
    with open(path, 'wb') as output:
        plistlib.dump(values, output)
PY
codesign --force --sign - "$FRAMEWORK"
cp -R "$FRAMEWORK" "$APP/Frameworks/"
cp "$ROOT/Preferences/Resources/BottomGestureReference.json" "$APP/BottomGestureReference.json"
cp "$ROOT/Preferences/Resources/SettingsReference.json" "$APP/SettingsReference.json"
xcrun swiftc -parse-as-library -swift-version 5 -target "$TARGET" -sdk "$SDK" \
    -I "$ROOT/Interfaces" -F "$WORK/frameworks" \
    -import-objc-header "$ROOT/Tests/SettingsConstructionFixture.h" \
    "$ROOT/Shared/Preferences.swift" \
    "$ROOT/Shared/BottomGesturePreferences.swift" \
    "$ROOT/Shared/Applications.swift" \
    "$ROOT/Sources/PrivateAPI.swift" \
    "$ROOT/Preferences/ApplicationIcons.swift" \
    "$ROOT/Preferences/SettingsController.swift" \
    "$ROOT/Preferences/BottomGestureSettingsController.swift" \
    "$ROOT/Tests/BottomGestureSettingsApp.swift" \
    -Xlinker -rpath -Xlinker @executable_path/Frameworks \
    -o "$APP/BottomGestureSettings"
codesign --force --sign - "$APP"
xcrun simctl install "$DEVICE" "$APP"
# Preserve the console and actual transport status, including on timeout. The
# runner itself prints no fake pass marker when launch succeeds without output.
set +e
python3 - "$DEVICE" "$WORK/console.txt" <<'PY'
import subprocess, sys
from pathlib import Path
try:
    result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
        sys.argv[1], 'com.tsangbaby.taplock.bottom-ui-tests'], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=240)
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
printf 'UIKit production execution evidence: %s\n' "$WORK/console.txt"
