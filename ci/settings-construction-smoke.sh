#!/bin/bash
# Execute the production Swift Settings constructor in UIKit, not a text mock.
# Preferences.framework here is an isolated native superclass/factory fixture.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
BASELINE=72826b2a558b03e20a7dd5e98047dfdecc489202
HIERARCHY_BASELINE=94b384d64ce44705e754f4695c98661110db76ff
OPEN_APP_BASELINE=7f35f9e51aa9d61d8bd052f0ab6b85127313d326
ICON_BASELINE=cb3f53b27e102b74cea93bf9a44d476cb873477a
CONTROL_CENTER_BASELINE=b8d6994be7defcc37ceac3bb158c5526c952ac3a
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-settings.XXXXXX")"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-ios15.0-simulator"
DEVICE=""
RESULTS="$RUNNER_TEMP/SETTINGS_CONSTRUCTION_TESTS.txt"
cleanup() {
    if [ -n "$DEVICE" ]; then
        xcrun simctl shutdown "$DEVICE" || true
        xcrun simctl delete "$DEVICE" || true
    fi
}
trap cleanup EXIT

# Use an already installed Xcode-16-compatible runtime; never download an OS.
xcrun simctl list runtimes --json > "$WORK/runtimes.json"
xcrun simctl list devicetypes --json > "$WORK/types.json"
RUNTIME="$(python3 - "$WORK/runtimes.json" <<'PY'
import json, sys
items = [r for r in json.load(open(sys.argv[1]))['runtimes']
         if r.get('isAvailable') and r['name'].startswith('iOS ')
         and r['version'].split('.')[0] == '18']
if not items:
    raise SystemExit('No installed iOS 18 simulator runtime for Xcode 16.4')
print(max(items, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier'])
PY
)"
DEVICE_TYPE="$(python3 - "$WORK/types.json" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))['devicetypes']
print(next(d['identifier'] for d in items if d['name'] == 'iPhone 16'))
PY
)"
DEVICE="$(xcrun simctl create "TapLock constructor ${GITHUB_RUN_ID:-test}" "$DEVICE_TYPE" "$RUNTIME")"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b

# No production build ever sees this fixture framework or the Objective-C shim.
FRAMEWORK="$WORK/frameworks/Preferences.framework"
mkdir -p "$FRAMEWORK"
xcrun clang -target "$TARGET" -isysroot "$SDK" -fobjc-arc -dynamiclib \
    "$ROOT/Tests/SettingsConstructionFixture.m" -framework UIKit -framework Foundation \
    -install_name @rpath/Preferences.framework/Preferences -o "$FRAMEWORK/Preferences"
python3 - "$FRAMEWORK/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='Preferences', CFBundleName='Preferences',
        CFBundleIdentifier='com.tsangbaby.taplock.test-host-fixture',
        CFBundlePackageType='FMWK', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='15.0'), f)
PY
codesign --force --sign - "$FRAMEWORK"

# Freeze the actual failing source, not a hand-rewritten version of the bug.
git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
OLD="$WORK/baseline-source"
for path in Shared/Preferences.swift Preferences/SettingsController.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$OLD/$(dirname "$path")"
    git -C "$ROOT" show "$BASELINE:$path" > "$OLD/$path"
done
git -C "$ROOT" fetch --no-tags --depth=1 origin "$HIERARCHY_BASELINE"
STABLE="$WORK/accepted-source"
for path in Shared/Preferences.swift Preferences/SettingsController.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$STABLE/$(dirname "$path")"
    git -C "$ROOT" show "$HIERARCHY_BASELINE:$path" > "$STABLE/$path"
done
python3 - "$RESULTS" "$BASELINE" "$RUNTIME" "$TARGET" <<'PY'
import sys
with open(sys.argv[1], 'w') as f:
    f.write('Boundary: real production Swift + UIKit, native Preferences superclass fixture; NOT device Settings\n')
    f.write('Frozen failing source: ' + sys.argv[2] + '\n')
    f.write('Runtime: ' + sys.argv[3] + '\nTarget: ' + sys.argv[4] + '\n')
PY

git -C "$ROOT" fetch --no-tags --depth=1 origin "$OPEN_APP_BASELINE"
APP_OLD="$WORK/accepted-lock-ui"
for path in Shared/Preferences.swift Preferences/SettingsController.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$APP_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$OPEN_APP_BASELINE:$path" > "$APP_OLD/$path"
done

# Freeze the actual version whose picker had no image assignment.
git -C "$ROOT" fetch --no-tags --depth=1 origin "$ICON_BASELINE"
ICON_OLD="$WORK/no-app-icons"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$ICON_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$ICON_BASELINE:$path" > "$ICON_OLD/$path"
done

