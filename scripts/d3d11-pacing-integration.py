#!/usr/bin/env python3
"""Check DXMT pacing and executable scoping using an owned, bounded test window.
No Steam/game/account data is used. APFS runtime clone and prefix are removed.
"""
import argparse, json, os, shutil, subprocess, uuid
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', type=Path, required=True)
args = parser.parse_args()
root = PROJECT / '.cache' / ('d3d11-pacing-' + str(uuid.uuid4()))
root.mkdir(parents=True)
runtime, prefix = root / 'runtime', root / 'prefix'
manifest = json.loads((args.runtime / 'runtime.json').read_text())
assert manifest['id'].startswith('wine-11.0-cx26.3.0-dxmt0.80-')
subprocess.run(['cp', '-cR', str(args.runtime.resolve()), str(runtime)], check=True)
env = dict(HOME=str(Path.home()), PATH='/usr/bin:/bin:/usr/sbin:/sbin', WINEPREFIX=str(prefix),
           WINESERVER=str(runtime / manifest['wineserverRelativePath']), WINEDEBUG='-all', WINEMSYNC='1',
           WINEDLLOVERRIDES='winemetal,dxgi,d3d11,d3d10core,d3d9=b;mscoree,mshtml=',
           WINEDLLPATH=str(runtime / 'dxmt'), CROSSEDOVER_DLL_OVERLAY='1',
           DYLD_FALLBACK_LIBRARY_PATH=str(runtime / 'lib') + ':/usr/lib', DXMT_LOG_LEVEL='info',
           DXMT_CONFIG_FILE=r'C:\crossedover\pacing-test.conf')
if 'TMPDIR' in os.environ:
    env['TMPDIR'] = os.environ['TMPDIR']
results = {}

def run_wine(arguments, name, timeout=90):
    with (root / name).open('wb') as log:
        subprocess.run([str(runtime / manifest['wineRelativePath']), *map(str, arguments)], env=env,
                       stdout=log, stderr=log, check=True, timeout=timeout)

try:
    run_wine(['wineboot', '-u'], 'bootstrap.log')
    for arch, folder in [('x86_64-windows', 'system32'), ('i386-windows', 'syswow64')]:
        shutil.copy2(runtime / 'dxmt' / arch / 'winemetal.dll', prefix / 'drive_c/windows' / folder / 'winemetal.dll')
    z = prefix / 'dosdevices/z:'
    if z.is_symlink():
        z.unlink()
    folder = prefix / 'drive_c/crossedover'
    folder.mkdir(parents=True, exist_ok=True)
    executable = folder / 'PacingProbe.exe'
    subprocess.run(['x86_64-w64-mingw32-gcc', '-O2', '-static', str(PROJECT / 'runtime/d3d11-pacing-smoke.c'),
                    '-o', str(executable), '-ld3d11', '-ldxgi', '-ldxguid', '-luser32'], check=True)
    for case, heading, rate in [('matched30', 'PacingProbe.exe', 30), ('matched60', 'PacingProbe.exe', 60), ('unmatched30', 'Different.exe', 30)]:
        (folder / 'pacing-test.conf').write_text(f'[{heading}]\nd3d11.preferredMaxFrameRate = {rate}\ndxgi.customDeviceDesc = \"crossedover pacing fixture\"\n')
        run_wine([executable], case + '.log', 30)
        for line in (root / (case + '.log')).read_text(errors='replace').splitlines():
            if line.startswith('{"samples":'):
                results[case] = json.loads(line)
        assert case in results, f'No presentation statistics in {case}'
    (root / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    # Present returns before scanout: loop FPS is not displayed FPS. The
    # observable adapter label checks executable scoping without game access.
    assert results['matched30']['configMatched'] is True, results
    assert results['matched60']['configMatched'] is True, results
    assert results['unmatched30']['configMatched'] is False, results
    assert all(0 < item['presentLoopFPS'] <= 70 for item in results.values()), results
    print(json.dumps(results, indent=2))
    print('Evidence:', root.relative_to(PROJECT))
finally:
    subprocess.run([str(runtime / manifest['wineserverRelativePath']), '-k'], env=env, capture_output=True, timeout=20)
    subprocess.run([str(runtime / manifest['wineserverRelativePath']), '-w'], env=env, capture_output=True, timeout=20)
    for owned in [runtime, prefix]:
        if owned.is_dir() and not owned.is_symlink():
            shutil.rmtree(owned)
