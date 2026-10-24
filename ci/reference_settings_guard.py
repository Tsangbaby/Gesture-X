#!/usr/bin/env python3
"""Require simulator transport AND a unique exact terminal harness completion."""
import re
import subprocess
import sys
from pathlib import Path

NEGATIVE = 'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE: root navigation differs from reference'
MEDIA_NEGATIVE = 'MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE: original play/pause row is disabled'
TRACK_NEGATIVE = 'MEDIA_TRACKS_SETTINGS_BASELINE_EXPECTED_FAILURE: original previous/next rows are disabled'
FLASHLIGHT_NEGATIVE = 'FLASHLIGHT_SETTINGS_BASELINE_EXPECTED_FAILURE: original flashlight row is disabled'
POSITIVE = re.compile(r'REFERENCE_SETTINGS_UIKIT_PASS: [1-9][0-9]* assertions; .+; simulator fixture boundary only')
UI_TERMINAL_FIELDS = (
    'REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE:',
    'MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE:',
    'MEDIA_TRACKS_SETTINGS_BASELINE_EXPECTED_FAILURE:',
    'FLASHLIGHT_SETTINGS_BASELINE_EXPECTED_FAILURE:',
    'REFERENCE_SETTINGS_UIKIT_PASS:', 'REFERENCE_SETTINGS_FAIL:')
STARTUP_TERMINAL_FIELDS = ('NATIVE_STARTUP_PASS:', 'NATIVE_STARTUP_FAIL:')


def validate_completed_run(returncode, output, mode):
    if mode not in ('--expect-reference-baseline-failure', '--expect-media-baseline-failure',
                    '--expect-track-baseline-failure', '--expect-flashlight-baseline-failure',
                    '--expect-reference-fixed'):
        raise ValueError('Unknown reference Settings harness mode')
    if returncode:
        raise ValueError('Reference Settings simulator transport failed')
    terminals = [line for line in output.splitlines()
                 if line.startswith(UI_TERMINAL_FIELDS + STARTUP_TERMINAL_FIELDS)]
    if len(terminals) != 1:
        raise ValueError('Missing, duplicate, or contradictory reference Settings terminal marker')
    marker = terminals[0]
    if mode == '--expect-reference-baseline-failure':
        if marker != NEGATIVE:
            raise ValueError('Missing exact frozen-0.1.8 root-navigation behavioral RED')
    elif mode == '--expect-media-baseline-failure':
        if marker != MEDIA_NEGATIVE:
            raise ValueError('Missing exact frozen-0.1.9 disabled-media behavioral RED')
    elif mode == '--expect-track-baseline-failure':
        if marker != TRACK_NEGATIVE:
            raise ValueError('Missing exact frozen-0.1.10 disabled-tracks behavioral RED')
    elif mode == '--expect-flashlight-baseline-failure':
        if marker != FLASHLIGHT_NEGATIVE:
            raise ValueError('Missing exact frozen-0.1.11 disabled-flashlight behavioral RED')
    elif POSITIVE.fullmatch(marker) is None:
        raise ValueError('Missing exact nonzero-assertion current Settings completion')
    return marker


