#!/usr/bin/env python3
"""Narrow functional candidate staging; formal metadata/baselines stay byte-exact."""
import argparse
import hashlib
import io
import json
import plistlib
import re
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '08bdc7823db6d68ef7a438234439364569c1265c'
VERSION = '0.1.13+bottomfix1'
SAMPLE = 'Sources/BottomGestureSession.swift'
BASE_SHA256 = '2bb82aad5909640cac7c2aaf751288d53f1b9a433e311460aacd90c1cf98efaa'
BEFORE = '''              let container = objectIvar(deck, "_tongueContainer") as? UIView,
              let recognizer = edgeRecognizer(in: deck),
              recognizer === gesture, recognizer.view != nil,
'''
AFTER = '''              let recognizer = edgeRecognizer(in: deck), recognizer === gesture,
              let container = recognizer.view,
'''
ALLOWED = {
    SAMPLE, 'Tests/BottomGestureNativeApp.swift', 'Tests/test_bottom_gesture_native.py',
    'Tests/test_bottom_sample_fix.py', 'ci/bottom_sample_fix.py',
    'ci/bottom-sample-fix-smoke.sh', 'ci/bottom-sample-fix-build.sh',
    '.github/workflows/bottom-sample-fix.yml',
}
EXPECTED_RED = 'BOTTOM_GESTURE_NATIVE_FAIL: missing display container must not block attached recognizer sampling'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def restore_sample(text):
    assert text.count(AFTER) == 1, 'sample-view inverse anchor'
    original = text.replace(AFTER, BEFORE, 1)
    assert digest(original.encode()) == BASE_SHA256, 'unrelated sample-view runtime drift'
    return original


def validate_red(status, text):
    terminal = [line for line in text.splitlines()
                if 'BOTTOM_GESTURE_NATIVE_FAIL' in line or 'BOTTOM_GESTURE_NATIVE_PASS' in line]
    assert status == 1 and terminal == [EXPECTED_RED], ('Expected behavioral RED missing or incomplete', status, terminal)


def verify_scope() -> dict[str, object]:
    head = git('rev-parse', 'HEAD').decode().strip()
    assert re.fullmatch('[0-9a-f]{40}', head)
    changed = set(git('diff', '--name-only', BASE).decode().splitlines())
    changed |= set(git('ls-files', '--others', '--exclude-standard').decode().splitlines())
    assert changed == ALLOWED, ('Unexpected functional candidate paths', sorted(changed ^ ALLOWED))
    current = (ROOT / SAMPLE).read_bytes().decode()
    restored = restore_sample(current)
    assert restored.encode() == git('show', BASE + ':' + SAMPLE)
    production = [p for p in changed if p.startswith(('Sources/', 'Shared/', 'Preferences/', 'Interfaces/', 'layout/'))]
    assert production == [SAMPLE], production
    return dict(source_repository='Tsangbaby/Gesture-X', source_sha=head, production_base=BASE,
                mode='functional_verification_candidate', package_version=VERSION,
                changed_paths=sorted(changed), production_paths=production,
                exact_inverse_verified=True, diagnostic_instrumentation=False,
                full_simulator_regression='unresolved; not executed in this candidate lane',
                focused_uikit_regression='separate required RED/GREEN logs', device_tested=False)


def archive(stage, source_sha):
    assert source_sha == git('rev-parse', 'HEAD').decode().strip()
    assert not git('status', '--porcelain').strip(), 'Committed clean source required'
    scope = verify_scope()
    stage.mkdir(parents=True, exist_ok=False)
    with tarfile.open(fileobj=io.BytesIO(git('archive', 'HEAD'))) as source:
        for member in source.getmembers():
            path = Path(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            assert member.isdir() or member.isfile(), 'Unexpected source symlink/hardlink'
        source.extractall(stage, filter='data')
    return scope


def prepare(stage, source_sha):
    scope = archive(stage, source_sha)
    control = stage / 'control'
    text = control.read_text()
    assert text.count('Version: 0.1.13\n') == 1
    control.write_text(text.replace('Version: 0.1.13\n', 'Version: ' + VERSION + '\n', 1))
    info = stage / 'Preferences/Resources/Info.plist'
    values = plistlib.loads(info.read_bytes())
    assert values['CFBundleVersion'] == values['CFBundleShortVersionString'] == '0.1.13'
    values['CFBundleVersion'] = values['CFBundleShortVersionString'] = VERSION
    info.write_bytes(plistlib.dumps(values, sort_keys=False))
    for name in (SAMPLE, 'Sources/BottomGestureNative.swift', 'Sources/BottomActions.swift',
                 'Sources/HomeDoubleTap.swift', 'Makefile', 'Preferences/Makefile'):
        assert (stage / name).read_bytes() == git('show', source_sha + ':' + name), name
    scope.update(generated_metadata=['control', 'Preferences/Resources/Info.plist'],
                 generated_metadata_sha256={p: digest((stage / p).read_bytes())
                                            for p in ('control', 'Preferences/Resources/Info.plist')})
    return scope


def red_fixture(stage, source_sha):
    scope = archive(stage, source_sha)
    path = stage / SAMPLE
    path.write_text(restore_sample(path.read_bytes().decode()))
    # Keep the existing compiler, lifecycle and timeout intact. Replace only its
    # terminal-output verdict so the exact baseline behavior can be expected RED.
    runner = stage / 'ci/bottom-gesture-native-smoke.sh'
    text = runner.read_text()
    before = 'bash "$0" --verify-output "$STATUS" "$WORK/console.txt"'
    after = 'python3 -B "$ROOT/ci/bottom_sample_fix.py" validate-red --status "$STATUS" --log "$WORK/console.txt"'
    assert text.count(before) == 1
    runner.write_text(text.replace(before, after, 1))
    assert digest(path.read_bytes()) == BASE_SHA256
    scope.update(fixture='only acquisition hunk restored to frozen baseline; new test unchanged',
                 baseline_sample_sha256=BASE_SHA256,
                 expected_red=EXPECTED_RED, expected_child_transport=1)
    return scope


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('verify-source', 'prepare', 'red-fixture', 'validate-red'))
    parser.add_argument('--source-sha')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--status', type=int)
    args = parser.parse_args()
    if args.mode == 'validate-red':
        validate_red(args.status, args.log.read_text(errors='replace'))
        print('BOTTOM_SAMPLE_EXPECTED_RED_ACCEPTED: missing display container')
    elif args.mode == 'verify-source':
        print(json.dumps(verify_scope(), indent=2))
    else:
        operation = prepare if args.mode == 'prepare' else red_fixture
        print(json.dumps(operation(args.output, args.source_sha), indent=2))


if __name__ == '__main__':
    main()
