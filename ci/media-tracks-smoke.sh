#!/bin/bash
# Execute MRMediaRemoteSendCommand ABI through real Swift and an independent C fixture.
set -euo pipefail
: "${RUNNER_TEMP:?Run on the isolated cloud Mac runner}"
[[ "$(uname -s)" == Darwin ]]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$RUNNER_TEMP/taplock-tracks.XXXXXX")"
BASELINE=cd480bfe09c7080b0523e1c73910b8af617edb01
RESULTS="$RUNNER_TEMP/MEDIA_TRACKS_TESTS.txt"
trap 'rm -rf -- "$WORK"' EXIT
printf 'MEDIA_TRACKS_SOURCE_COMMIT: %s\n' "$(git -C "$ROOT" rev-parse HEAD)" > "$RESULTS"
printf '%s\n' 'Boundary: actual production Swift/preferences/PrivateAPI/LockAction/shared loader; independent C/Objective-C fixtures only. NOT iOS MediaRemote/player integration or handset track-change acceptance.' >> "$RESULTS"
xcrun swiftc --version >> "$RESULTS"
git -C "$ROOT" fetch --no-tags --depth=1 origin "$BASELINE"
git -C "$ROOT" show "$BASELINE:Shared/Preferences.swift" > "$WORK/LegacyPreferences.swift"
python3 - "$ROOT" "$WORK" "$RESULTS" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
root, work = map(Path, sys.argv[1:3])
frozen = json.loads((root / 'Tests/media_tracks_baseline.json').read_text())
assert frozen['baseline'] == 'cd480bfe09c7080b0523e1c73910b8af617edb01'
assert hashlib.sha256((work / 'LegacyPreferences.swift').read_bytes()).hexdigest() == frozen['frozen']['Shared/Preferences.swift']
fixture = (root / 'Tests/MediaRemoteFixture.m').read_bytes()
assert fixture == subprocess.check_output(['git', '-C', str(root), 'show', frozen['baseline'] + ':Tests/MediaRemoteFixture.m'])
for path, bindings in [
    ('Sources/LockAction.swift', [(b'"SBLockScreenManager"', b'"TLMediaTrackLockManagerFixture"', 1)]),
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
    stream.write('MEDIA_TRACKS_BASELINE_BYTES_VERIFIED: exact accepted 0.1.10 preferences and unchanged independent C fixture\n')
    stream.write('MEDIA_TRACKS_FIXTURE_REBINDING_VERIFIED: only one OS class lookup and one fixed loader path; inverse copies equal production bytes\n')
PY
xcrun swiftc -parse-as-library -swift-version 5 -DMEDIA_TRACKS_BASELINE \
    "$WORK/LegacyPreferences.swift" "$ROOT/Tests/MediaTracksRuntimeTests.swift" -o "$WORK/baseline-tests"
for mode in --baseline-next --baseline-previous; do
    python3 -B "$ROOT/ci/media_tracks_guard.py" "$WORK/baseline-tests" "$RESULTS" "$mode"
done
xcrun clang -dynamiclib -framework Foundation "$ROOT/Tests/MediaRemoteFixture.m" -o "$WORK/working.dylib"
xcrun clang -dynamiclib -framework Foundation -DMEDIA_REMOTE_MISSING_SYMBOL "$ROOT/Tests/MediaRemoteFixture.m" -o "$WORK/missing-symbol.dylib"
xcrun swiftc -parse-as-library -swift-version 5 \
    "$ROOT/Shared/Preferences.swift" "$ROOT/Sources/PrivateAPI.swift" \
    "$WORK/LockAction.swift" "$WORK/MediaPlayPauseAction.swift" \
    "$ROOT/Tests/MediaTracksRuntimeTests.swift" -o "$WORK/current-tests"
for mode in --missing-library --missing-symbol --working; do
    rm -f -- "$WORK/MediaRemoteFixture.dylib"
    python3 -B "$ROOT/ci/media_tracks_guard.py" "$WORK/current-tests" "$RESULTS" "$mode" \
        "$WORK/MediaRemoteFixture.dylib" "$WORK/working.dylib" "$WORK/missing-symbol.dylib"
done
python3 -B - "$ROOT" "$RESULTS" <<'PY'
import runpy, sys
from pathlib import Path
summary = runpy.run_path(str(Path(sys.argv[1]) / 'ci/media_tracks_guard.py'))['SUMMARY']
with Path(sys.argv[2]).open('a') as stream:
    stream.write(summary + '\n')
PY
python3 -B "$ROOT/ci/media_tracks_guard.py" --validate-suite "$RESULTS" "$(git -C "$ROOT" rev-parse HEAD)"
