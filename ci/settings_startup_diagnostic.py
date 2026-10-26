#!/usr/bin/env python3
"""One-shot cloud-Mac startup investigation; never replaces package/test gates."""
import argparse
import hashlib
import json
import os
import platform
import re
import signal
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PHASES = {
    'control': ('native-constructor', 'main-entered', 'before-UIApplicationMain',
                'didFinishLaunching', 'control-ui-attached', 'control-pass'),
    'baseline': ('native-constructor', 'main-entered', 'before-UIApplicationMain',
                 'didFinishLaunching', 'before-legacy-checks', 'before-TLConstructDetail',
                 'after-TLConstructDetail', 'baseline-expected-failure'),
}
PREFIX = 'SETTINGS_STARTUP_EVENT: '
BASELINE = '72826b2a558b03e20a7dd5e98047dfdecc489202'
FROZEN_BASELINE = {
    'Shared/Preferences.swift': '227f50e3b867615426e4860f01b515a71c81844d64522b3269309ba6651aada5',
    'Preferences/SettingsController.swift': '5b1680b157b2a8c827ee42c52ab45c66b8ed057b257288705a46499b247164a6',
    'Interfaces/TapLockPreferencesHost/PSViewController.h': '4d365e79c73719391823d1606bfabb2f2c8cdcd4f709f9ff84c0a4690dc2e35b',
    'Interfaces/TapLockPreferencesHost/module.modulemap': 'a8eaa6b0f7925ffa1ec469469e2f694abc02448ca89cfd1d5cbe2e4d4257b303',
}
FROZEN_HARNESS = '43a8f1b497f7524f1196cc3ac0bdd4d240449a265f945d2e3530983be80a40d6'

# Only compiled into disposable diagnostic Apps; never a tracked C production source.
# POSIX writes are independent of Swift/Foundation buffering and use the App sandbox.
NATIVE_PROBE = r'''
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned int sequence;
static int hexidentity(const char *s, size_t n) {
    return s && strlen(s) == n && strspn(s, "0123456789abcdef") == n;
}
void TLSDRecord(const char *phase) {
    const char *source = getenv("SETTINGS_DIAGNOSTIC_SOURCE");
    const char *token = getenv("SETTINGS_DIAGNOSTIC_TOKEN");
    if (!hexidentity(source, 40) || !hexidentity(token, 32)) {
        const char *error = "SETTINGS_STARTUP_PROBE_ERROR: invalid identity\n";
        write(STDERR_FILENO, error, strlen(error)); return;
    }
    if (!phase || strlen(phase) > 80 || strspn(phase,
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-") != strlen(phase)) return;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return;
    char record[768], path[PATH_MAX], directory[PATH_MAX];
    int length = snprintf(record, sizeof(record),
        "{\"schemaVersion\":1,\"source_commit\":\"%s\",\"run_token\":\"%s\","
        "\"seq\":%u,\"phase\":\"%s\",\"pid\":%d,\"monotonic_ns\":%llu}\n",
        source, token, ++sequence, phase, (int)getpid(),
        (unsigned long long)now.tv_sec * 1000000000ULL + (unsigned long long)now.tv_nsec);
    if (length <= 0 || length >= (int)sizeof(record)) return;
    const char *home = getenv("HOME");
    if (home && snprintf(directory, sizeof(directory), "%s/Documents", home) < (int)sizeof(directory) &&
        snprintf(path, sizeof(path), "%s/SettingsStartup.jsonl", directory) < (int)sizeof(path)) {
        mkdir(directory, 0700);
        int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd >= 0) {
            struct stat info;
            if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_size < 32768) {
                write(fd, record, (size_t)length); fsync(fd);
            }
            close(fd);
        }
    }
    char output[850];
    int outlength = snprintf(output, sizeof(output), "SETTINGS_STARTUP_EVENT: %s", record);
    if (outlength > 0 && outlength < (int)sizeof(output)) write(STDOUT_FILENO, output, (size_t)outlength);
}
__attribute__((constructor)) static void startup_checkpoint(void) { TLSDRecord("native-constructor"); }
'''


