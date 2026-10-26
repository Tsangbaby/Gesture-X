#!/usr/bin/env python3
"""Stage a diagnostic-only observation of the exact failed bottomfix1 tree."""
import argparse
import hashlib
import io
import json
import plistlib
import re
import runpy
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
inverse = runpy.run_path(str(ROOT / 'Tests/bottom_panel_inverse.py'))
restore, FROZEN = inverse['restore'], inverse['FROZEN']

BASE = 'b606238d93bb71e7caf1c219767aefaad63a0bb7'
VERSION = '0.1.13+bottomfix1.diag1'
COLLECTOR = 'ci/BottomPanelDiagnostic.swift'
ALLOWED = set(FROZEN) | {
    COLLECTOR, 'Tests/BottomGestureNativeApp.swift', 'Tests/BottomPanelDiagnosticRuntimeTests.swift',
    'Tests/test_bottom_panel_diagnostic.py', 'Tests/bottom_panel_inverse.py', 'Tests/bottom_panel_inverse.json',
    'Tests/test_bottom_sample_fix.py', 'Tests/test_bottom_gesture_native.py',
    'Tests/test_bottom_runtime_integration.py', 'Tests/test_bottom_actions.py',
    'ci/bottom_panel_diagnostic.py', 'ci/bottom-panel-diagnostic-smoke.sh',
    'ci/bottom-panel-diagnostic-build.sh', '.github/workflows/bottom-panel-diagnostic.yml',
}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_scope() -> dict[str, object]:
    changed = set(git('diff', '--name-only', BASE).decode().splitlines())
    changed |= set(git('ls-files', '--others', '--exclude-standard').decode().splitlines())
    assert changed == ALLOWED, ('Unexpected observation paths', sorted(changed ^ ALLOWED))
    for path in FROZEN:
        original = restore(path, (ROOT / path).read_bytes().decode())
        assert original.encode() == git('show', BASE + ':' + path), path
    for path in ('Makefile', 'control', 'Preferences/Makefile', 'Preferences/Resources/Info.plist',
                 '.github/workflows/build.yml', '.github/workflows/bottom-sample-fix.yml',
                 '.github/workflows/package-recovery.yml', 'ci/bottom_sample_fix.py',
                 'ci/bottom-gesture-native-smoke.sh', 'Shared/BottomGestureGeometry.swift',
                 'Shared/BottomGesturePreferences.swift', 'Sources/HomeDoubleTap.swift', 'Sources/NativeHook.swift'):
        assert (ROOT / path).read_bytes() == git('show', BASE + ':' + path), path
    sha = git('rev-parse', 'HEAD').decode().strip()
    assert re.fullmatch('[0-9a-f]{40}', sha)
    return dict(source_repository='Tsangbaby/Gesture-X', source_sha=sha,
                observation_base=BASE, mode='diagnostic_only', package_version=VERSION,
                changed_paths=sorted(changed), runtime_inverse_verified=True,
                sink='/var/mobile/Library/Logs/TapLockBottomDiag2/report.txt',
                full_simulator_regression='unresolved; not executed in observation lane', device_tested=False)


def identity(sha, parent):
    assert re.fullmatch('[0-9a-f]{40}', sha)
    return ('enum BottomDiagnosticBuild {\n    static let sourceSHA = ' + json.dumps(sha) +
            '\n    static let parentDirectory = ' + json.dumps(str(parent)) + '\n}\n')


