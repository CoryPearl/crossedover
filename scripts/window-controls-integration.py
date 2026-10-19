#!/usr/bin/env python3
"""Check native controls on owned fixture windows in a fresh, disposable prefix.

Never enumerates or manipulates other applications' windows or processes.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import uuid

PROJECT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', type=Path, default=PROJECT / 'runtime/output/source-wine')
parser.add_argument('--driver', type=Path, help='Explicit test-build driver; never installed in user data')
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--bits', type=int, choices=[32, 64], default=64)
options = parser.parse_args()
root = PROJECT / '.cache' / ('window-controls-' + str(uuid.uuid4()))
root.mkdir(parents=True)
runtime, prefix = root / 'runtime', root / 'prefix'
subprocess.run(['cp', '-cR', str(options.runtime.resolve()), str(runtime)], check=True)
if options.driver:
    shutil.copy2(options.driver.resolve(), runtime / 'lib/wine/x86_64-unix/winemac.so')
env = dict(HOME=str(Path.home()), PATH='/usr/bin:/bin:/usr/sbin:/sbin',
           WINEPREFIX=str(prefix), WINESERVER=str(runtime / 'bin/wineserver'),
           WINEMSYNC='1', WINEDEBUG='-all', WINEDLLOVERRIDES='mscoree,mshtml=',
           DYLD_FALLBACK_LIBRARY_PATH=str(runtime / 'lib') + ':/usr/lib',
           CROSSEDOVER_WINDOW_CONTROLS_PROBE='1')
if 'TMPDIR' in os.environ:
    env['TMPDIR'] = os.environ['TMPDIR']

def wine(*arguments, timeout=60):
    with (root / 'fixture.log').open('ab') as log:
        return subprocess.run([str(runtime / 'bin/wine'), *map(str, arguments)],
                              env=env, stdout=log, stderr=log, timeout=timeout, check=True)

try:
    wine('wineboot', '-u')
    for name in ['ForceWindowControls', 'NativeFullscreen', 'FullscreenIgnoreMaxSize']:
        wine('reg', 'add', r'HKCU\Software\Wine\AppDefaults\Brawlhalla.exe\Mac Driver',
             '/v', name, '/t', 'REG_SZ', '/d', 'Y', '/f')
    executable = root / 'Brawlhalla.exe'
    compiler = 'i686-w64-mingw32-gcc' if options.bits == 32 else 'x86_64-w64-mingw32-gcc'
    subprocess.run([compiler, '-O2', '-static', str(PROJECT / 'runtime/window-controls-smoke.c'),
                    '-o', str(executable), '-luser32', '-lgdi32'], check=True)
    wine(executable)
    found = {}
    pattern = r'CROSSEDOVER_CONTROLS case=(\w+) titled=(\d) close=(\d) mini=(\d) zoom=(\d) fullscreen=(\d) onscreen=(\d)'
    for match in re.finditer(pattern, (root / 'fixture.log').read_text(errors='replace')):
        found[match[1]] = dict(zip(['titled', 'close', 'mini', 'zoom', 'fullscreen', 'onscreen'], map(int, match.groups()[1:])))
    assert set(found) == {'plain', 'layered', 'shaped', 'desktop', 'tool', 'inactive', 'small', 'disabled'}, 'Missing native fixture observations'
    for name in ['tool', 'inactive', 'small']:
        assert found[name]['titled'] == 0, f'{name}: helper received controls'
    assert all(found['plain'][key] for key in ['titled', 'close', 'mini', 'zoom', 'fullscreen', 'onscreen']), found['plain']
    if options.baseline:
        assert found['layered']['titled'] == found['shaped']['titled'] == 0
    else:
        for name in ['layered', 'shaped', 'desktop']:
            assert all(found[name].values()), {name: found[name]}
        assert found['disabled']['titled'] == 1
        assert all(found['disabled'][key] == 0 for key in ['close', 'mini', 'zoom'])
    result = dict(baseline=options.baseline, bits=options.bits, windows=found)
    (root / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    print('Evidence:', root.relative_to(PROJECT))
finally:
    subprocess.run([str(runtime / 'bin/wineserver'), '-k'], env=env, capture_output=True, timeout=15)
    subprocess.run([str(runtime / 'bin/wineserver'), '-w'], env=env, capture_output=True, timeout=15)
    # Only the generated runtime/prefix; keep the small fixture/results/log.
    for folder in [runtime, prefix]:
        if folder.is_dir() and not folder.is_symlink():
            shutil.rmtree(folder)
