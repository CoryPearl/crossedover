#!/usr/bin/env python3
"""Install the real Epic prerequisites in an owned empty prefix, without an account/game.

Requires the vendor's EpicOnlineServicesInstaller.exe from an installed Epic client.
Only that selected installer is copied; never copy the client's account/cache folders.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import uuid
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--installer", type=Path, required=True)
parser.add_argument("--runtime", type=Path, default=PROJECT / "runtime/output/source-wine")
parser.add_argument("--cli", type=Path, default=PROJECT / ".build/release/CrossedOverCLI")
options = parser.parse_args()
installer, source, cli = options.installer.resolve(), options.runtime.resolve(), options.cli.resolve()
assert installer.name == "EpicOnlineServicesInstaller.exe" and installer.is_file()
assert installer.open("rb").read(2) == b"MZ"
manifest = json.loads((source / "runtime.json").read_text())
root = PROJECT / ".cache" / ("epic-support-" + str(uuid.uuid4()))
runtime = root / "Runtimes" / manifest["id"]
runtime.parent.mkdir(parents=True)
subprocess.run(["/bin/cp", "-cR", str(source), str(runtime)], check=True)
evidence = PROJECT / ".cache/v1.3/epic-support-results.json"
evidence.parent.mkdir(parents=True, exist_ok=True)
prefix = None


def command(*arguments, timeout=420):
    return subprocess.check_output([str(cli), "--root", str(root), *arguments],
                                   text=True, stderr=subprocess.STDOUT, timeout=timeout)


try:
    environment = json.loads(command("create"))
    prefix = root / "Environments" / environment["id"]
    launcher = prefix / "drive_c/Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe"
    launcher.parent.mkdir(parents=True)
    launcher.write_bytes(b"Owned path placeholder; this launcher is never executed.")
    target = launcher.parents[2] / "Extras/EOS/EpicOnlineServicesInstaller.exe"
    target.parent.mkdir(parents=True)
    subprocess.run(["/bin/cp", "-c", str(installer), str(target)], check=True)
    mono = prefix / "drive_c/windows/mono/mono-2.0/lib/mono/4.5/mscorlib.dll"
    assert not mono.exists()
    assert "Epic launch support is ready." in command("epic-repair")
    assert mono.is_file()
    first_modified = mono.stat().st_mtime_ns
    command("force-stop")  # Only this script's owned empty environment.
    assert "Epic launch support is ready." in command("epic-repair")
    assert mono.stat().st_mtime_ns == first_modified, "Repeat repair reinstalled Mono"
    command("force-stop")
    registry = (prefix / "system.reg").read_text()
    match = re.search(r'\[Software\\\\Wow6432Node\\\\Epic Games\\\\EOS\\\\MainService\].*?\n"Version"="([^"\n]+)"', registry, re.S)
    assert match and match.group(1).startswith("5."), "No persisted helper version"
    assert not list((prefix / "drive_c/crossedover").glob("mono-*.msi")), "Staged installer was retained"
    assert not list((root / "Backups").iterdir()), "Unexpected automatic backup"
    result = {
        "ownedEmptyPrefix": True,
        "runtime": manifest["id"],
        "installerSHA256": hashlib.sha256(installer.read_bytes()).hexdigest(),
        "helperVersion": match.group(1),
        "realMonoAndVendorHelperInstalled": True,
        "coreLiveVersionCheckPassed": True,
        "repeatRepairKeptMono": True,
        "stagedMSIRemoved": True,
        "automaticBackups": False,
        "launcherExecuted": False,
        "accountOrGameplayTested": False,
    }
    evidence.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
finally:
    try:
        if prefix is not None:
            command("force-stop", timeout=60)
    finally:
        shutil.rmtree(root)