git -C "$ROOT" fetch --no-tags --depth=1 origin "$CONTROL_CENTER_BASELINE"
CC_OLD="$WORK/accepted-no-control-center"
for path in Shared/Preferences.swift Shared/Applications.swift Sources/PrivateAPI.swift \
            Preferences/SettingsController.swift Preferences/ApplicationIcons.swift \
            Interfaces/TapLockPreferencesHost/PSViewController.h \
            Interfaces/TapLockPreferencesHost/module.modulemap; do
    mkdir -p "$CC_OLD/$(dirname "$path")"
    git -C "$ROOT" show "$CONTROL_CENTER_BASELINE:$path" > "$CC_OLD/$path"
done

run_case() {
    local source_root="$1" label="$2" mode="$3" marker="$4"
    local app="$WORK/$label.app" bundle="com.tsangbaby.taplock.constructor-$label"
    mkdir -p "$app/Frameworks"
    cp -R "$FRAMEWORK" "$app/Frameworks/"
    python3 - "$app/Info.plist" "$bundle" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='SettingsConstruction',
        CFBundleIdentifier=sys.argv[2], CFBundleName='SettingsConstruction',
        CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='15.0',
        LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={}), f)
PY
    local compile_sources=("$source_root/Shared/Preferences.swift" "$source_root/Preferences/SettingsController.swift")
    local compile_flags=(-parse-as-library -swift-version 5)
    if [ "$label" = app-baseline ] || [ "$label" = icon-baseline ] || [ "$label" = control-center-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DOPEN_APP_ROWS)
    fi
    if [ "$label" = icon-baseline ] || [ "$label" = control-center-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DOPEN_APP_FEATURE -DAPP_ICONS)
        compile_sources+=("$source_root/Shared/Applications.swift" "$source_root/Sources/PrivateAPI.swift")
    fi
    if [ "$label" = control-center-baseline ] || [ "$label" = fixed ]; then
        compile_flags+=(-DCONTROL_CENTER_ROWS)
        compile_sources+=("$source_root/Preferences/ApplicationIcons.swift")
    fi
    if [ "$label" = fixed ]; then
        compile_flags+=(-DAPP_ICON_LOADER_TESTS -DCONTROL_CENTER_FEATURE)
    fi
    xcrun swiftc "${compile_flags[@]}" -target "$TARGET" -sdk "$SDK" \
        -I "$source_root/Interfaces" -F "$WORK/frameworks" \
        -import-objc-header "$ROOT/Tests/SettingsConstructionFixture.h" \
        "${compile_sources[@]}" \
        "$ROOT/Tests/SettingsConstructionApp.swift" \
        -Xlinker -rpath -Xlinker @executable_path/Frameworks \
        -o "$app/SettingsConstruction"
    codesign --force --sign - "$app"
    xcrun simctl install "$DEVICE" "$app"
    python3 - "$DEVICE" "$bundle" "$mode" "$marker" "$RESULTS" <<'PY'
import subprocess, sys
from pathlib import Path
p = subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
                    sys.argv[1], sys.argv[2], sys.argv[3]],
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
print(p.stdout, flush=True)
print('simctl launch exit:', p.returncode, flush=True)
# simctl reports transport success, not the app's exit status. Every case
# still requires its own exact terminal assertion/completion marker.
if p.returncode or sys.argv[4] not in p.stdout:
    # This is CI-harness evidence only, collected before the disposable
    # simulator is deleted. Never weaken the exact-marker failure gate.
    roots = [Path.home() / 'Library/Logs/DiagnosticReports',
             Path.home() / 'Library/Developer/CoreSimulator/Devices' / sys.argv[1] /
             'data/Library/Logs/CrashReporter']
    reports = [path for root in roots for path in root.glob('SettingsConstruction*') if path.is_file()]
    for path in sorted(reports, key=lambda item: item.stat().st_mtime, reverse=True)[:2]:
        print('SettingsConstruction crash report:', path.name, flush=True)
        print(path.read_text(errors='replace')[:24000], flush=True)
    try:
        logs = subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], 'log', 'show',
                               '--last', '3m', '--style', 'compact', '--predicate',
                               'process == "SettingsConstruction"'], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, timeout=30)
        print(logs.stdout[-24000:], flush=True)
    except subprocess.TimeoutExpired:
        print('CI-only SettingsConstruction log read timed out', flush=True)
    raise SystemExit('Constructor test failed: missing verified completion marker / nonzero exit')
with open(sys.argv[5], 'a') as f:
    f.write(p.stdout + '\n')
PY
}
run_case "$OLD" baseline --expect-legacy-failure BASELINE_EXPECTED_FAILURE
run_case "$STABLE" accepted --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: root must link to 主屏幕的手势'
run_case "$APP_OLD" app-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: unimplemented actions must not be exposed'
run_case "$ICON_OLD" icon-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: App picker icon missing'
run_case "$CC_OLD" control-center-baseline --expect-fixed 'SETTINGS_CONSTRUCTION_FAIL: Control Center action row missing'
run_case "$ROOT" fixed --expect-fixed FIXED_CONSTRUCTION_PASS
bash "$ROOT/ci/native-startup-smoke.sh" "$DEVICE"
