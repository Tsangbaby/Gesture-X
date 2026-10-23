#!/bin/bash
# Reuse the disposable UIKit simulator booted by settings-construction-smoke.sh.
# Only the system class/Hook installer are fixtures; load the entire tweak graph.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
DEVICE="${1:?Pass the already booted disposable simulator}"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-native.XXXXXX")"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="$(uname -m)-apple-ios15.0-simulator"
APP="$WORK/NativeStartup.app"
LIBS="$APP/Frameworks"
BUNDLE=com.tsangbaby.taplock.native-startup-test
mkdir -p "$LIBS"

xcrun clang -target "$TARGET" -isysroot "$SDK" -fobjc-arc -dynamiclib \
    "$ROOT/Tests/NativeHookFixture.m" -framework Foundation \
    -install_name @rpath/libTapLockHookFixture.dylib -o "$LIBS/libTapLockHookFixture.dylib"
codesign --force --sign - "$LIBS/libTapLockHookFixture.dylib"

# Resolve exactly the files that the Theos tweak target will compile.
SOURCES=()
while IFS= read -r source; do SOURCES+=("$ROOT/$source"); done < <(
    python3 - "$ROOT/Makefile" <<'PY'
import pathlib, sys
lines = [line for line in pathlib.Path(sys.argv[1]).read_text().splitlines()
         if line.startswith('TapLock_FILES = ')]
assert len(lines) == 1
for name in lines[0].split('=', 1)[1].split():
    assert name.endswith('.swift') and '$' not in name
    print(name)
PY
)
test "${#SOURCES[@]}" -gt 0
xcrun swiftc -parse-as-library -swift-version 5 -O -emit-library \
    -target "$TARGET" -sdk "$SDK" -I "$ROOT/Interfaces" \
    -enable-experimental-feature SymbolLinkageMarkers \
    -module-name TapLockNativeStartup "${SOURCES[@]}" \
    "$ROOT/Tests/NativeHookReactivation.swift" \
    -L "$LIBS" -lTapLockHookFixture -Xlinker -dead_strip \
    -Xlinker -install_name -Xlinker @rpath/TapLockStartup.dylib \
    -Xlinker -rpath -Xlinker @loader_path \
    -o "$LIBS/TapLockStartup.dylib"
codesign --force --sign - "$LIBS/TapLockStartup.dylib"

python3 - "$APP/Info.plist" "$BUNDLE" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='NativeStartup', CFBundleIdentifier=sys.argv[2],
        CFBundleName='NativeStartup', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='15.0',
        LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={}), f)
PY
xcrun swiftc -parse-as-library -swift-version 5 -O -target "$TARGET" -sdk "$SDK" \
    -I "$ROOT/Interfaces" -import-objc-header "$ROOT/Tests/NativeHookFixture.h" \
    "$ROOT/Tests/NativeStartupApp.swift" -L "$LIBS" -lTapLockHookFixture \
    -Xlinker -rpath -Xlinker @executable_path/Frameworks -o "$APP/NativeStartup"
codesign --force --sign - "$APP"
xcrun simctl install "$DEVICE" "$APP"
python3 - "$DEVICE" "$BUNDLE" "$RUNNER_TEMP/NATIVE_STARTUP_TESTS.txt" <<'PY'
import subprocess, sys
from pathlib import Path
p = subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
                    sys.argv[1], sys.argv[2]], stdout=subprocess.PIPE,
                   stderr=subprocess.STDOUT, text=True, timeout=120)
print('simctl exit status:', p.returncode, flush=True)
print(p.stdout, flush=True)
if p.returncode or 'NATIVE_STARTUP_PASS:' not in p.stdout:
    # CI-only evidence; retain the hard failure and never retry a product action.
    roots = [Path.home() / 'Library/Logs/DiagnosticReports',
             Path.home() / 'Library/Developer/CoreSimulator/Devices' / sys.argv[1] /
             'data/Library/Logs/CrashReporter']
    reports = [path for root in roots for path in root.glob('NativeStartup*') if path.is_file()]
    for path in sorted(reports, key=lambda item: item.stat().st_mtime, reverse=True)[:2]:
        print('NativeStartup crash report:', path.name, flush=True)
        print(path.read_text(errors='replace')[:24000], flush=True)
    try:
        logs = subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], 'log', 'show',
                               '--last', '2m', '--style', 'compact', '--predicate',
                               'process == "NativeStartup"'], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, timeout=30)
        print(logs.stdout[-18000:], flush=True)
    except subprocess.TimeoutExpired:
        print('CI-only simulator log read timed out', flush=True)
    raise SystemExit('Native startup test failed: no executed completion marker / nonzero exit')
with open(sys.argv[3], 'w') as f:
    f.write(p.stdout)
PY
