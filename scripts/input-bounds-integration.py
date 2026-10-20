#!/usr/bin/env python3
"""Reproduce stale full-client clipping on owned windows in a disposable prefix.
Native geometry changes require an explicit environment flag and the receiving
fixture's title. Never inspects other windows, sends clicks, or reads accounts.
"""
import argparse,json,os,re,shutil,subprocess,uuid
from pathlib import Path
PROJECT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime',type=Path,default=PROJECT/'runtime/output/source-wine')
p.add_argument('--driver',type=Path,required=True)
p.add_argument('--baseline',action='store_true')
p.add_argument('--disabled',action='store_true')
p.add_argument('--bits',type=int,choices=[32,64],default=64)
a=p.parse_args()
root=PROJECT/'.cache'/('input-bounds-'+str(uuid.uuid4()));root.mkdir(parents=True)
runtime,prefix=root/'runtime',root/'prefix'
subprocess.run(['cp','-cR',str(a.runtime.resolve()),str(runtime)],check=True)
shutil.copy2(a.driver.resolve(),runtime/'lib/wine/x86_64-unix/winemac.so')
env=dict(HOME=str(Path.home()),PATH='/usr/bin:/bin:/usr/sbin:/sbin',WINEPREFIX=str(prefix),
    WINESERVER=str(runtime/'bin/wineserver'),WINEDEBUG='-all',WINEMSYNC='1',WINEDLLOVERRIDES='mscoree,mshtml=',
    DYLD_FALLBACK_LIBRARY_PATH=str(runtime/'lib')+':/usr/lib',CROSSEDOVER_INPUT_BOUNDS_PROBE='1')
if 'TMPDIR' in os.environ: env['TMPDIR']=os.environ['TMPDIR']
def wine(*args):
    with (root/'fixture.log').open('ab') as out:
        subprocess.run([str(runtime/'bin/wine'),*map(str,args)],env=env,stdout=out,stderr=out,check=True,timeout=90)
try:
    wine('wineboot','-u')
    for key,value in [('CursorClippingLocksWindows','N'),('CursorClippingFollowsWindow','N' if a.disabled else 'Y')]:
        wine('reg','add',r'HKCU\Software\Wine\AppDefaults\InputBounds.exe\Mac Driver','/v',key,'/t','REG_SZ','/d',value,'/f')
    exe=root/'InputBounds.exe'
    compiler='i686-w64-mingw32-gcc' if a.bits==32 else 'x86_64-w64-mingw32-gcc'
    subprocess.run([compiler,'-O2','-static',str(PROJECT/'runtime/input-bounds-smoke.c'),'-o',str(exe),'-luser32'],check=True)
    wine(exe)
    pattern=r'INPUT_BOUNDS case=(\w+) geometry=(\d) follows=(\d) unchanged=(\d) replaced=(\d) released=(\d)'
    found={m[0]:dict(zip(['geometry','follows','unchanged','replaced','released'],map(int,m[1:])))
           for m in re.findall(pattern,(root/'fixture.log').read_text(errors='replace'))}
    assert len(found)==8,found
    for name,case in found.items(): assert case['geometry']==1,(name,case)
    for name in ['grow','move','shrink']:
        if a.baseline or a.disabled: assert found[name]['unchanged']==1,(name,found[name])
        else: assert found[name]['follows']==1,(name,found[name])
    for name in ['subrect','point','released']: assert found[name]['unchanged']==1,(name,found[name])
    assert found['release_during']['released']==1,found['release_during']
    assert found['replace_during']['replaced']==1,found['replace_during']
    result=dict(baseline=a.baseline,disabled=a.disabled,bits=a.bits,cases=found)
    (root/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));print('Evidence:',root.relative_to(PROJECT))
finally:
    subprocess.run([str(runtime/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15)
    subprocess.run([str(runtime/'bin/wineserver'),'-w'],env=env,capture_output=True,timeout=15)
    for folder in [prefix,runtime]:
        if folder.is_dir() and not folder.is_symlink(): shutil.rmtree(folder)
