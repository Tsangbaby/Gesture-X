#!/usr/bin/env python3
"""Fail-closed exact-source native report protocol; never handset evidence."""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

BASELINE = '925df18141606b75f71c77ddd998ad2baa237efe'
BASELINE_FAILURE = 'FLASHLIGHT_RUNTIME_FAIL: persisted flashlight action is unavailable'
BASELINE_MARKER = ('FLASHLIGHT_BASELINE_EXPECTED_FAILURE: --baseline; '
                   'unmodified 0.1.11 rejects flashlight')
ATTESTATIONS = (
    'FLASHLIGHT_BASELINE_BYTES_VERIFIED: exact 0.1.11 preferences from ' + BASELINE,
    'FLASHLIGHT_FIXTURE_REBINDING_VERIFIED: exactly two class-name literals; inverse copies equal production bytes',
)
SUMMARY = ('FLASHLIGHT_SWIFT_EXECUTION_PASS: 0.1.11 flashlight preference behavior RED; '
           'current production preference/ABI/branch/thread fixtures GREEN; hardware effect unverified')
CURRENT_PATTERN = (r'FLASHLIGHT_RUNTIME_PASS: [1-9][0-9]* assertions; mode=--current; '
                   r'actual production Swift/Objective-C fixtures, NOT hardware effect proof')


def validate_completed_run(returncode, output, mode):
    if mode == '--baseline':
        if returncode != 1 or output != BASELINE_FAILURE + '\n':
            raise ValueError('Missing precise 0.1.11 behavior assertion; compiler/crash/transport failure is not RED')
        return BASELINE_MARKER
    if mode != '--current' or returncode != 0 or re.fullmatch(CURRENT_PATTERN + r'\n', output) is None:
        raise ValueError('Missing exact successful current flashlight execution')
    return output[:-1]


def _records(output):
    # Do not strip whitespace, translate CRLF, or filter prefixes: every byte is contractual.
    if not output.endswith('\n') or '\r' in output:
        raise ValueError('Report requires exact newline-terminated records')
    return output[:-1].split('\n')


def _header(source):
    if re.fullmatch(r'[0-9a-f]{40}', source) is None:
        raise ValueError('Expected full lowercase 40-character source commit')
    return ['FLASHLIGHT_SOURCE_COMMIT: ' + source, *ATTESTATIONS]


def _validate_prefix(output, stage, source=None):
    lines = _records(output)
    if source is None:
        match = re.fullmatch(r'FLASHLIGHT_SOURCE_COMMIT: ([0-9a-f]{40})', lines[0])
        if match is None:
            raise ValueError('Missing exact source attestation')
        source = match.group(1)
    expected = _header(source)
    if stage >= 1:
        expected.extend((BASELINE_FAILURE, BASELINE_MARKER))
    if stage >= 2:
        if len(lines) < 6:
            raise ValueError('Missing current native completion')
        validate_completed_run(0, lines[5] + '\n', '--current')
        expected.append(lines[5])
    if stage == 3:
        expected.append(SUMMARY)
    if lines != expected:
        raise ValueError('Missing, extra, duplicate, mixed, reordered or wrong-source flashlight records')
    return source


def validate_completed_suite(output, source):
    _validate_prefix(output, 3, source)
    return SUMMARY


def run_and_record(executable, report, mode):
    if mode not in ('--baseline', '--current'):
        raise ValueError('Unknown flashlight mode')
    path = Path(report)
    # Read bytes instead of universal-newline text mode to reject CRLF poisoning.
    before = path.read_bytes().decode('utf-8')
    stage = 0 if mode == '--baseline' else 1
    source = _validate_prefix(before, stage)
    result = subprocess.run([str(executable), mode], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=90)
    output = result.stdout.decode('utf-8')
    marker = validate_completed_run(result.returncode, output, mode)
    addition = output + (marker + '\n' if mode == '--baseline' else '')
    after = before + addition
    _validate_prefix(after, stage + 1, source)
    if path.read_bytes() != before.encode('utf-8'):
        raise ValueError('Report changed while executing native child')
    with path.open('ab') as stream:
        stream.write(addition.encode('utf-8'))
    print(output, end='', flush=True)


