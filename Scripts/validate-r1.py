#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""R1/R2 host correctness gates. Artifacts describe this run, not device qualification."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

MINIMUM_LIBRARY_TESTS = 44
MINIMUM_LIBRARY_SUITES = 7
MINIMUM_CLI_TESTS = 5
MINIMUM_CLI_SUITES = 1
MINIMUM_TOTAL_TESTS = MINIMUM_LIBRARY_TESTS + MINIMUM_CLI_TESTS
MINIMUM_TOTAL_SUITES = MINIMUM_LIBRARY_SUITES + MINIMUM_CLI_SUITES
CLI_SUITE_NAME = 'R3/R4 CLI backend policy and deadline boundary regressions'
LIBRARY_SUITE_NAME = 'PackBits Scalar Byte Engine, Incremental Decode and libtiff Interoperability Tests'

PASS_SUMMARY_RE = re.compile(r'Test run with (\d+) tests?(?: in (\d+) suites?)? passed\b')
STARTED_RUN_RE = re.compile(r'Test run started\.')
FAIL_OUTPUT_RE = re.compile(
    r'(?:Test run with \d+ tests?(?: in \d+ suites?)? failed\b'
    r'|✘\s+(?:Test|Suite)\b'
    r'|\brecorded an issue\b'
    r'|Executed \d+ tests?, with [1-9]\d* failures?\b'
    r'|^.*↷.*$'
    r'|\bTest .* skipped\b)',
    re.M,
)


def evaluate_test_summary(stdout, returncode=0, build_system=None):
    matches = [
        (int(m.group(1)), int(m.group(2)) if m.group(2) is not None else None)
        for m in PASS_SUMMARY_RE.finditer(stdout)
    ]
    group_counts = [tests for tests, _ in matches]
    suite_counts = [suites for _, suites in matches if suites is not None]
    started_runs = len(STARTED_RUN_RE.findall(stdout))

    verified = False
    if returncode != 0:
        reason = f'nonzero_exit:{returncode}'
    elif FAIL_OUTPUT_RE.search(stdout):
        reason = 'failure_or_skip_marker'
    elif not group_counts:
        reason = 'missing_pass_summary'
    elif any(count <= 0 for count in group_counts):
        reason = 'zero_test_group'
    elif started_runs and started_runs != len(group_counts):
        reason = f'incomplete_test_runs:{started_runs}!={len(group_counts)}'
    elif 'Suite "' in stdout and (CLI_SUITE_NAME not in stdout or LIBRARY_SUITE_NAME not in stdout):
        reason = 'missing_expected_suite_banner'
    elif len(group_counts) == 1:
        total_tests, total_suites = matches[0]
        if build_system == 'swiftbuild':
            reason = 'swiftbuild_requires_two_test_bundles'
        elif total_tests >= MINIMUM_TOTAL_TESTS and (total_suites is None or total_suites >= MINIMUM_TOTAL_SUITES):
            verified = True
            reason = 'combined_runner_ok'
        else:
            reason = 'combined_below_minimum'
    elif len(group_counts) == 2:
        (small_tests, small_suites), (large_tests, large_suites) = sorted(
            matches, key=lambda pair: (pair[0], pair[1] or 0)
        )
        cli_ok = small_tests >= MINIMUM_CLI_TESTS and (small_suites is None or small_suites >= MINIMUM_CLI_SUITES)
        lib_ok = large_tests >= MINIMUM_LIBRARY_TESTS and (large_suites is None or large_suites >= MINIMUM_LIBRARY_SUITES)
        if cli_ok and lib_ok and (small_tests + large_tests) >= MINIMUM_TOTAL_TESTS:
            verified = True
            reason = 'split_runner_ok'
        else:
            reason = 'split_group_below_minimum'
    else:
        reason = f'unexpected_group_count:{len(group_counts)}'

    return {
        'tests_passed': sum(group_counts),
        'test_groups_passed': group_counts,
        'test_suites_passed': suite_counts,
        'test_summary_verified': verified,
        'test_summary_reason': reason,
    }


