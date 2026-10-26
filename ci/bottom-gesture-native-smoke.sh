#!/bin/bash
# Real UIKit/ObjC execution only. Uses installed Apple tools/runtime; no downloads.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" = --verify-output ]; then
    python3 - "$2" "$3" <<'PY'
import re, sys
from pathlib import Path
status = int(sys.argv[1])
text = Path(sys.argv[2]).read_text(errors='replace')
terminal = [line for line in text.splitlines() if 'BOTTOM_GESTURE_NATIVE_PASS' in line or 'BOTTOM_GESTURE_NATIVE_FAIL' in line]
if status != 0 or len(terminal) != 1 or not re.fullmatch(r'BOTTOM_GESTURE_NATIVE_PASS: assertions=[1-9][0-9]*', terminal[0]):
    raise SystemExit('Bottom native execution incomplete/failed: transport or unique positive completion marker rejected')
print('Bottom native completion guard accepted')
PY
    exit $?
fi
if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' 'UNSUPPORTED_HOST: bottom native UIKit/ObjC requires macOS + Xcode iOS Simulator SDK; no tests executed.' >&2
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
SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
TARGET="$(uname -m)-apple-ios15.0-simulator"
WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:?Writable scratch directory required}}/bottom-native.XXXXXX")"
DEVICE=""
cleanup() {
    if [ -n "$DEVICE" ]; then
        xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
        xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
# Zero-argument operation: choose an already installed, available iOS runtime,
# create our own simulator and clean up only that owned device on every exit.
xcrun simctl list runtimes --json > "$WORK/runtimes.json"
xcrun simctl list devicetypes --json > "$WORK/device-types.json"
RUNTIME="$(python3 - "$WORK/runtimes.json" "$SDK_VERSION" <<'PY'
import json, os, sys
sdk_major = int(sys.argv[2].split('.')[0])
runtimes = [r for r in json.load(open(sys.argv[1]))['runtimes'] if r.get('isAvailable') and r['name'].startswith('iOS ') and int(r['version'].split('.')[0]) == sdk_major and sdk_major >= 15]
requested = os.environ.get('BOTTOM_NATIVE_RUNTIME')
if requested:
    runtimes = [r for r in runtimes if r['identifier'] == requested]
if not runtimes:
    raise SystemExit('MISSING_APPLE_PREREQUISITE: no compatible installed iOS simulator runtime; no tests executed; no download attempted')
print(max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier'])
PY
)"
printf 'BOTTOM_NATIVE_RUNTIME: %s; SDK: %s\n' "$RUNTIME" "$SDK_VERSION"
DEVICE_TYPE="${BOTTOM_NATIVE_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-13}"
python3 - "$WORK/device-types.json" "$DEVICE_TYPE" <<'PY'
import json, sys
if not any(d['identifier'] == sys.argv[2] for d in json.load(open(sys.argv[1]))['devicetypes']):
    raise SystemExit('MISSING_APPLE_PREREQUISITE: requested iPhone device type not installed; no tests executed')
PY
DEVICE="$(xcrun simctl create "BottomGestureNative-${GITHUB_RUN_ID:-local}" "$DEVICE_TYPE" "$RUNTIME")"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
APP="$WORK/BottomGestureNative.app"
mkdir -p "$APP"
# The unchanged existing Objective-C fixture provides a real runtime IMP swap,
# not a reimplementation of gesture/session policy or a handset substrate claim.
xcrun clang -target "$TARGET" -isysroot "$SDK" -fobjc-arc -c \
    "$ROOT/Tests/NativeHookFixture.m" -o "$WORK/NativeHookFixture.o"
# Compile the actual complete bottom-runtime graph and unchanged providers in one
# Swift module. Old bootstrap/home startup has its separate complete-graph smoke.
xcrun swiftc -parse-as-library -swift-version 5 -module-name BottomGestureNative -target "$TARGET" -sdk "$SDK" \
    -I "$ROOT/Interfaces" -import-objc-header "$ROOT/Tests/NativeHookFixture.h" \
    "$ROOT/Shared/Preferences.swift" \
    "$ROOT/Shared/BottomGesturePreferences.swift" \
    "$ROOT/Shared/BottomGestureGeometry.swift" \
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
    "$ROOT/Sources/BottomGestureNative.swift" \
    "$ROOT/Sources/BottomGestureSession.swift" \
    "$ROOT/Tests/BottomGestureNativeApp.swift" \
    "$WORK/NativeHookFixture.o" -framework UIKit -framework Foundation \
    -o "$APP/BottomGestureNative"
python3 - "$APP/Info.plist" <<'PY'
import os, plistlib, sys, uuid
with open(sys.argv[1], 'wb') as output:
    plistlib.dump(dict(CFBundleExecutable='BottomGestureNative', CFBundleName='BottomGestureNative',
        BottomNativeSourceCommit=os.environ['GITHUB_SHA'], BottomNativeRunToken=uuid.uuid4().hex,
        CFBundleIdentifier='com.tsangbaby.taplock.bottom-native-tests', CFBundlePackageType='APPL',
        CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0',
        LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={},
        UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False,
            UISceneConfigurations=dict(UIWindowSceneSessionRoleApplication=[dict(
                UISceneConfigurationName='BottomNative',
                UISceneDelegateClassName='BottomGestureNative.BottomGestureNativeApp')]))), output)
