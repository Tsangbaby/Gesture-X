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
if [ "${1:-}" = --verify-report ]; then
    bash "$0" --verify-output "$2" "$3" >/dev/null
    python3 - "$3" "$4" "$5" "$6" <<'PY'
import json
import re
import sys
from pathlib import Path
def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate result key')
        result[key] = value
    return result
try:
    text = Path(sys.argv[1]).read_text(errors='replace')
    result = json.loads(Path(sys.argv[2]).read_text(), object_pairs_hook=unique_object)
    sha, token = sys.argv[3:5]
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or not re.fullmatch(r'[0-9a-f]{32}', token):
        raise ValueError('invalid expected source/run identity')
    if not isinstance(result, dict):
        raise ValueError('result must be an object')
    assertions = result['assertions']
    markers = re.findall(r'^BOTTOM_GESTURE_UIKIT_PASS: assertions=([1-9][0-9]*)$', text, re.M)
    if (type(result['schemaVersion']) is not int or result['schemaVersion'] != 1 or
        result['source_commit'] != sha or result['run_token'] != token or
        result['status'] != 'pass' or type(assertions) is not int or assertions <= 0 or
        len(markers) != 1 or int(markers[0]) != assertions or
        not isinstance(result['phase'], str) or not result['phase'] or result['error'] != ''):
        raise ValueError('source/run/result does not agree with successful console completion')
except (OSError, ValueError, KeyError, TypeError) as error:
    raise SystemExit('Bottom UIKit durable completion rejected: ' + str(error))
print('Bottom UIKit owned durable completion guard accepted')
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
SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
TARGET="$(uname -m)-apple-ios15.0-simulator"
WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:?Apple temporary directory required}}/bottom-settings.XXXXXX")"
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RUN_TOKEN="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
python3 - "$SOURCE_COMMIT" <<'PY'
import os, re, sys
sha = sys.argv[1]
if not re.fullmatch(r'[0-9a-f]{40}', sha) or os.environ.get('GITHUB_SHA', sha) != sha:
    raise SystemExit('UIKit harness source identity mismatch')
PY
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
RUNTIME="$(python3 - "$WORK/runtimes.json" "$SDK_VERSION" <<'PY'
import json, os, sys
sdk_major = int(sys.argv[2].split('.')[0])
runtimes = [r for r in json.load(open(sys.argv[1]))['runtimes'] if r.get('isAvailable') and r['name'].startswith('iOS ') and int(r['version'].split('.')[0]) == sdk_major and sdk_major >= 15]
requested = os.environ.get('BOTTOM_UI_RUNTIME')
if requested:
    runtimes = [r for r in runtimes if r['identifier'] == requested]
if not runtimes:
    raise SystemExit('No compatible installed iOS simulator runtime; no download attempted')
