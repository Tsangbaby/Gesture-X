#!/usr/bin/env python3
"""Require simulator transport AND a unique exact terminal harness completion."""
import re
import subprocess
import sys
from pathlib import Path

NEGATIVE = 'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE: root navigation differs from reference'
MEDIA_NEGATIVE = 'MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE: original play/pause row is disabled'
POSITIVE = re.compile(r'REFERENCE_SETTINGS_UIKIT_PASS: [1-9][0-9]* assertions; .+; simulator fixture boundary only')


def validate_completed_run(returncode, output, mode):
    if mode not in ('--expect-reference-baseline-failure', '--expect-media-baseline-failure', '--expect-reference-fixed'):
        raise ValueError('Unknown reference Settings harness mode')
    if returncode:
        raise ValueError('Reference Settings simulator transport failed')
    lines = output.splitlines()
    terminals = [line for line in lines if line.startswith((
        'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE:',
        'MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE:',
        'REFERENCE_SETTINGS_UIKIT_PASS:', 'REFERENCE_SETTINGS_FAIL:'))]
    if len(terminals) != 1:
        raise ValueError('Missing, duplicate, or contradictory reference Settings terminal marker')
    marker = terminals[0]
    if mode == '--expect-reference-baseline-failure':
        if marker != NEGATIVE:
            raise ValueError('Missing exact frozen-0.1.8 root-navigation behavioral RED')
    elif mode == '--expect-media-baseline-failure':
        if marker != MEDIA_NEGATIVE:
            raise ValueError('Missing exact frozen-0.1.9 disabled-media behavioral RED')
    elif POSITIVE.fullmatch(marker) is None:
        raise ValueError('Missing exact nonzero-assertion current Settings completion')
    return marker


def validate_completed_suite(output, source):
    lines = output.splitlines()
    sources = [line for line in lines if line.startswith('REFERENCE_UIKIT_SOURCE_COMMIT:')]
    if re.fullmatch(r'[0-9a-f]{40}', source) is None or sources != ['REFERENCE_UIKIT_SOURCE_COMMIT: ' + source]:
        raise ValueError('Missing, duplicate, or wrong exact-source UIKit report')
    terminals = [line for line in lines if line.startswith((
        'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE:',
        'MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE:',
        'REFERENCE_SETTINGS_UIKIT_PASS:', 'REFERENCE_SETTINGS_FAIL:'))]
    if len(terminals) != 3 or terminals[:2] != [NEGATIVE, MEDIA_NEGATIVE]:
        raise ValueError('Missing, duplicate, reordered, or contradictory complete-suite terminals')
    return validate_completed_run(0, terminals[2], '--expect-reference-fixed')


def validate_startup_report(output):
    terminals = [line for line in output.splitlines() if line.startswith(('NATIVE_STARTUP_PASS:', 'NATIVE_STARTUP_FAIL:'))]
    if len(terminals) != 1 or re.fullmatch(
            r'NATIVE_STARTUP_PASS: [1-9][0-9]* executed production-startup/hook/attachment checks', terminals[0]) is None:
        raise ValueError('Missing, duplicate, or wrong production startup completion')
    return terminals[0]


def main():
    if len(sys.argv) == 5 and sys.argv[1] == '--validate-suite':
        report, source, startup = sys.argv[2:]
        validate_completed_suite(Path(report).read_text(), source)
        validate_startup_report(Path(startup).read_text())
        print('REFERENCE_SETTINGS_SUITE_PASS: exact-source both behavioral REDs, current UIKit GREEN and production startup executed')
        return
    if len(sys.argv) != 5:
        raise SystemExit('usage: reference_settings_guard.py DEVICE BUNDLE MODE REPORT')
    device, bundle, mode, report = sys.argv[1:]
    result = subprocess.run([
        'xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
        device, bundle, mode], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120)
    print(result.stdout, flush=True)
    print('reference simctl launch exit:', result.returncode, flush=True)
    marker = validate_completed_run(result.returncode, result.stdout, mode)
    with Path(report).open('a', encoding='utf-8') as stream:
        stream.write('Mode: ' + mode + '\n' + result.stdout + '\nVerified terminal: ' + marker + '\n')


if __name__ == '__main__':
    main()
