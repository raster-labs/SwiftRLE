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

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--build-system', choices=['native', 'swiftbuild'], required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
receipt = {'build_system': args.build_system, 'host': platform.platform(),
           'architecture': platform.machine(), 'checks': []}

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
        counts = re.findall(r'Test run with (\d+) tests.*passed', result.stdout)
        item['tests_passed'] = int(counts[-1]) if counts else 0
        item['test_summary_verified'] = bool(counts) and item['tests_passed'] >= 38
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
