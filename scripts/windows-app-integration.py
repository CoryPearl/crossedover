#!/usr/bin/env python3
"""Run owned x86/x64 .exe payloads through the real supervisor in a fresh prefix.
Requires the source runtime and MinGW; never touches the user's Steam environment.
"""
from pathlib import Path
import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import time
import uuid

PROJECT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, help='Check a packaged .app and its bundled runtime')
options = parser.parse_args()
ROOT = PROJECT / '.cache' / ('windows-app-check-' + str(uuid.uuid4()))
RUNTIME_SOURCE = options.app.resolve() / 'Contents/Resources/BundledRuntime' if options.app else PROJECT / 'runtime/output/source-wine'
CLI = PROJECT / '.build/release/CrossedOverCLI'
SUPERVISOR = options.app.resolve() / 'Contents/MacOS/CrossedOverSupervisor' if options.app else PROJECT / '.build/release/CrossedOverSupervisor'
manifest = json.loads((RUNTIME_SOURCE / 'runtime.json').read_text())
ROOT.mkdir(parents=True)
(ROOT / 'Runtimes').mkdir()
RUNTIME = ROOT / 'Runtimes' / manifest['id']
# APFS clone of this explicitly owned test runtime, retaining symlink topology.
subprocess.run(['cp', '-cR', str(RUNTIME_SOURCE), str(RUNTIME)], check=True)

def cli(*arguments):
    return subprocess.check_output([str(CLI), '--root', str(ROOT), *arguments], text=True, timeout=60)

def records(kind):
    with sqlite3.connect(ROOT / 'crossedover.sqlite') as connection:
        return [json.loads(row[0]) for row in connection.execute('select payload from records where kind=?', (kind,))]

prefix = None
results = []
try:
    cli('create')
    environment = records('environment')[0]
    prefix = ROOT / 'Environments' / environment['id']
    assert not (prefix / 'drive_c/Program Files (x86)/Steam/steam.exe').exists()
    for bits, compiler in [(32, 'i686-w64-mingw32-gcc'), (64, 'x86_64-w64-mingw32-gcc')]:
        payload = ROOT / ('payload ' + str(bits))
        (payload / 'assets').mkdir(parents=True)
        (payload / 'assets/required.txt').write_text('crossedover sidecar\n')
        executable = payload / "Probe ' local.exe"
        subprocess.run([compiler, '-O2', '-static', str(PROJECT / 'runtime/windows-app-smoke.c'), '-o', str(executable), '-luser32', '-ladvapi32'], check=True)
        app = json.loads(cli('app-add', str(executable), '--folder', *(['--game'] if bits == 32 else [])))
        staged = prefix / app['executablePath']
        assert staged.is_file()
        assert app['category'] == ('games' if bits == 32 else 'apps')
        # The card must keep working when its source download is gone.
        shutil.rmtree(payload)
        request = {'version': 1, 'root': ROOT.as_uri() + '/', 'environmentID': environment['id'], 'command': 'launchWindowsApp', 'windowsAppID': app['id'], 'runID': str(uuid.uuid4())}
        reply = subprocess.run([str(SUPERVISOR)], input=json.dumps(request), text=True, capture_output=True, timeout=30, check=True)
        assert json.loads(reply.stdout)['success']
        observed_running = False
        for _ in range(300):
            run = next((item for item in records('windowsRun') if item['id'].lower() == request['runID'].lower()), None)
            if run and run['state'] == 'running':
                observed_running = True
                # A second launch of a live card must be rejected without starting a new worker.
                duplicate = dict(request, runID=str(uuid.uuid4()))
                rejected = subprocess.run([str(SUPERVISOR)], input=json.dumps(duplicate), text=True, capture_output=True, timeout=30)
                assert rejected.returncode != 0 and 'already' in json.loads(rejected.stdout)['message']
                break
            time.sleep(.1)
        assert observed_running, records('windowsRun')
        for _ in range(300):
            run = next(item for item in records('windowsRun') if item['id'].lower() == request['runID'].lower())
            if run['state'] not in ('requested', 'running'): break
            time.sleep(.1)
        assert run['state'] == 'exited' and run['exitCode'] == 0, run
        result = json.loads((staged.parent / 'probe-result.txt').read_text())
        assert result == {'bits': bits, 'sidecarRead': True, 'registryWrite': True, 'windowCreated': True}, result
        assert len(records('windowsApp')) == len(results) + 1
        results.append(dict(result, persistedCard=True, runningObserved=True, sourceRemoved=True, duplicateRejected=True))
    assert not list((ROOT / 'Backups').iterdir())
    output = {'runtime': manifest['id'], 'steamRequired': False, 'checks': results, 'automaticBackups': False}
    (PROJECT / '.cache/release-preview/windows-app-results.json').write_text(json.dumps(output, indent=2))
    print(json.dumps(output, indent=2))
finally:
    if prefix:
        variables = dict(os.environ, WINEPREFIX=str(prefix), WINESERVER=str(RUNTIME / manifest['wineserverRelativePath']), WINEDEBUG='-all')
        subprocess.run([str(RUNTIME / manifest['wineserverRelativePath']), '-k'], env=variables, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        subprocess.run([str(RUNTIME / manifest['wineserverRelativePath']), '-w'], env=variables, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
    shutil.rmtree(ROOT)
