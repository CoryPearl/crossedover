#!/usr/bin/env python3
"""Owned Wine handoff/Metal probe. This does not test Epic accounts or store downloads."""
from pathlib import Path
import argparse,json,os,shutil,sqlite3,subprocess,time,uuid
PROJECT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app',type=Path)
options=parser.parse_args()
source=options.app.resolve()/'Contents/Resources/BundledRuntime' if options.app else PROJECT/'runtime/output/source-wine'
supervisor=options.app.resolve()/'Contents/MacOS/CrossedOverSupervisor' if options.app else PROJECT/'.build/release/CrossedOverSupervisor'
cli=PROJECT/'.build/release/CrossedOverCLI'
manifest=json.loads((source/'runtime.json').read_text())
root=PROJECT/'.cache'/('epic-handoff-'+str(uuid.uuid4()))
(root/'Runtimes').mkdir(parents=True)
runtime=root/'Runtimes'/manifest['id']
subprocess.run(['cp','-cR',str(source),str(runtime)],check=True)
prefix=None

def command(*arguments):
 return subprocess.check_output([str(cli),'--root',str(root),*arguments],text=True,timeout=90)
def request(operation,app='OwnedProbe'):
 payload={'version':1,'root':root.as_uri()+'/','environmentID':environment['id'],'command':operation,'appID':app}
 result=subprocess.run([str(supervisor)],input=json.dumps(payload),text=True,capture_output=True,timeout=30,check=True)
 assert json.loads(result.stdout)['success']