def complete_suite(report, source):
    path = Path(report)
    before = path.read_bytes().decode('utf-8')
    _validate_prefix(before, 2, source)
    after = before + SUMMARY + '\n'
    validate_completed_suite(after, source)
    with path.open('ab') as stream:
        stream.write((SUMMARY + '\n').encode('utf-8'))
    return SUMMARY


def rebind_source(raw, original, replacement):
    if not original or not replacement or raw.count(original) != 1 or replacement in raw:
        raise ValueError('Fixture rebinding requires exactly one unambiguous original literal')
    rebound = raw.replace(original, replacement)
    if rebound.count(replacement) != 1 or rebound.replace(replacement, original) != raw:
        raise ValueError('Inverse fixture rebinding does not restore exact production bytes')
    return rebound


def verified_baseline_preferences(root, raw):
    frozen = json.loads((Path(root) / 'Tests/flashlight_baseline.json').read_bytes())
    if frozen.get('baseline') != BASELINE:
        raise ValueError('History-owned flashlight baseline identity differs')
    digest = frozen.get('frozen', {}).get('Shared/Preferences.swift')
    if not isinstance(digest, str) or hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError('Baseline preferences differ from history-owned frozen bytes')
    return raw


def prepare_sources(root, work, report, source):
    root, work, report = Path(root), Path(work), Path(report)
    # All native compile inputs and the attestation writer must be committed:
    # a correct HEAD label on modified source is not exact-source evidence.
    inputs = ('Shared/Preferences.swift', 'Sources/PrivateAPI.swift', 'Sources/LockAction.swift',
              'Sources/FlashlightAction.swift', 'Tests/FlashlightRuntimeTests.swift',
              'Tests/flashlight_baseline.json', 'ci/flashlight-smoke.sh', 'ci/flashlight_guard.py')
    head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).rstrip('\n')
    _header(source)
    if head != source:
        raise ValueError('Requested source does not equal checked-out HEAD')
    for relative in inputs:
        committed = subprocess.check_output(['git', '-C', str(root), 'show', source + ':' + relative])
        if committed != (root / relative).read_bytes():
            raise ValueError('Native compile/protocol input differs from source commit: ' + relative)
    baseline = subprocess.check_output(['git', '-C', str(root), 'show', BASELINE + ':Shared/Preferences.swift'])
    (work / 'LegacyPreferences.swift').write_bytes(verified_baseline_preferences(root, baseline))
    for relative, original, replacement in (
        ('Sources/LockAction.swift', b'"SBLockScreenManager"', b'"TLFlashlightLockManagerFixture"'),
        ('Sources/FlashlightAction.swift', b'"SBUIFlashlightController"', b'"TLFlashlightControllerFixture"'),
    ):
        raw = (root / relative).read_bytes()
        (work / Path(relative).name).write_bytes(rebind_source(raw, original, replacement))
    report.write_bytes(('\n'.join(_header(source)) + '\n').encode('utf-8'))


def main():
    if len(sys.argv) == 6 and sys.argv[1] == '--prepare-sources':
        prepare_sources(*sys.argv[2:])
        return
    if len(sys.argv) == 4 and sys.argv[1] in ('--validate-suite', '--complete-suite'):
        operation, report, source = sys.argv[1:]
        if operation == '--complete-suite':
            print(complete_suite(report, source))
        else:
            print(validate_completed_suite(Path(report).read_bytes().decode('utf-8'), source))
        return
    if len(sys.argv) == 4:
        run_and_record(*sys.argv[1:])
        return
    raise ValueError('usage: flashlight_guard.py EXECUTABLE REPORT --baseline|--current; '
                     'or --validate-suite|--complete-suite REPORT SOURCE_SHA')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, UnicodeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