def owned_events(text, source, token):
    records = []
    for line in text.splitlines():
        row = json.loads(line)
        if (not isinstance(row, dict) or row.get('schemaVersion') != 1 or
                row.get('source_commit') != source or row.get('run_token') != token or
                type(row.get('seq')) is not int or row['seq'] != len(records) + 1 or
                type(row.get('pid')) is not int or row['pid'] <= 0 or
                type(row.get('monotonic_ns')) is not int or row['monotonic_ns'] <= 0 or
                not isinstance(row.get('phase'), str)):
            raise ValueError('unowned or invalid checkpoint')
        if records and (records[0]['pid'] != row['pid'] or
                        row['monotonic_ns'] < records[-1]['monotonic_ns']):
            raise ValueError('checkpoint process or monotonic clock changed')
        records.append(row)
    return records


def observe_case(kind, status, console, ledger, source, token):
    expected = PHASES[kind]
    result: dict = dict(kind=kind, transport_status=status, completed=False,
                  last_owned_phase=None, console_events=[], file_events=[],
                  limit='Missing checkpoints are not proof that the process never started.')
    errors = []
    for key, text in (
        ('console_events', '\n'.join(line[len(PREFIX):] for line in console.splitlines()
                                    if line.startswith(PREFIX))),
        ('file_events', ledger),
    ):
        try:
            result[key] = owned_events(text, source, token)
        except (ValueError, TypeError, KeyError) as error:
            errors.append(key + ': ' + str(error))
    file_phases = [row['phase'] for row in result['file_events']]
    if file_phases and tuple(file_phases) == expected[:len(file_phases)]:
        result['last_owned_phase'] = file_phases[-1]
    if status != 0:
        errors.append('launch transport did not complete successfully')
    if tuple(file_phases) != expected or result['console_events'] != result['file_events']:
        errors.append('console and owned file do not agree on every required phase')
    terminal = (r'^SETTINGS_STARTUP_CONTROL_PASS$' if kind == 'control' else
                r'^BASELINE_EXPECTED_FAILURE: .*initForContentSize:.*$')
    if len(re.findall(terminal, console, re.M)) != 1:
        errors.append('missing or duplicate case-specific completion marker')
    if ('SETTINGS_CONSTRUCTION_FAIL:' in console or 'FIXED_CONSTRUCTION_PASS' in console or
            (kind == 'control' and 'BASELINE_EXPECTED_FAILURE:' in console) or
            (kind == 'baseline' and 'SETTINGS_STARTUP_CONTROL_PASS' in console)):
        errors.append('contradictory completion output')
    result['errors'] = errors
    result['completed'] = not errors
    return result


def instrument_harness(original):
    if hashlib.sha256(original.encode()).hexdigest() != FROZEN_HARNESS:
        raise ValueError('historical harness bytes changed')
    constructor = '            let result = TLConstructDetail(TapLockSettingsController.self, true)\n'
    hunks = [
        ('@main\n', ''),
        ('        print("SETTINGS_CHECKPOINT: didFinishLaunching',
         '        TLSDRecord("didFinishLaunching")\n        print("SETTINGS_CHECKPOINT: didFinishLaunching'),
        ('        let selector = NSSelectorFromString("initForContentSize:")',
         '        TLSDRecord("before-legacy-checks")\n        let selector = NSSelectorFromString("initForContentSize:")'),
        (constructor, '            TLSDRecord("before-TLConstructDetail")\n' + constructor +
         '            TLSDRecord("after-TLConstructDetail")\n'),
        ('            print("BASELINE_EXPECTED_FAILURE:',
         '            TLSDRecord("baseline-expected-failure")\n            print("BASELINE_EXPECTED_FAILURE:'),
    ]
    text = original
    for before, after in hunks:
        if text.count(before) != 1:
            raise ValueError('instrumentation anchor count changed')
        text = text.replace(before, after, 1)
    return text, hunks