try:
 command('create')
 with sqlite3.connect(root/'crossedover.sqlite') as connection:
  environment=json.loads(connection.execute("select payload from records where kind='environment'").fetchone()[0])
 prefix=root/'Environments'/environment['id']
 launcher=prefix/'drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe'
 launcher.parent.mkdir(parents=True)
 subprocess.run(['x86_64-w64-mingw32-gcc','-O2','-static',str(PROJECT/'runtime/epic-handoff-smoke.c'),'-o',str(launcher)],check=True)
 game=prefix/'drive_c/Program Files/Epic Games/OwnedProbe'; game.mkdir(parents=True)
 shutil.copy2(runtime/'share/crossedover/d3d11-smoke-64.exe',game/'Brawlhalla.exe')
 manifests=prefix/'drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests'; manifests.mkdir(parents=True)
 item=manifests/'owned.item'
 metadata={'AppName':'OwnedProbe','DisplayName':'Owned Epic handoff probe','CatalogNamespace':'probe-ns','CatalogItemId':'probe-item','InstallLocation':'C:\\Program Files\\Epic Games\\OwnedProbe','LaunchExecutable':'Brawlhalla.exe','InstallSize':123456,'bIsIncompleteInstall':True}
 item.write_text(json.dumps(metadata))
 assert json.loads(command('games'))==[]
 metadata['bIsIncompleteInstall']=False; item.write_text(json.dumps(metadata))
 discovered=json.loads(command('games')); assert len(discovered)==1 and discovered[0]['source']=='epic'
 handoff=prefix/'drive_c/crossedover/epic-handoff-request.txt'
 result=prefix/'drive_c/crossedover/epic-handoff-result.txt'
 request('launchEpicGame')
 for _ in range(300):
  if result.exists(): break
  time.sleep(.1)
 launch_log=root/'Logs/epic-session.log'
 assert result.exists() and result.read_text()=='0', {'log':launch_log.read_text(errors='replace')[-1000:] if launch_log.exists() else 'no worker log', 'handoff':handoff.read_text() if handoff.exists() else 'no handoff'}
 assert handoff.read_text()=='com.epicgames.launcher://apps/probe-ns%3Aprobe-item%3AOwnedProbe?action=launch&silent=false'
 order=(prefix/'drive_c/crossedover/epic-handoff-order.txt').read_text().splitlines()
 assert order[:2]==['com.epicgames.launcher://store/library',handoff.read_text()],order
 log=(prefix/'drive_c/crossedover/epic-readback.txt').read_text(errors='replace')
 assert '"valid":true' in log and '"api":"d3d11"' in log,log[-1000:]
 # Reuse the same owned child name to exercise the production Brawlhalla
 # D3D9 policy after the D3D11 child has exited. This is not game code.
 popup_source=root/'popup-readback.c'
 popup_source.write_text((PROJECT/'runtime/d3d9-smoke.c').read_text().replace('WS_OVERLAPPEDWINDOW, 0, 0, 64, 64','WS_POPUP, 40, 80, 640, 480'))
 subprocess.run(['x86_64-w64-mingw32-gcc','-O2','-static',str(popup_source),'-o',str(game/'Brawlhalla.exe'),'-ld3d9','-luser32'],check=True)
 result.unlink(); handoff.unlink()
 request('launchEpicGame')
 for _ in range(300):
  if result.exists(): break
  time.sleep(.1)
 assert result.exists() and result.read_text()=='0'
 readback=(prefix/'drive_c/crossedover/epic-readback.txt').read_text(errors='replace')
 assert '"valid":true' in readback and '"api":"d3d9"' in readback,readback[-1000:]
 for operation in ['openEpic','epicProperties','verifyEpicGame','uninstallEpicGame','epicDownloads']:
  handoff.unlink(missing_ok=True)
  request(operation)
  for _ in range(100):
   if handoff.exists(): break
   time.sleep(.1)
  assert handoff.exists() and handoff.read_text()=='com.epicgames.launcher://store/library',operation
 # Epic's Ubisoft-managed installs have partner records rather than .items.
 # Exercise the registered Ubisoft bootstrapper with an owned stand-in too.
 item.unlink()
 ubisoft=prefix/'drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe'
 ubisoft.parent.mkdir(parents=True); shutil.copy2(launcher,ubisoft)
 command('force-stop') # Only this owned fixture; flush/close its registry first.
 with (prefix/'system.reg').open('a') as registry:
  registry.write('\n'+r'[Software\\WOW6432Node\\Ubisoft\\Launcher\\Installs\\16382]'+'\n"InstallDir"='+json.dumps(r'C:\Program Files\Epic Games\OwnedProbe')+'\n')
 partners=prefix/'drive_c/ProgramData/Epic/EpicGamesLauncher/Data/ThirPartyManagedApps'
 partners.mkdir(parents=True)
 partner=partners/'owned.json'
 partner.write_text(json.dumps({'Provider':'UbisoftConnect','RegistryKey':'InstallDir','GameID':'16382','AppName':'OwnedPartner','Namespace':'probe-ns','CatalogID':'partner-item','Title':'Owned partner probe'}))
 cards=json.loads(command('games')); assert len(cards)==1 and cards[0]['epicPartnerGameID']=='16382'
 result.unlink(); handoff.unlink()
 count=len((prefix/'drive_c/crossedover/epic-handoff-order.txt').read_text().splitlines())
 request('launchEpicGame','OwnedPartner')
 for _ in range(300):
  if result.exists(): break
  time.sleep(.1)
 assert result.exists() and result.read_text()=='0'
 assert handoff.read_text()=='uplay://launch/16382/0'
 assert len((prefix/'drive_c/crossedover/epic-handoff-order.txt').read_text().splitlines())==count+1
 # Simulate a completed uninstall and remove only its card.
 partner.unlink(); shutil.rmtree(game)
 assert json.loads(command('games'))==[]
 assert not list((root/'Backups').iterdir())
 output={'ownedFixture':True,'officialEpicAuthenticationTested':False,'runtime':manifest['id'],'completeInstallDiscovery':True,'launchURIHandoff':True,'coldClientPrimed':True,'d3d11MetalReadback':True,'d3d9ScopedReadback':True,'partnerBootstrapper':True,'managementLibraryRoutes':True,'uninstallDiscovery':True,'automaticBackups':False}
 output_file=PROJECT/'.cache/release-preview/epic-results.json'
 output_file.parent.mkdir(parents=True,exist_ok=True)
 output_file.write_text(json.dumps(output,indent=2))
 print(json.dumps(output,indent=2))
finally:
 if prefix:
  variables=dict(os.environ,WINEPREFIX=str(prefix),WINESERVER=str(runtime/'bin/wineserver'),WINEDEBUG='-all')
  for argument in ['-k','-w']:
   subprocess.run([str(runtime/'bin/wineserver'),argument],env=variables,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=15)
 shutil.rmtree(root)