def validate_completed_suite(output, source, *, media_tracks=False, flashlight=False):
    if flashlight and not media_tracks:
        raise ValueError('Flashlight suite requires the preserved track-baseline gate')
    lines = output.splitlines()
    sources = [line for line in lines if line.startswith('REFERENCE_UIKIT_SOURCE_COMMIT:')]
    if re.fullmatch(r'[0-9a-f]{40}', source) is None or sources != ['REFERENCE_UIKIT_SOURCE_COMMIT: ' + source]:
        raise ValueError('Missing, duplicate, or wrong exact-source UIKit report')
    terminal_fields = UI_TERMINAL_FIELDS + (STARTUP_TERMINAL_FIELDS if flashlight else ())
    terminals = [line for line in lines if line.startswith(terminal_fields)]
    expected = [NEGATIVE, MEDIA_NEGATIVE] + ([TRACK_NEGATIVE] if media_tracks else []) + ([FLASHLIGHT_NEGATIVE] if flashlight else [])
    if len(terminals) != len(expected) + 1 or terminals[:-1] != expected:
        raise ValueError('Missing, duplicate, reordered, or contradictory complete-suite terminals')
    marker = validate_completed_run(0, terminals[-1], '--expect-reference-fixed')
    if flashlight:
        if 'nine single-value replacements' not in marker:
            raise ValueError('Missing current nine-action UIKit replacement matrix')
        modes = ['--expect-reference-baseline-failure', '--expect-media-baseline-failure',
                 '--expect-track-baseline-failure', '--expect-flashlight-baseline-failure',
                 '--expect-reference-fixed']
        # Exact fields, NOT broad REFERENCE_/FLASHLIGHT_ prefixes: baseline-byte
        # and SHA256 attestations are metadata; Verified terminal is a paired
        # writer field, not another harness completion record.
        fields = ('REFERENCE_UIKIT_SOURCE_COMMIT:', 'Mode:', 'Transport exit:',
                  'Verified terminal:') + UI_TERMINAL_FIELDS + STARTUP_TERMINAL_FIELDS
        actual_records = [line for line in lines if line.startswith(fields)]
        expected_records = ['REFERENCE_UIKIT_SOURCE_COMMIT: ' + source]
        for mode, terminal in zip(modes, expected + [marker]):
            expected_records.extend(['Mode: ' + mode, 'Transport exit: 0', terminal,
                                     'Verified terminal: ' + terminal])
        if actual_records != expected_records:
            raise ValueError('Missing, duplicate, reordered, nonzero-transport or unpaired UIKit case records')
    return marker


def validate_startup_report(output, *, exact_checks=None):
    fields = STARTUP_TERMINAL_FIELDS + (UI_TERMINAL_FIELDS if exact_checks is not None else ())
    terminals = [line for line in output.splitlines() if line.startswith(fields)]
    if len(terminals) != 1 or re.fullmatch(
            r'NATIVE_STARTUP_PASS: [1-9][0-9]* executed production-startup/hook/attachment checks', terminals[0]) is None:
        raise ValueError('Missing, duplicate, or wrong production startup completion')
    if exact_checks is not None and terminals[0] != (
            'NATIVE_STARTUP_PASS: ' + str(exact_checks) + ' executed production-startup/hook/attachment checks'):
        raise ValueError('Missing complete ten-check production startup execution')
    return terminals[0]


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == '--validate-suite':
        flags = sys.argv[5:]
        if len(set(flags)) != len(flags) or set(flags) - {'--with-track-baseline', '--with-flashlight-baseline'}:
            raise SystemExit('Unknown reference suite option')
        report, source, startup = sys.argv[2:5]
        media_tracks = '--with-track-baseline' in flags
        flashlight = '--with-flashlight-baseline' in flags
        validate_completed_suite(Path(report).read_text(), source, media_tracks=media_tracks, flashlight=flashlight)
        validate_startup_report(Path(startup).read_text(), exact_checks=10 if flashlight else None)
        reds = 'four' if flashlight else ('three' if media_tracks else 'both')
        print('REFERENCE_SETTINGS_SUITE_PASS: exact-source ' + reds + ' behavioral REDs, current UIKit GREEN and production startup executed')
        return
    if len(sys.argv) != 5:
        raise SystemExit('usage: reference_settings_guard.py DEVICE BUNDLE MODE REPORT; or --validate-suite REPORT SHA STARTUP [--with-track-baseline] [--with-flashlight-baseline]')
    device, bundle, mode, report = sys.argv[1:]
    result = subprocess.run([
        'xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
        device, bundle, mode], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=120)
    print(result.stdout, flush=True)
    print('reference simctl launch exit:', result.returncode, flush=True)
    marker = validate_completed_run(result.returncode, result.stdout, mode)
    with Path(report).open('a', encoding='utf-8') as stream:
        stream.write('Mode: ' + mode + '\nTransport exit: ' + str(result.returncode) + '\n' +
                     result.stdout + '\nVerified terminal: ' + marker + '\n')


if __name__ == '__main__':
    main()