def run_summary_self_tests():
    banners = f'◇ Suite "{LIBRARY_SUITE_NAME}" started.\n◇ Suite "{CLI_SUITE_NAME}" started.\n'
    cases = [
        ('combined_49_native', banners + '◇ Test run started.\n✔ Test run with 49 tests in 8 suites passed after 4.3s.\n', 0, 'native', True, 49, [49]),
        ('combined_53_increased', '✔ Test run with 53 tests in 8 suites passed after 4.5s.\n', 0, 'native', True, 53, [53]),
        ('split_44_plus_5_swiftbuild', banners + '◇ Test run started.\n✔ Test run with 44 tests in 7 suites passed after 4.4s.\n◇ Test run started.\n✔ Test run with 5 tests in 1 suite passed after 0.04s.\n', 0, 'swiftbuild', True, 49, [44, 5]),
        ('split_5_plus_44_reversed', banners + '◇ Test run started.\n✔ Test run with 5 tests in 1 suite passed after 0.04s.\n◇ Test run started.\n✔ Test run with 44 tests in 7 suites passed after 4.4s.\n', 0, 'swiftbuild', True, 49, [5, 44]),
        ('split_increased_46_plus_6', '✔ Test run with 46 tests in 7 suites passed after 4.4s.\n✔ Test run with 6 tests in 1 suite passed after 0.05s.\n', 0, 'swiftbuild', True, 52, [46, 6]),
        ('missing_cli_44_only_native', '✔ Test run with 44 tests in 7 suites passed after 4.4s.\n', 0, 'native', False, 44, [44]),
        ('missing_cli_44_only_swiftbuild', '✔ Test run with 44 tests in 7 suites passed after 4.4s.\n', 0, 'swiftbuild', False, 44, [44]),
        ('missing_library_5_only', '✔ Test run with 5 tests in 1 suite passed after 0.04s.\n', 0, 'swiftbuild', False, 5, [5]),
        ('swiftbuild_single_bundle_49_rejected', '✔ Test run with 49 tests in 8 suites passed after 4.4s.\n', 0, 'swiftbuild', False, 49, [49]),
        ('missing_cli_banner_when_suites_logged', f'◇ Suite "{LIBRARY_SUITE_NAME}" started.\n✔ Test run with 49 tests in 8 suites passed after 4.3s.\n', 0, 'native', False, 49, [49]),
        ('combined_below_threshold_48', '✔ Test run with 48 tests in 8 suites passed after 4.3s.\n', 0, 'native', False, 48, [48]),
        ('split_library_below_43_plus_6', '✔ Test run with 43 tests in 7 suites passed after 4.3s.\n✔ Test run with 6 tests in 1 suite passed after 0.04s.\n', 0, 'swiftbuild', False, 49, [43, 6]),
        ('split_cli_below_45_plus_4', '✔ Test run with 45 tests in 7 suites passed after 4.3s.\n✔ Test run with 4 tests in 1 suite passed after 0.04s.\n', 0, 'swiftbuild', False, 49, [45, 4]),
        ('empty_output', '', 0, 'native', False, 0, []),
        ('zero_single_group', '✔ Test run with 0 tests in 0 suites passed after 0.0s.\n', 0, 'native', False, 0, [0]),
        ('zero_second_group', '✔ Test run with 49 tests in 8 suites passed after 4.3s.\n✔ Test run with 0 tests in 0 suites passed after 0.0s.\n', 0, 'swiftbuild', False, 49, [49, 0]),
        ('incomplete_second_bundle_crash', '◇ Test run started.\n✔ Test run with 44 tests in 7 suites passed after 4.4s.\n◇ Test run started.\n', 0, 'swiftbuild', False, 44, [44]),
        ('second_bundle_failed_run', '✔ Test run with 44 tests in 7 suites passed after 4.4s.\n✘ Test run with 5 tests in 1 suite failed after 0.04s.\n', 0, 'swiftbuild', False, 44, [44]),
        ('recorded_issue_marker', '✔ Test run with 44 tests in 7 suites passed after 4.4s.\n✘ Test sample() recorded an issue at File.swift:1:1\n✔ Test run with 5 tests in 1 suite passed after 0.04s.\n', 0, 'swiftbuild', False, 49, [44, 5]),
        ('skipped_test_marker', '✔ Test run with 49 tests in 8 suites passed after 4.4s.\n↷ Test skippedSample() skipped.\n', 0, 'native', False, 49, [49]),
        ('nonzero_exit_despite_summaries', '✔ Test run with 44 tests in 7 suites passed after 4.4s.\n✔ Test run with 5 tests in 1 suite passed after 0.04s.\n', 1, 'swiftbuild', False, 49, [44, 5]),
        ('cli_entry_collision_exit_2', "Test Suite 'All tests' passed.\n\t Executed 0 tests, with 0 failures in 0.000 seconds\nswiftrle-cli: operation failed (exit 2)\n", 2, 'native', False, 0, []),
    ]
    for label, text, code, engine, expected_ok, expected_total, expected_groups in cases:
        actual = evaluate_test_summary(text, returncode=code, build_system=engine)
        if (
            actual['test_summary_verified'] != expected_ok
            or actual['tests_passed'] != expected_total
            or actual['test_groups_passed'] != expected_groups
        ):
            raise AssertionError(f'Summary self-test failed for {label}: {actual}')
    return len(cases)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    parser.add_argument('--build-system', choices=['native', 'swiftbuild'])
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()

    self_test_count = run_summary_self_tests()
    if args.self_test:
        print(json.dumps({'summary_self_test_passed': True, 'cases': self_test_count}, sort_keys=True))
        return

    if args.output is None or args.build_system is None:
        parser.error('the following arguments are required: --output, --build-system')

    root = Path(__file__).resolve().parents[1]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    receipt = {
        'build_system': args.build_system,
        'host': platform.platform(),
        'architecture': platform.machine(),
        'summary_self_test_cases': self_test_count,
        'checks': [],
    }

    def save():
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(name, command, tests=False):
        start = time.monotonic()
        environment = os.environ.copy()
        if tests:
            environment['SWIFTRLE_ORACLE_OUTPUT'] = str(out / (name + '-oracle'))
        result = subprocess.run(command, cwd=root, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (out / (name + '.log')).write_text(result.stdout)
        item = {'name': name, 'command': command, 'exit': result.returncode,
                'seconds': time.monotonic() - start}
        if tests:
            item.update(evaluate_test_summary(result.stdout, returncode=result.returncode, build_system=args.build_system))
        receipt['checks'].append(item)
        save()
        failed = result.returncode or (tests and not item['test_summary_verified'])
        if failed:
            # Compiler diagnostics can precede a long frontend command, so a tail
            # alone can omit the actual reason for failure. Preserve the full log
            # and print bounded diagnostic context from its original position.
            lines = result.stdout.splitlines()
            diagnostic_lines = [i for i, line in enumerate(lines)
                                if re.search(r'error:|fatal error:|Traceback|AssertionError', line)]
            selected = set()
            for index in diagnostic_lines[:20]:
                selected.update(range(max(0, index - 3), min(len(lines), index + 8)))
            context = '\n'.join(lines[i] for i in sorted(selected)) if selected else result.stdout[-8000:]
            print(name, result.returncode, 'full log:', out / (name + '.log'), context, flush=True)
            raise SystemExit(result.returncode or 1)
        print(name, result.returncode, result.stdout[-2000:], flush=True)
        return result.stdout

    run('swift-version', ['swift', '--version'])
    receipt['head'] = run('head', ['git', 'rev-parse', 'HEAD']).strip()
    receipt['status'] = run('status', ['git', 'status', '--porcelain'])
    files = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    receipt['files_sha256'] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                              for name in sorted(set(files) - {''}) if (root / name).is_file()}
    for line in (root / 'Documentation/COMMON_CONTRACT_SHA256.txt').read_text().splitlines():
        expected, name = line.split()
        if hashlib.sha256((root / 'Documentation' / name).read_bytes()).hexdigest() != expected:
            raise SystemExit('Pinned contract changed: ' + name)
    receipt['contracts_verified'] = 7
    oracle = os.environ.get('SWIFTRLE_TIFFCP') or shutil.which('tiffcp')
    if not oracle:
        raise SystemExit('Required libtiff oracle tiffcp is unavailable')
    # libtiff help prints its version and normally exits nonzero; tests exercise it.
    version = subprocess.run([oracle, '-h'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    receipt['oracle'] = {'path': oracle, 'version_help': version.stdout, 'help_exit': version.returncode}
    manifest = json.loads(run('manifest', ['swift', 'package', 'dump-package']))
    if manifest['dependencies']:
        raise SystemExit('Core package must have zero external dependencies')
    base = ['swift', 'test', '--build-system', args.build_system, '--scratch-path', str(out / 'build'), '-j', '2', '--no-parallel']
    run('debug', base, tests=True)
    run('release', base + ['-c', 'release'], tests=True)
    run('consumer', ['swift', 'run', '--build-system', args.build_system, '--package-path', 'Examples/Consumer',
                     '--scratch-path', str(out / 'consumer-build'), '-j', '2'])
    receipt['dicom_oracles'] = {}
    for configuration in ['debug', 'release']:
        oracle_path = out / (configuration + '-oracle') / 'oracle.json'
        oracle = json.loads(oracle_path.read_text())
        if oracle.get('two_way_passed', 0) < 27:
            raise SystemExit('Required DICOM oracle profile coverage missing')
        receipt['dicom_oracles'][configuration] = {'two_way_passed': oracle['two_way_passed'],
            'sha256': hashlib.sha256(oracle_path.read_bytes()).hexdigest()}
    receipt['passed'] = True
    save()


if __name__ == '__main__':
    main()
