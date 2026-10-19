#!/usr/bin/env python3
"""Build a local .app, CLI and optional disk image. No publishing side effects."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text().strip()

def run(args):
    subprocess.run([str(x) for x in args], cwd=ROOT, check=True)

def verify_runtime(root):
    manifest = json.loads((root / "runtime.json").read_text())
    hashes = manifest["fileHashes"]
    files = {str(p.relative_to(root)) for p in root.rglob("*")
             if p.is_file() and not p.is_symlink()
             and p.name not in {"runtime.json", "build-provenance.json"}}
    if files != set(hashes):
        raise RuntimeError("Runtime contents differ from its manifest. Finish the runtime build before packaging.")
    for name, expected in hashes.items():
        path = (root / name).resolve()
        if not path.is_relative_to(root.resolve()):
            raise RuntimeError("Runtime manifest path escapes its directory")
        with path.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
                raise RuntimeError("Runtime hash mismatch: " + name)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--dmg", action="store_true")
    parser.add_argument("--identity", default="-", help="Developer ID identity; '-' makes a local ad-hoc build")
    parser.add_argument("--runtime", type=Path, help="Include an explicitly selected development runtime for offline setup")
    parser.add_argument("--thin", action="store_true", help="Do not include a runtime; require an explicit local import")
    args = parser.parse_args()
    if args.runtime and args.thin: parser.error("--runtime and --thin are mutually exclusive")
    local_runtime = ROOT / "runtime/output/source-wine"
    if args.runtime is None and not args.thin and (local_runtime / "runtime.json").exists(): args.runtime = local_runtime
    configuration = "debug" if args.debug else "release"
    if not args.skip_build: run(["swift", "build", "-c", configuration, "-j", "4"])
    binary = Path(subprocess.check_output(["swift", "build", "-c", configuration, "--show-bin-path"], cwd=ROOT, text=True).strip())
    dist = ROOT / "dist"; dist.mkdir(exist_ok=True)
    app = dist / "crossedover.app"
    legacy_app = dist / "CrossedOver.app"
    if legacy_app.exists(): shutil.rmtree(legacy_app)
    if app.exists(): shutil.rmtree(app)
    macos = app / "Contents/MacOS"; resources = app / "Contents/Resources"; frameworks = app / "Contents/Frameworks"
    for folder in [macos, resources, frameworks]: folder.mkdir(parents=True, exist_ok=True)
    for name in ["CrossedOver", "CrossedOverSupervisor"]: shutil.copy2(binary / name, macos / name)
    for bundle in binary.glob("*.bundle"): shutil.copytree(bundle, resources / bundle.name, symlinks=True)
    shutil.copy2(ROOT / "LICENSE", resources / "LICENSE.txt")
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", resources / "Third-party notices.md")
    shutil.copytree(ROOT / "licenses", resources / "Licenses")
    if args.runtime:
        source_runtime = args.runtime.resolve()
        if not (source_runtime / "runtime.json").exists(): raise RuntimeError("Selected runtime has no runtime.json")
        verify_runtime(source_runtime)
        shutil.copytree(source_runtime, resources / "BundledRuntime", symlinks=True)
        verify_runtime(resources / "BundledRuntime")
    sparkle = ROOT / ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    shutil.copytree(sparkle, frameworks / "Sparkle.framework", symlinks=True)
    info = {
        "CFBundleIdentifier": "org.crossedover.CrossedOver", "CFBundleName": "crossedover", "CFBundleDisplayName": "crossedover",
        "CFBundleExecutable": "CrossedOver", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": "22", "LSMinimumSystemVersion": "15.0", "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication", "NSHumanReadableCopyright": "crossedover contributors. GPL-3.0-or-later.",
        "LSApplicationCategoryType": "public.app-category.games", "CFBundleIconFile": "CrossedOver"
    }
    iconset = ROOT / ".cache/CrossedOver.iconset"
    run(["swift", ROOT / "scripts/make-icon.swift", iconset])
    run(["iconutil", "-c", "icns", iconset, "-o", resources / "CrossedOver.icns"])
    feed, key = os.environ.get("CROSSEDOVER_UPDATE_FEED"), os.environ.get("CROSSEDOVER_UPDATE_PUBLIC_KEY")
    if bool(feed) != bool(key): raise RuntimeError("Set both update feed and public key, or neither")
    if feed:
        if not feed.startswith("https://"): raise RuntimeError("Update feed must use HTTPS")
        info.update({"SUFeedURL": feed, "SUPublicEDKey": key, "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False})
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    # Sign nested code explicitly from the inside out; Sparkle ships signed with
    # its own team, which cannot be loaded by our hardened application unchanged.
    options = ["--options", "runtime", "--timestamp"] if args.identity != "-" else []
    magic = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xfe\xed\xfa\xcf"}
    for path in frameworks.rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as f: header = f.read(4)
            if header in magic: run(["codesign", "--force", "--sign", args.identity, *options, path])
    for path in sorted(frameworks.rglob("*"), key=lambda x: len(x.parts), reverse=True):
        if path.suffix in [".app", ".xpc", ".framework"] and path.is_dir() and not path.is_symlink():
            run(["codesign", "--force", "--sign", args.identity, *options, path])
    run(["codesign", "--force", "--sign", args.identity, *options, macos / "CrossedOverSupervisor"])
    run(["codesign", "--force", "--sign", args.identity, *options, app])
    run(["codesign", "--verify", "--deep", "--strict", app])
    cli = dist / "bin"; cli.mkdir(exist_ok=True)
    shutil.copy2(binary / "CrossedOverCLI", cli / "crossedover")
    for bundle in binary.glob("*.bundle"):
        target = cli / bundle.name
        if target.exists(): shutil.rmtree(target)
        shutil.copytree(bundle, target, symlinks=True)
    if args.dmg:
        image = dist / f"crossedover-{VERSION}.dmg"
        legacy_image = dist / "CrossedOver-0.1.0.dmg"
        if legacy_image.exists(): legacy_image.unlink()
        if image.exists(): image.unlink()
        stage = dist / ".dmg-stage"
        if stage.exists(): shutil.rmtree(stage)
        stage.mkdir(); shutil.copytree(app, stage / app.name, symlinks=True)
        (stage / "Applications").symlink_to("/Applications")
        for source, name in [(ROOT / "docs/QUICKSTART.html", "Start Here.html"),
                             (ROOT / "LICENSE", "LICENSE.txt"),
                             (ROOT / "THIRD_PARTY_NOTICES.md", "Third-party notices.md")]:
            if source.exists(): shutil.copy2(source, stage / name)
        shutil.copytree(ROOT / "licenses", stage / "Licenses")
        run(["hdiutil", "create", "-volname", "crossedover", "-srcfolder", stage, "-ov", "-format", "UDZO", image])
        shutil.rmtree(stage)
    print("Built", app)
    print("CLI:", cli / "crossedover")
    if args.identity == "-": print("Local ad-hoc build. Not notarized or ready for public distribution.")

if __name__ == "__main__": main()
