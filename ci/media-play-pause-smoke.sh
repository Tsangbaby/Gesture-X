#!/bin/bash
# Actual Swift loader/preferences plus an independent C test dylib; no player calls.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
[[ "$(uname -s)" == Darwin ]]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-media.XXXXXX")"
BASELINE=1e2b7ef11a5f743b8db122c02d9a5478d2f20bfa
RESULTS="$RUNNER_TEMP/MEDIA_PLAY_PAUSE_TESTS.txt"
trap 'rm -rf -- "$WORK"' EXIT
printf 'MEDIA_PLAY_PAUSE_SOURCE_COMMIT: %s\n' "$(git -C "$ROOT" rev-parse HEAD)" > "$RESULTS"
printf '%s\n' 'Boundary: actual production Swift/preferences/PrivateAPI/LockAction and dlopen/dlsym; C/Objective-C service fixtures only, NOT iOS MediaRemote service acceptance or handset playback.' >> "$RESULTS"
xcrun swiftc --version >> "$RESULTS"
git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
git -C "$ROOT" show "$BASELINE:Shared/Preferences.swift" > "$WORK/LegacyPreferences.swift"
python3 - "$ROOT" "$WORK" "$RESULTS" <<'PY'
import hashlib, json, sys
from pathlib import Path
root, work = map(Path, sys.argv[1:3])
frozen = json.loads((root / 'Tests/media_play_pause_baseline.json').read_text())
assert hashlib.sha256((work / 'LegacyPreferences.swift').read_bytes()).hexdigest() == frozen['frozen']['Shared/Preferences.swift']
for path, bindings in [
    ('Sources/LockAction.swift', [(b'"SBLockScreenManager"', b'"TLMediaLockManagerFixture"', 1)]),
    ('Sources/MediaPlayPauseAction.swift', [(b'"/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"',
      ('"' + str(work / 'MediaRemoteFixture.dylib') + '"').encode(), 1)]),
]:
    original = (root / path).read_bytes()
    text = original
    for old, new, count in bindings:
        assert original.count(old) == count, (path, old)
        assert new not in original, path
        text = text.replace(old, new)
    restored = text
    for old, new, count in bindings:
        assert restored.count(new) == count, path
        restored = restored.replace(new, old)
    assert restored == original, path
    (work / Path(path).name).write_bytes(text)
with open(sys.argv[3], 'a') as stream:
    stream.write('MEDIA_PLAY_PAUSE_BASELINE_BYTES_VERIFIED: exact accepted 0.1.9 preferences\n')
    stream.write('MEDIA_PLAY_PAUSE_FIXTURE_REBINDING_VERIFIED: only one OS class lookup and one fixed loader path; inverse copies equal production bytes\n')
PY
xcrun swiftc -parse-as-library -swift-version 5 -DMEDIA_PLAY_PAUSE_BASELINE \
    "$WORK/LegacyPreferences.swift" "$ROOT/Tests/MediaPlayPauseRuntimeTests.swift" -o "$WORK/baseline-tests"
python3 - "$WORK/baseline-tests" "$RESULTS" <<'PY'
import subprocess, sys
p = subprocess.run([sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
expected = 'MEDIA_PLAY_PAUSE_RUNTIME_FAIL: persisted media action is unavailable'
if p.returncode != 1 or p.stdout.splitlines() != [expected]:
    raise SystemExit('Expected exact baseline behavior assertion; compile/crash/harness failure is NOT RED')
with open(sys.argv[2], 'a') as stream:
    stream.write(p.stdout + 'MEDIA_PLAY_PAUSE_BASELINE_EXPECTED_FAILURE: unmodified 0.1.9 does not decode the persisted media action\n')
PY
xcrun clang -dynamiclib -framework Foundation "$ROOT/Tests/MediaRemoteFixture.m" -o "$WORK/working.dylib"
xcrun clang -dynamiclib -framework Foundation -DMEDIA_REMOTE_MISSING_SYMBOL "$ROOT/Tests/MediaRemoteFixture.m" -o "$WORK/missing-symbol.dylib"
xcrun swiftc -parse-as-library -swift-version 5 \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/LockAction.swift" "$WORK/MediaPlayPauseAction.swift" \
    "$ROOT/Tests/MediaPlayPauseRuntimeTests.swift" -o "$WORK/current-tests"
for mode in --missing-library --missing-symbol --working; do
    rm -f -- "$WORK/MediaRemoteFixture.dylib"
    python3 - "$WORK/current-tests" "$RESULTS" "$mode" "$WORK" <<'PY'
import re, subprocess, sys
from pathlib import Path
work = Path(sys.argv[4])
p = subprocess.run([sys.argv[1], sys.argv[3], str(work / 'MediaRemoteFixture.dylib'),
                    str(work / 'working.dylib'), str(work / 'missing-symbol.dylib')],
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
print(p.stdout, end='', flush=True)
pattern = (r'MEDIA_PLAY_PAUSE_RUNTIME_PASS: [1-9][0-9]* assertions; mode=' + re.escape(sys.argv[3]) +
           r'; actual Swift/C loader fixture, NOT handset playback proof')
if p.returncode or len(p.stdout.splitlines()) != 1 or re.fullmatch(pattern, p.stdout.splitlines()[0]) is None:
    raise SystemExit('Media Swift execution failed: nonzero/missing/wrong/duplicate/extra marker')
with open(sys.argv[2], 'a') as stream:
    stream.write(p.stdout)
PY
done
printf '%s\n' 'MEDIA_PLAY_PAUSE_SWIFT_EXECUTION_PASS: baseline behavior RED; missing library/symbol cache, native refusal/nonzero/exact command/lock/thread and seven-action preferences GREEN; system integration unverified' >> "$RESULTS"
