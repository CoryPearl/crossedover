#!/usr/bin/env python3
"""Exercise an explicit runtime in a fresh, isolated environment; never signs in."""
import argparse
import json
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--cli", type=Path, default=ROOT / ".build/debug/CrossedOverCLI")
    parser.add_argument("--steam-install", action="store_true", help="Also download and install official Windows Steam, without login")
    args = parser.parse_args()
    root = ROOT / ".cache" / ("integration-" + str(uuid.uuid4()))
    root.mkdir(parents=True)
    cli = args.cli.resolve(); manifest = json.loads((args.runtime / "runtime.json").read_text())
    record = {"runtime": manifest["id"], "root": str(root), "checks": [], "success": False}
    def check(name, *command):
        print(name, flush=True)
        result = subprocess.run([str(cli), "--root", str(root), *map(str, command)], cwd=ROOT, capture_output=True, text=True, timeout=360)
        log = root / (name.replace(" ", "-") + ".txt")
        log.write_text(result.stdout + result.stderr)
        record["checks"].append({"name": name, "success": result.returncode == 0, "log": str(log)})
        if result.returncode: raise RuntimeError(name + " failed; inspect " + str(log))
        return result.stdout
    try:
        check("import", "runtime-import", args.runtime.resolve())
        check("fresh-prefix", "create")
        check("stop-before-legacy", "force-stop")
        check("legacy-profile", "profile", "legacy")
        check("legacy-execution-and-gpu", "smoke", "--graphics")
        if "performance" in manifest["profiles"]:
            check("stop-before-performance", "force-stop")
            check("performance-profile", "profile", "performance")
            check("performance-execution-and-gpu", "smoke", "--graphics")
            check("stop-before-legacy-fallback", "force-stop")
            check("legacy-fallback-profile", "profile", "legacy")
            check("legacy-fallback-execution-and-gpu", "smoke", "--graphics")
        if "metal" in manifest["profiles"]:
            check("stop-before-metal", "force-stop")
            check("metal-profile", "profile", "metal")
            check("metal-execution-and-gpu", "smoke", "--graphics")
        if {"performance", "metal"}.issubset(manifest["profiles"]):
            check("stop-before-combined", "force-stop")
            check("combined-profile", "profile", "combined")
            check("combined-execution-and-gpu", "smoke", "--graphics")
        observation = json.loads(check("process-observer", "observe"))
        if not isinstance(observation.get("processes"), list): raise RuntimeError("Runtime did not return process observations")
        check("stop-before-backup", "force-stop")
        backup = check("backup", "backup").strip()
        check("restore", "restore", backup)
        if args.steam_install: check("official-steam-install", "steam-install")
        record["success"] = True
    finally:
        subprocess.run([str(cli), "--root", str(root), "force-stop"], cwd=ROOT, capture_output=True, timeout=30)
        (root / "results.json").write_text(json.dumps(record, indent=2))
        print("Results:", root / "results.json", flush=True)
    if not record["success"]: raise SystemExit(1)

if __name__ == "__main__": main()