PY
codesign --force --sign - "$APP"
xcrun simctl install "$DEVICE" "$APP"
set +e
python3 - "$DEVICE" "$WORK/console.txt" "$APP/Info.plist" "$ROOT/ci" <<'PY'
import json, plistlib, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[4])
from bottom_sample_fix import validate_owned_result
metadata = plistlib.loads(Path(sys.argv[3]).read_bytes())
container = subprocess.run(['xcrun', 'simctl', 'get_app_container', sys.argv[1],
    'com.tsangbaby.taplock.bottom-native-tests', 'data'], capture_output=True, text=True, timeout=15)
container.check_returncode()
documents = Path(container.stdout.strip()) / 'Documents'
result_file = documents / 'BottomGestureNative.result.json'
assert not result_file.exists(), 'Owned new simulator must not contain a stale result'
deadline = time.monotonic() + 180
try:
    result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
        sys.argv[1], 'com.tsangbaby.taplock.bottom-native-tests'], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=max(1, deadline - time.monotonic()))
    text, status = result.stdout, result.returncode
except subprocess.TimeoutExpired as error:
    text = error.stdout or b''
    if isinstance(text, bytes):
        text = text.decode(errors='replace')
    status = 124
# simctl can return only a PID while the App is still running. Require an actual
# App-written terminal marker bound to this exact SHA and unique launch token.
while status in (0, 1) and not result_file.exists() and time.monotonic() < deadline:
    time.sleep(0.2)
Path(sys.argv[2]).write_text(text)
print(text, end='', flush=True)
print('BOTTOM_NATIVE_TRANSPORT_STATUS:', status, flush=True)
state_file = documents / 'BottomGestureNative.state.json'
if state_file.exists():
    print('BOTTOM_NATIVE_OWNED_STATE:', state_file.read_text(), flush=True)
record = json.loads(result_file.read_text()) if result_file.exists() else None
marker = validate_owned_result(status, text, record,
    metadata['BottomNativeSourceCommit'], metadata['BottomNativeRunToken'])
if marker not in text.splitlines():
    text += '\n' + marker + '\n'
    print(marker, flush=True)
Path(sys.argv[2]).write_text(text)
raise SystemExit(0 if marker.startswith('BOTTOM_GESTURE_NATIVE_PASS:') else 1)
PY
STATUS=$?
set -e
bash "$0" --verify-output "$STATUS" "$WORK/console.txt"
printf 'UIKit/ObjC production execution evidence: %s\n' "$WORK/console.txt"