def archive(output, sha):
    assert sha == git('rev-parse', 'HEAD').decode().strip()
    assert not git('status', '--porcelain').strip(), 'Exact committed clean observation required'
    scope = verify_scope()
    output.mkdir(parents=True, exist_ok=False)
    with tarfile.open(fileobj=io.BytesIO(git('archive', 'HEAD'))) as source:
        for member in source.getmembers():
            path = Path(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            assert member.isdir() or member.isfile(), 'Unexpected source link/special member'
        source.extractall(output, filter='data')
    return scope


def replace_once(path, before, after):
    text = path.read_bytes().decode()
    assert text.count(before) == 1, ('Staging anchor', str(path), before)
    path.write_text(text.replace(before, after, 1))


def extract(output, sha):
    output.mkdir(parents=True, exist_ok=False)
    (output / 'Collector.swift').write_bytes((ROOT / COLLECTOR).read_bytes())
    (output / 'Build.swift').write_text(identity(sha, output))
    return dict(source_sha=sha, collector_sha256=digest((output / 'Collector.swift').read_bytes()))


def native(output, sha, enabled):
    scope = archive(output, sha)
    if not enabled:
        for path in FROZEN:
            (output / path).write_text(restore(path, (output / path).read_bytes().decode()))
        scope['native_runtime'] = 'exact uninstrumented observation baseline plus new closed-flow test'
    else:
        (output / 'ci/BottomDiagnosticBuild.swift').write_text(identity(sha, '/var/mobile/Library/Logs'))
        runner = output / 'ci/bottom-gesture-native-smoke.sh'
        replace_once(runner, '-module-name BottomGestureNative',
                     '-DBOTTOM_PANEL_DIAGNOSTIC -DBOTTOM_DIAGNOSTIC_TESTS -module-name BottomGestureNative')
        replace_once(runner, '    "$ROOT/Sources/BottomActions.swift" \\\n',
                     '    "$ROOT/ci/BottomPanelDiagnostic.swift" \\\n    "$ROOT/ci/BottomDiagnosticBuild.swift" \\\n    "$ROOT/Sources/BottomActions.swift" \\\n')
        scope['native_runtime'] = 'instrumented observation; same closed-flow test and unchanged completion protocol'
    return scope


def prepare(output, sha):
    scope = archive(output, sha)
    replace_once(output / 'control', 'Version: 0.1.13\n', 'Version: ' + VERSION + '\n')
    replace_once(output / 'control', 'Name: TapLock\n', 'Name: TapLock (Bottom Diagnostic 2)\n')
    info = output / 'Preferences/Resources/Info.plist'
    values = plistlib.loads(info.read_bytes())
    assert values['CFBundleVersion'] == values['CFBundleShortVersionString'] == '0.1.13'
    values['CFBundleVersion'] = values['CFBundleShortVersionString'] = VERSION
    info.write_bytes(plistlib.dumps(values, sort_keys=False))
    makefile = output / 'Makefile'
    replace_once(makefile, ' Sources/Bootstrap.swift\n',
                 ' Sources/Bootstrap.swift ci/BottomPanelDiagnostic.swift ci/BottomDiagnosticBuild.swift\n')
    replace_once(makefile, '-enable-experimental-feature SymbolLinkageMarkers\n',
                 '-enable-experimental-feature SymbolLinkageMarkers -DBOTTOM_PANEL_DIAGNOSTIC\n')
    (output / 'ci/BottomDiagnosticBuild.swift').write_text(identity(sha, '/var/mobile/Library/Logs'))
    for path in FROZEN:
        assert (output / path).read_bytes() == git('show', sha + ':' + path)
    generated = ['control', 'Preferences/Resources/Info.plist', 'Makefile', 'ci/BottomDiagnosticBuild.swift']
    scope.update(generated_metadata=generated, generated_sha256={p: digest((output / p).read_bytes()) for p in generated},
                 instrumentation_flag='BOTTOM_PANEL_DIAGNOSTIC')
    return scope


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('verify-source', 'extract', 'prepare', 'native-off', 'native-on'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--source-sha')
    args = parser.parse_args()
    if args.mode == 'verify-source':
        result = verify_scope()
    elif args.mode == 'extract':
        result = extract(args.output, args.source_sha)
    elif args.mode == 'prepare':
        result = prepare(args.output, args.source_sha)
    else:
        result = native(args.output, args.source_sha, args.mode == 'native-on')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