print(max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier'])
PY
)"
printf 'BOTTOM_UIKIT_RUNTIME: %s; SDK: %s\n' "$RUNTIME" "$SDK_VERSION"
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
python3 - "$FRAMEWORK/Info.plist" "$APP/Info.plist" "$SOURCE_COMMIT" "$RUN_TOKEN" <<'PY'
import plistlib, sys
framework = dict(CFBundleExecutable='Preferences', CFBundleName='Preferences',
    CFBundleIdentifier='com.tsangbaby.taplock.bottom-fixture', CFBundlePackageType='FMWK',
    CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0')
app = dict(CFBundleExecutable='BottomGestureSettings', CFBundleName='BottomGestureSettings',
    CFBundleIdentifier='com.tsangbaby.taplock.bottom-ui-tests', CFBundlePackageType='APPL',
    CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0',
    LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={},
    BottomUIKitSourceCommit=sys.argv[3], BottomUIKitRunToken=sys.argv[4])
for path, values in zip(sys.argv[1:3], [framework, app]):
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
print('BOTTOM_UIKIT_TRANSPORT_STATUS:', status, flush=True)
try:
    container = subprocess.run(['xcrun', 'simctl', 'get_app_container', sys.argv[1],
        'com.tsangbaby.taplock.bottom-ui-tests', 'data'], capture_output=True, text=True, timeout=15)
    if container.returncode != 0:
        raise OSError('could not resolve owned test container: ' + container.stderr.strip())
    documents = Path(container.stdout.strip()) / 'Documents'
    for name, local, label in [('BottomGestureUIKit.state.json', 'state.json', 'BOTTOM_UIKIT_DURABLE_STATE:'),
                               ('BottomGestureUIKit.result.json', 'result.json', 'BOTTOM_UIKIT_DURABLE_RESULT:')]:
        evidence = documents / name
        if evidence.is_file():
            data = evidence.read_bytes()
            Path(sys.argv[2]).with_name(local).write_bytes(data)
            print(label, data.decode(errors='replace'), flush=True)
        else:
            print(label, 'MISSING', flush=True)
except (OSError, subprocess.TimeoutExpired) as error:
    print('BOTTOM_UIKIT_DURABLE_COLLECTION_FAILED:', str(error), flush=True)
if status != 0 or 'BOTTOM_GESTURE_UIKIT_PASS: assertions=' not in text:
    # Cloud-only evidence, collected before our owned simulator is removed.
    # It changes neither production bytes nor the exact terminal-marker gate.
    roots = [Path.home() / 'Library/Logs/DiagnosticReports',
             Path.home() / 'Library/Developer/CoreSimulator/Devices' / sys.argv[1] /
             'data/Library/Logs/CrashReporter']
    reports = [path for root in roots for path in root.glob('BottomGestureSettings*') if path.is_file()]
    for path in sorted(reports, key=lambda item: item.stat().st_mtime, reverse=True)[:2]:
        print('BottomGestureSettings crash report:', path.name, flush=True)
        print(path.read_text(errors='replace')[:24000], flush=True)
    try:
        processes = subprocess.run(['ps', '-axo', 'pid=,command='], capture_output=True,
                                   text=True, timeout=10)
        targets = [line.strip().split(None, 1)[0] for line in processes.stdout.splitlines()
                   if sys.argv[1] in line and 'BottomGestureSettings.app/BottomGestureSettings' in line]
        print('BOTTOM_UIKIT_RUNNING_PIDS:', targets, flush=True)
        for pid in targets[:1]:
            sample_path = Path(sys.argv[2]).with_name('main-thread-sample.txt')
            sample = subprocess.run(['sample', pid, '1', '1', '-file', str(sample_path)],
                                    capture_output=True, text=True, timeout=20)
            print('BOTTOM_UIKIT_SAMPLE_STATUS:', sample.returncode, sample.stdout, sample.stderr, flush=True)
            if sample_path.is_file():
                print(sample_path.read_text(errors='replace')[:26000], flush=True)
        logs = subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], 'log', 'show',
                               '--last', '4m', '--style', 'compact', '--predicate',
                               'process == "BottomGestureSettings" OR (process == "SpringBoard" AND eventMessage CONTAINS "com.tsangbaby.taplock.bottom-ui-tests")'],
                              capture_output=True, text=True, timeout=30)
        print('BOTTOM_UIKIT_SYSTEM_LOG_STATUS:', logs.returncode, flush=True)
        print((logs.stdout + logs.stderr)[-26000:], flush=True)
    except subprocess.TimeoutExpired as error:
        print('BOTTOM_UIKIT_EVIDENCE_PROBE_TIMEOUT:', error.cmd, flush=True)
raise SystemExit(status)
PY
STATUS=$?
set -e
bash "$0" --verify-output "$STATUS" "$WORK/console.txt"
bash "$0" --verify-report "$STATUS" "$WORK/console.txt" "$WORK/result.json" "$SOURCE_COMMIT" "$RUN_TOKEN"
printf 'UIKit production execution evidence: %s\n' "$WORK/console.txt"
