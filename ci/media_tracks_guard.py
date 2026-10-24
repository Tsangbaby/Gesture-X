#!/usr/bin/env python3
"""Exact source/mode/exit markers for executed track tests, never log keywords."""
import re
import subprocess
import sys
from pathlib import Path

BASELINES = {'--baseline-next': 'nextTrack', '--baseline-previous': 'previousTrack'}
MODES = ('--missing-library', '--missing-symbol', '--working')
SUMMARY = ('MEDIA_TRACKS_SWIFT_EXECUTION_PASS: both 0.1.10 action behavior REDs; '
           'nine-action replacement matrix, commands 4/5/2, nil options, native unsigned-byte result, '
           'missing library/symbol shared cache, lock/thread admission GREEN; handset integration unverified')
ATTESTATIONS = (
    'MEDIA_TRACKS_BASELINE_BYTES_VERIFIED: exact accepted 0.1.10 preferences and unchanged independent C fixture',
    'MEDIA_TRACKS_FIXTURE_REBINDING_VERIFIED: only one OS class lookup and one fixed loader path; inverse copies equal production bytes',
)


def baseline_failure(mode):
    return 'MEDIA_TRACKS_RUNTIME_FAIL: persisted ' + BASELINES[mode] + ' action is unavailable'


def baseline_marker(mode):
    return 'MEDIA_TRACKS_BASELINE_EXPECTED_FAILURE: ' + mode + '; unmodified 0.1.10 rejects ' + BASELINES[mode]


def validate_completed_run(returncode, output, mode):
    lines = output.splitlines()
    if mode in BASELINES:
        if returncode != 1 or lines != [baseline_failure(mode)]:
            raise ValueError('Missing exact accepted-0.1.10 track assertion; compile/crash/transport failure is NOT RED')
        return baseline_marker(mode)
    if mode not in MODES:
        raise ValueError('Unknown media track runtime mode')
    pattern = (r'MEDIA_TRACKS_RUNTIME_PASS: [1-9][0-9]* assertions; mode=' + re.escape(mode) +
               r'; actual Swift/C loader fixture, NOT handset track-change proof')
    if returncode or len(lines) != 1 or re.fullmatch(pattern, lines[0]) is None:
        raise ValueError('Track Swift execution failed: nonzero/missing/wrong/duplicate/extra marker')
    return lines[0]


def validate_completed_suite(output, source):
    lines = output.splitlines()
    sources = [line for line in lines if line.startswith('MEDIA_TRACKS_SOURCE_COMMIT:')]
    if re.fullmatch(r'[0-9a-f]{40}', source) is None or sources != ['MEDIA_TRACKS_SOURCE_COMMIT: ' + source]:
        raise ValueError('Missing, duplicate or wrong exact-source track execution report')
    attestations = [line for line in lines if line.startswith((
        'MEDIA_TRACKS_BASELINE_BYTES_VERIFIED:', 'MEDIA_TRACKS_FIXTURE_REBINDING_VERIFIED:'))]
    if attestations != list(ATTESTATIONS):
        raise ValueError('Missing, duplicate, reordered or wrong track fixture byte attestations')
    terminals = [line for line in lines if line.startswith((
        'MEDIA_TRACKS_RUNTIME_', 'MEDIA_TRACKS_BASELINE_EXPECTED_FAILURE:',
        'MEDIA_TRACKS_BASELINE_UNEXPECTED_SUCCESS', 'MEDIA_TRACKS_SWIFT_EXECUTION_'))]
    expected_prefix = [item for mode in BASELINES for item in (baseline_failure(mode), baseline_marker(mode))]
    if len(terminals) != len(expected_prefix) + len(MODES) + 1 or terminals[:len(expected_prefix)] != expected_prefix:
        raise ValueError('Missing, duplicate, reordered or contradictory track behavioral terminals')
    for mode, marker in zip(MODES, terminals[len(expected_prefix):-1]):
        validate_completed_run(0, marker, mode)
    if terminals[-1] != SUMMARY:
        raise ValueError('Missing exact completed track suite marker')
    return SUMMARY


def main():
    if len(sys.argv) == 4 and sys.argv[1] == '--validate-suite':
        print(validate_completed_suite(Path(sys.argv[2]).read_text(), sys.argv[3]))
        return
    if len(sys.argv) not in (4, 7):
        raise SystemExit('usage: media_tracks_guard.py EXECUTABLE REPORT MODE [TARGET WORKING MISSING]')
    executable, report, mode = sys.argv[1:4]
    if (mode in BASELINES and len(sys.argv) != 4) or (mode in MODES and len(sys.argv) != 7):
        raise SystemExit('Wrong track test mode/fixture arguments')
    if mode not in BASELINES and mode not in MODES:
        raise SystemExit('Unknown track test mode')
    result = subprocess.run([executable, mode] + sys.argv[4:], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=90)
    print(result.stdout, end='', flush=True)
    marker = validate_completed_run(result.returncode, result.stdout, mode)
    with Path(report).open('a', encoding='utf-8') as stream:
        stream.write(result.stdout)
        if mode in BASELINES:
            stream.write(marker + '\n')


if __name__ == '__main__':
    main()