class CommandRunner:
    def __init__(self, directory):
        self.directory = directory
        self.directory.mkdir(parents=True, exist_ok=True)

    def run(self, label, argv, timeout=30, env=None) -> dict:
        path = self.directory / (label + '.log')
        if path.exists():
            raise ValueError('refusing repeated command label: ' + label)
        started = time.monotonic()
        status, timed_out = 127, False
        with path.open('wb') as output:
            try:
                proc = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=output,
                                        stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    status = proc.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    timed_out, status = True, 124
                    try:
                        os.killpg(proc.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    try:
                        proc.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                        proc.wait(timeout=3)
            except OSError as error:
                output.write((type(error).__name__ + ': ' + str(error)).encode())
        record = dict(label=label, argv=[str(x) for x in argv], timeout_seconds=timeout,
                      status=status, timed_out=timed_out, elapsed_seconds=time.monotonic() - started,
                      log=str(path))
        with (self.directory / 'commands.jsonl').open('a') as stream:
            stream.write(json.dumps(record) + '\n')
        print('SETTINGS_STARTUP_COMMAND: ' + json.dumps(record), flush=True)
        return dict(record, stdout=path.read_text(errors='replace'))

    def checked(self, label, argv, timeout=30, env=None):
        result = self.run(label, argv, timeout, env)
        if result['status']:
            raise RuntimeError(label + ' failed: ' + str(result['status']) + '\n' + result['stdout'][-6000:])
        return result['stdout'].strip()


def launch_once(runner, kind, device, bundle, mode, env):
    return runner.run(kind + '-launch', ['xcrun', 'simctl', 'launch', '--console',
        '--terminate-running-process', device, bundle, mode], timeout=120, env=env)


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def diagnostic_main_source(delegate):
    return ('import UIKit\nimport Darwin\nTLSDRecord("main-entered")\n'
            'let delegateName = NSStringFromClass(' + delegate + '.self)\n'
            'TLSDRecord("before-UIApplicationMain")\n'
            'exit(UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, delegateName))\n')


def collect_process_evidence(runner, kind, device, bundle, app_container, evidence, since):
    snapshot = runner.run(kind + '-host-processes', ['ps', '-axo', 'pid=,ppid=,stat=,etime=,command='])
    runner.run(kind + '-sim-launchctl', ['xcrun', 'simctl', 'spawn', device, 'launchctl', 'list'], timeout=15)
    executable = 'SettingsConstruction' if kind == 'baseline' else 'SettingsStartupControl'
    expected_path = app_container + '/' + executable if app_container else None
    pids = []
    for line in snapshot['stdout'].splitlines():
        fields = line.strip().split(None, 4)
        if len(fields) == 5 and fields[0].isdigit() and expected_path and (
                fields[4] == expected_path or fields[4].startswith(expected_path + ' ')):
            pids.append(int(fields[0]))
    save_json(evidence / (kind + '-live-pids.json'), dict(executable_path=expected_path, pids=pids,
        limit='An absent live PID does not prove that the process never ran.'))
    for pid in pids[:1]:
        runner.run(kind + '-sample-' + str(pid), ['/usr/bin/sample', str(pid), '2', '1',
                   '-file', str(evidence / (kind + '-stack.txt'))], timeout=12)
    predicate = ('process == "' + executable + '" OR eventMessage CONTAINS "' + bundle + '"')
    runner.run(kind + '-sim-log', ['xcrun', 'simctl', 'spawn', device, 'log', 'show',
               '--last', '3m', '--style', 'compact', '--predicate', predicate], timeout=20)
    roots = [Path.home() / 'Library/Logs/DiagnosticReports',
             Path.home() / 'Library/Developer/CoreSimulator/Devices' / device / 'data/Library/Logs/CrashReporter']
    reports = [p for root in roots for p in root.glob(executable + '*')
               if p.is_file() and p.stat().st_mtime >= since]
    for index, report in enumerate(sorted(reports, key=lambda p: p.stat().st_mtime, reverse=True)[:2]):
        (evidence / (kind + '-crash-' + str(index) + '.txt')).write_text(report.read_text(errors='replace'))


def execute_diagnostic():
    if platform.system() != 'Darwin' or not os.environ.get('RUNNER_TEMP'):
        raise RuntimeError('execute only on the authorized isolated cloud Mac')
    evidence = Path(os.environ['RUNNER_TEMP']) / 'settings-startup-diagnostic'
    work = Path(os.environ['RUNNER_TEMP']) / 'settings-startup-work'
    evidence.mkdir(exist_ok=False)
    work.mkdir(exist_ok=False)
    runner = CommandRunner(evidence)
    source = os.environ.get('GITHUB_SHA', '')
    token = uuid.uuid4().hex
    report: dict = dict(schemaVersion=1, source_commit=source, run_token=token,
        run_id=os.environ.get('GITHUB_RUN_ID'), run_attempt=os.environ.get('GITHUB_RUN_ATTEMPT'),
        boundary='isolated startup observation only; NOT full regression, a fix, package or handset proof',
        baseline_commit=BASELINE, launch_timeout_seconds=120, cases=[], state='preparing')
    save_json(evidence / 'RESULT.json', report)
    device = ''
    try:
        if not re.fullmatch(r'[0-9a-f]{40}', source):
            raise ValueError('missing exact cloud source SHA')
        if runner.checked('head', ['git', 'rev-parse', 'HEAD']) != source:
            raise ValueError('checkout does not match cloud source')
        if runner.checked('worktree', ['git', 'status', '--porcelain']):
            raise ValueError('dirty checkout')
        runner.checked('xcode-version', ['xcodebuild', '-version'])
        sdk = runner.checked('sdk-path', ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'])
        arch = runner.checked('host-arch', ['uname', '-m'])
        target = arch + '-apple-ios15.0-simulator'
        runtimes = json.loads(runner.checked('runtimes', ['xcrun', 'simctl', 'list', 'runtimes', '--json']))
        choices = [r for r in runtimes['runtimes'] if r.get('isAvailable') and r['version'].split('.')[0] == '18']
        if not choices:
            raise RuntimeError('no installed iOS 18 runtime; no OS download permitted')
        runtime = max(choices, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier']
        report.update(runtime=runtime, sdk_path=sdk, target=target)
        device = runner.checked('create-device', ['xcrun', 'simctl', 'create',
            'Settings startup ' + os.environ.get('GITHUB_RUN_ID', token),
            'com.apple.CoreSimulator.SimDeviceType.iPhone-16', runtime])
        report['device'] = device
        save_json(evidence / 'RESULT.json', report)
        runner.checked('boot-device', ['xcrun', 'simctl', 'boot', device])
        runner.checked('boot-status', ['xcrun', 'simctl', 'bootstatus', device, '-b'], timeout=120)
        runner.checked('fetch-baseline', ['git', 'fetch', '--no-tags', '--depth=1', 'origin', BASELINE])
        original = work / 'baseline-source'
        for relative, digest in FROZEN_BASELINE.items():
            runner.checked('source-' + relative.replace('/', '-'), ['git', 'show', BASELINE + ':' + relative])
            # git output is byte-attested below; do not normalize its final newline.
            data = (evidence / ('source-' + relative.replace('/', '-') + '.log')).read_bytes()
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('frozen baseline mismatch: ' + relative)
            path = original / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        harness, hunks = instrument_harness((ROOT / 'Tests/SettingsConstructionApp.swift').read_text())
        (work / 'SettingsConstructionApp.swift').write_text(harness)
        save_json(evidence / 'instrumentation.json', dict(original_harness_sha256=FROZEN_HARNESS,
            baseline_sha256=FROZEN_BASELINE, hunks=hunks,
            deltas='explicit main instead of automatic @main; additive owned checkpoints only'))
        (work / 'probe.c').write_text(NATIVE_PROBE)
        (work / 'ProbeBridge.h').write_text('#include "' + str(ROOT / 'Tests/SettingsConstructionFixture.h') +
            '"\nvoid TLSDRecord(const char * _Nonnull phase);\n')
        runner.checked('compile-probe', ['xcrun', 'clang', '-target', target, '-isysroot', sdk,
            '-c', str(work / 'probe.c'), '-o', str(work / 'probe.o')], timeout=45)
        framework = work / 'frameworks/Preferences.framework'
        framework.mkdir(parents=True)
        runner.checked('compile-fixture', ['xcrun', 'clang', '-target', target, '-isysroot', sdk,
            '-fobjc-arc', '-dynamiclib', str(ROOT / 'Tests/SettingsConstructionFixture.m'),
            '-framework', 'UIKit', '-framework', 'Foundation', '-install_name',
            '@rpath/Preferences.framework/Preferences', '-o', str(framework / 'Preferences')], timeout=45)
        import plistlib
        (framework / 'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='Preferences',
            CFBundleName='Preferences', CFBundleIdentifier='com.tsangbaby.taplock.test-host-fixture',
            CFBundlePackageType='FMWK', CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0')))
        runner.checked('sign-fixture', ['codesign', '--force', '--sign', '-', str(framework)])
        import shutil
        for kind, bundle, executable, delegate, mode in [
            ('control', 'com.tsangbaby.taplock.startup-control', 'SettingsStartupControl', 'SettingsStartupControlApp', '--control'),
            ('baseline', 'com.tsangbaby.taplock.constructor-baseline', 'SettingsConstruction', 'SettingsConstructionApp', '--expect-legacy-failure'),
        ]:
            app = work / (kind + '.app')
            app.mkdir()
            (app / 'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable=executable,
                CFBundleIdentifier=bundle, CFBundleName=executable, CFBundlePackageType='APPL',
                CFBundleVersion='1', CFBundleShortVersionString='1', MinimumOSVersion='15.0',
                LSRequiresIPhoneOS=True, UIDeviceFamily=[1], UILaunchScreen={})))
            source_dir = work / (kind + '-entry')
            source_dir.mkdir()
            entry = source_dir / 'main.swift'
            entry.write_text(diagnostic_main_source(delegate))
            command = ['xcrun', 'swiftc', '-swift-version', '5', '-target', target, '-sdk', sdk,
                '-module-name', executable, '-import-objc-header', str(work / 'ProbeBridge.h'),
                str(entry), str(work / 'probe.o')]
            if kind == 'control':
                command += [str(ROOT / 'Tests/SettingsStartupControl.swift')]
            else:
                (app / 'Frameworks').mkdir()
                shutil.copytree(framework, app / 'Frameworks/Preferences.framework')
                command += ['-I', str(original / 'Interfaces'), '-F', str(work / 'frameworks'),
                    str(original / 'Shared/Preferences.swift'), str(original / 'Preferences/SettingsController.swift'),
                    str(work / 'SettingsConstructionApp.swift'), '-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks']
            command += ['-o', str(app / executable)]
            runner.checked(kind + '-compile', command, timeout=90)
            runner.checked(kind + '-sign', ['codesign', '--force', '--sign', '-', str(app)])
            runner.run(kind + '-load-commands', ['xcrun', 'otool', '-L', str(app / executable)])
            runner.checked(kind + '-install', ['xcrun', 'simctl', 'install', device, str(app)], timeout=45)
            app_path = runner.checked(kind + '-app-container', ['xcrun', 'simctl', 'get_app_container', device, bundle, 'app'])
            data_path = runner.checked(kind + '-data-container', ['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'])
            ledger_path = Path(data_path) / 'Documents/SettingsStartup.jsonl'
            if ledger_path.exists():
                raise ValueError('unexpected pre-existing App checkpoints')
            env = dict(os.environ, SIMCTL_CHILD_SETTINGS_DIAGNOSTIC_SOURCE=source,
                       SIMCTL_CHILD_SETTINGS_DIAGNOSTIC_TOKEN=token)
            report.update(state='launching-' + kind)
            save_json(evidence / 'RESULT.json', report)
            since = time.time()
            launch = launch_once(runner, kind, device, bundle, mode, env)
            ledger = ledger_path.read_text(errors='replace') if ledger_path.is_file() else ''
            (evidence / (kind + '-owned-checkpoints.jsonl')).write_text(ledger)
            observed = observe_case(kind, launch['status'], launch['stdout'], ledger, source, token)
            report['cases'].append(observed)
            print('SETTINGS_STARTUP_OBSERVATION: ' + json.dumps(observed), flush=True)
            save_json(evidence / 'RESULT.json', report)
            collect_process_evidence(runner, kind, device, bundle, app_path, evidence, since)
            runner.run(kind + '-terminate', ['xcrun', 'simctl', 'terminate', device, bundle], timeout=15)
        report['state'] = 'complete'
        report['both_completed'] = all(case['completed'] for case in report['cases'])
        report['conclusion'] = ('isolated_control_and_baseline_completed; previous_full_run_failure_unexplained'
            if report['both_completed'] else 'incomplete_startup; inspect_owned_phases_processes_loader_logs_and_stack')
    except Exception as error:
        report.update(state='blocked', error=type(error).__name__ + ': ' + str(error))
        print('SETTINGS_STARTUP_BLOCKER: ' + report['error'], flush=True)
    finally:
        save_json(evidence / 'RESULT.json', report)
        if device:
            runner.run('final-device-state', ['xcrun', 'simctl', 'list', 'devices', '--json'])
            runner.run('cleanup-shutdown', ['xcrun', 'simctl', 'shutdown', device], timeout=20)
            runner.run('cleanup-delete', ['xcrun', 'simctl', 'delete', device], timeout=20)
        print('SETTINGS_STARTUP_RESULT: ' + json.dumps(report), flush=True)
    return 0 if report.get('both_completed') else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    if not parser.parse_args().execute:
        parser.error('--execute is required; importing never executes cloud work')
    raise SystemExit(execute_diagnostic())
