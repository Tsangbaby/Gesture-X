#!/usr/bin/env python3
"""Exact-source diagnostic staging; formal metadata and build lane stay untouched."""
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
VERSION = '0.1.13+bottomdiag1'
RUNTIME = ('Sources/BottomGestureNative.swift', 'Sources/BottomGestureSession.swift')
ALLOWED = set(RUNTIME) | {
    'Tests/test_bottom_diagnostic.py', 'Tests/test_bottom_gesture_native.py',
    'Tests/BottomDiagnosticRuntimeTests.swift', 'Tests/bottom_diagnostic_inverse.json',
    'ci/bottom_diagnostic.py', 'ci/bottom-diagnostic-runtime-smoke.sh',
    'ci/bottom-diagnostic-build.sh', '.github/workflows/bottom-diagnostic.yml',
}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def restore(relative, text):
    manifest = json.loads((ROOT / 'Tests/bottom_diagnostic_inverse.json').read_text())
    record = manifest['files'][relative]
    assert manifest['base'] == BASE
    # Full, uniquely anchored diagnostic hunks, never blanket path exemptions.
    for edit in reversed(record['hunks']):
        assert text.count(edit['after']) == 1, ('diagnostic inverse anchor', relative)
        text = text.replace(edit['after'], edit['before'], 1)
    assert digest(text.encode()) == record['base_sha256'], ('non-diagnostic runtime drift', relative)
    return text


def verify_scope():
    head = git('rev-parse', 'HEAD').decode().strip()
    changed = set(git('diff', '--name-only', BASE, 'HEAD').decode().splitlines())
    changed |= set(git('diff', '--name-only').decode().splitlines())
    changed |= set(git('ls-files', '--others', '--exclude-standard').decode().splitlines())
    assert changed <= ALLOWED, ('out of diagnostic scope', sorted(changed - ALLOWED))
    for path in RUNTIME:
        restored = restore(path, (ROOT / path).read_text())
        assert restored.encode() == git('show', BASE + ':' + path), path
    for path in ('Makefile', 'control', 'Preferences/Resources/Info.plist', '.github/workflows/build.yml',
                 '.github/workflows/package-recovery.yml', 'Sources/BottomActions.swift',
                 'Sources/NativeHook.swift', 'Sources/HomeDoubleTap.swift', 'Shared/BottomGestureGeometry.swift',
                 'Shared/BottomGesturePreferences.swift', 'Tests/bottom_swipe_baseline.json',
                 'Tests/bottom_swipe_baseline.py'):
        assert (ROOT / path).read_bytes() == git('show', BASE + ':' + path), path
    return {'source_sha': head, 'observation_base': BASE, 'diagnostic_only': True,
            'changed_paths': sorted(changed), 'runtime_inverse_verified': True,
            'full_simulator_regression': 'unresolved; not executed in this package lane', 'device_tested': False}


def identity(source_sha, parent):
    assert re.fullmatch('[0-9a-f]{40}', source_sha)
    return ('enum BottomDiagnosticBuild {\n'
            '    static let sourceSHA = ' + json.dumps(source_sha) + '\n'
            '    static let parentDirectory = ' + json.dumps(str(parent)) + '\n}\n')


def extract(output, source_sha):
    output.mkdir(parents=True, exist_ok=False)
    text = (ROOT / RUNTIME[0]).read_text()
    start = '// BOTTOM_DIAGNOSTIC_COLLECTOR_BEGIN'
    end = '// BOTTOM_DIAGNOSTIC_COLLECTOR_END'
    assert text.count(start) == text.count(end) == 1
    collector = text.split(start, 1)[1].split(end, 1)[0]
    (output / 'Collector.swift').write_text('import Foundation\n' + collector)
    (output / 'Build.swift').write_text(identity(source_sha, output))


def prepare(stage, source_sha):
    assert source_sha == git('rev-parse', 'HEAD').decode().strip()
    assert not git('status', '--porcelain').strip(), 'Build requires committed clean source'
    scope = verify_scope()
    stage.mkdir(parents=True, exist_ok=False)
    with tarfile.open(fileobj=io.BytesIO(git('archive', 'HEAD'))) as archive:
        for member in archive.getmembers():
            path = Path(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            assert member.isdir() or member.isfile(), 'No source symlink/hardlink staging'
        archive.extractall(stage, filter='data')
    control = stage / 'control'
    original = control.read_text()
    assert original.count('Version: 0.1.13\n') == original.count('Name: TapLock\n') == 1
    control.write_text(original.replace('Version: 0.1.13\n', 'Version: ' + VERSION + '\n')
                      .replace('Name: TapLock\n', 'Name: TapLock (Bottom Diagnostic 1)\n'))
    info = stage / 'Preferences/Resources/Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    assert metadata['CFBundleVersion'] == metadata['CFBundleShortVersionString'] == '0.1.13'
    metadata['CFBundleVersion'] = metadata['CFBundleShortVersionString'] = VERSION
    info.write_bytes(plistlib.dumps(metadata, sort_keys=False))
    generated = identity(source_sha, '/var/mobile/Library/Logs')
    (stage / 'ci/BottomDiagnosticBuild.swift').write_text(generated)
    scope.update(package_version=VERSION, generated_metadata=['control', 'Preferences/Resources/Info.plist'],
                 build_identity_sha256=digest(generated.encode()),
                 sink='/var/mobile/Library/Logs/TapLockBottomDiag1/report.txt',
                 generated_identity=generated, instrumentation_flag='BOTTOM_GESTURE_DIAGNOSTIC')
    return scope


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['verify-source', 'extract', 'prepare'])
    parser.add_argument('--output', type=Path)
    parser.add_argument('--source-sha')
    args = parser.parse_args()
    if args.mode == 'verify-source':
        print(json.dumps(verify_scope(), ensure_ascii=False, indent=2))
    elif args.mode == 'extract':
        extract(args.output, args.source_sha)
    else:
        print(json.dumps(prepare(args.output, args.source_sha), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
