#!/usr/bin/env python3
"""Build development Wine from locked FOSS sources. Never copies CrossOver.app.

The development dependency archive supplies x86-64 shared libraries, not Wine.
See source-lock.json for provenance and public-distribution limitations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
LOCK = json.loads((PROJECT / "runtime/source-lock.json").read_text())
CACHE = PROJECT / ".cache/runtime-sources"
WORK = PROJECT / ".cache/runtime-build"
SOURCE = CACHE / "extracted/sources/wine"
OUTPUT = PROJECT / "runtime/output/source-wine"

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for data in iter(lambda: f.read(1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()

def fetch(item):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / item["url"].rsplit("/", 1)[1]
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".partial")
        urllib.request.urlretrieve(item["url"], temporary)
        if digest(temporary) != item["sha256"]:
            temporary.unlink()
            raise RuntimeError("Downloaded source does not match the lock file")
        temporary.replace(path)
    if digest(path) != item["sha256"]:
        raise RuntimeError("Cached archive does not match the lock file: " + str(path))
    return path

def extract(archive, destination, prefix=None):
    destination.mkdir(parents=True, exist_ok=True)
    base = destination.resolve()
    with tarfile.open(archive) as tar:
        for member in tar:
            if prefix and not (member.name == prefix or member.name.startswith(prefix + "/")):
                continue
            target = (base / member.name).resolve()
            if not target.is_relative_to(base) or Path(member.name).is_absolute():
                raise RuntimeError("Unsafe archive member")
            if not (member.isfile() or member.isdir() or member.issym()):
                raise RuntimeError("Unsupported archive member type")
            if member.issym():
                link = (target.parent / member.linkname).resolve()
                if Path(member.linkname).is_absolute() or not link.is_relative_to(base):
                    raise RuntimeError("Escaping archive symlink")
            tar.extract(member, base, set_attrs=True)

def run(command, *, cwd=PROJECT, env=None, log=None):
    print("Running:", " ".join(str(x) for x in command), flush=True)
    if log:
        with Path(log).open("w") as output:
            subprocess.run([str(x) for x in command], cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run([str(x) for x in command], cwd=cwd, env=env, check=True)

def apply_patch_series(source, patches):
    """Recognize the complete series, including overlapping later patches.

    Reconstruct known prefix states in a temporary Git index. Individual reverse
    checks cannot recognize an earlier patch whose context a later patch changed.
    Preserve local edits by refusing to replace any unknown source state.
    """
    patches = list(patches)
    paths = set()
    for patch in patches:
        stats = subprocess.check_output(["git", "apply", "--numstat", str(patch)], cwd=source, text=True)
        paths.update(line.split("\t", 2)[2] for line in stats.splitlines())
    if not paths: return
    with tempfile.TemporaryDirectory(prefix="crossedover-patch-index-") as temporary:
        env = os.environ.copy(); env["GIT_INDEX_FILE"] = str(Path(temporary) / "index")
        subprocess.run(["git", "read-tree", "HEAD"], cwd=source, env=env, check=True)
        matched = None
        for count in range(len(patches) + 1):
            result = subprocess.run(["git", "diff", "--quiet", "--", *sorted(paths)], cwd=source, env=env)
            if result.returncode == 0: matched = count
            elif result.returncode != 1: raise RuntimeError("Could not inspect patched source")
            if count < len(patches):
                subprocess.run(["git", "apply", "--cached", str(patches[count])], cwd=source, env=env, check=True)
        if matched is None:
            raise RuntimeError("Source has edits outside the known patch series; preserved without modification")
        for patch in patches[matched:]:
            run(["git", "apply", "--check", patch], cwd=source)
            run(["git", "apply", patch], cwd=source)

def build_d9vk(overlay, jobs):
    item = LOCK["d9vk"]
    source = CACHE / "d9vk"
    if not source.exists():
        run(["git", "clone", "--no-checkout", item["source"], source])
        run(["git", "checkout", "--detach", item["revision"]], cwd=source)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if revision != item["revision"]:
        raise RuntimeError("D9VK checkout does not match its locked revision")
    run(["git", "submodule", "update", "--init", "--recursive"], cwd=source)
    apply_patch_series(source, sorted((PROJECT / "runtime/patches/d9vk").glob("*.patch")))
    for bits, arch, strip in [("32", "i386-windows", "i686-w64-mingw32-strip"), ("64", "x86_64-windows", "x86_64-w64-mingw32-strip")]:
        build = source / ("build" + bits)
        options = ["--reconfigure"] if (build / "meson-private/coredata.dat").exists() else []
        run(["meson", "setup", *options, build, "--cross-file", source / ("build-win" + bits + ".txt"), "--buildtype", "release", "-Denable_dxgi=false", "-Denable_d3d10=false", "-Denable_d3d11=false"], cwd=source, log=WORK / ("d9vk-configure" + bits + ".log"))
        run(["meson", "compile", "-C", build, "-j", str(jobs)], cwd=source, log=WORK / ("d9vk-build" + bits + ".log"))
        target = overlay / arch / "d3d9.dll"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(build / "src/d3d9/d3d9.dll", target)
        run([strip, "--strip-debug", target])
    shutil.copy2(source / "LICENSE", overlay / "D9VK-LICENSE")
    (overlay / "README.md").write_text("CrossedOver altered D9VK build from " + item["source"] + " at " + item["revision"] + ".\nVolume-slice and reflection patches: https://github.com/vakesz/TrackMania-MacOS/tree/main/patches/d9vk\n")
    archive = fetch(LOCK["moltenvk"])
    with tarfile.open(archive) as tar:
        for member, name in [("MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib", "libMoltenVK.dylib"), ("MoltenVK/LICENSE", "MoltenVK-LICENSE")]:
            entry = tar.getmember(member)
            if not entry.isfile() or not 0 < entry.size < 128 * 1024 * 1024:
                raise RuntimeError("Invalid MoltenVK payload")
            with tar.extractfile(entry) as content:
                (overlay / name).write_bytes(content.read())
    (overlay / "dxvk.conf").write_text(
        "# No asynchronous draw skipping. Options are scoped by executable.\n"
        "[TmForever.exe]\n"
        "d3d9.maxAvailableMemory = 1024\n"
        "d3d9.forceProcessDEP = True\n"
        "d3d9.maxFrameRate = 60\n"
        "d3d9.maxFrameLatency = 2\n"
        "\n[d3d9-mapped-copy-32.exe]\n"
        "d3d9.forceProcessDEP = True\n")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--configure-only", action="store_true")
    parser.add_argument("--skip-build", action="store_true", help="Package an already compiled source tree")
    parser.add_argument("--metal", action="store_true", help="Include the pinned experimental DXMT builtin overlay")
    parser.add_argument("--d3d9", action="store_true", help="Build pinned D9VK and include official MoltenVK for the TrackMania Performance profile")
    parser.add_argument("--x87", action="store_true", help="Include the pinned PC24-aware cooperative x87 accelerator for Performance")
    parser.add_argument("--audio", action="store_true", help="Include official OpenAL Soft for the TrackMania demo")
    args = parser.parse_args()
    if args.x87 and not args.d3d9:
        parser.error("--x87 requires --d3d9")
    if not 1 <= args.jobs <= 32:
        parser.error("--jobs must be between 1 and 32")
    wine_archive = fetch(LOCK["wine"])
    if not SOURCE.exists():
        extract(wine_archive, CACHE / "extracted", "sources/wine")
    # The handshake is inert unless the managed launcher selects a helper.
    if "rosetta_cooperative_handshake" not in (SOURCE / "dlls/ntdll/unix/loader.c").read_text():
        patch = PROJECT / "runtime/patches/ntdll-x87-cooperative.patch"
        run(["git", "apply", "--check", patch], cwd=SOURCE)
        run(["git", "apply", patch], cwd=SOURCE)
    window_patch = PROJECT / "runtime/patches/winemac-optional-cursor-clipping.patch"
    if "bool allow_cursor_clipping = true;" not in (SOURCE / "dlls/winemac.drv/macdrv_main.c").read_text():
        run(["git", "apply", "--check", window_patch], cwd=SOURCE)
        run(["git", "apply", window_patch], cwd=SOURCE)
    fullscreen_patch = PROJECT / "runtime/patches/winemac-native-fullscreen-size.patch"
    if "bool fullscreen_ignore_max_size = false;" not in (SOURCE / "dlls/winemac.drv/macdrv_main.c").read_text():
        run(["git", "apply", "--check", fullscreen_patch], cwd=SOURCE)
        run(["git", "apply", fullscreen_patch], cwd=SOURCE)
    dependency_archive = fetch(LOCK["developmentDependencies"])
    dependency_extract = PROJECT / ".cache/community-runtime"
    if not (dependency_extract / "Wine Devel.app").exists():
        extract(dependency_archive, dependency_extract)
    dependency_root = dependency_extract / "Wine Devel.app/Contents/Resources/wine"
    alias = PROJECT / ".cache/wine-deps"
    if not alias.exists():
        alias.symlink_to(dependency_root, target_is_directory=True)
    # DXMT discovers these APIs through dlsym. Keep the visibility patch narrow.
    header = SOURCE / "dlls/winemac.drv/macdrv_cocoa.h"
    content = header.read_text()
    names = ["macdrv_create_metal_device", "macdrv_release_metal_device", "macdrv_view_create_metal_view", "macdrv_view_get_metal_layer", "macdrv_view_release_metal_view"]
    for name in names:
        content = re.sub(r'(extern )(?!__attribute__)(.*\b' + name + r'\()', r'\1__attribute__((visibility("default"))) \2', content)
    if content != header.read_text():
        header.write_text(content)
    loader = SOURCE / "dlls/ntdll/unix/loader.c"
    content = loader.read_text()
    marker = '    for (i = 0; i < count; i++) dll_path_maxlen = max( dll_path_maxlen, strlen(dll_paths[i]) );'
    if "CROSSEDOVER_DLL_OVERLAY" not in content:
        overlay_patch = '''    /* CrossedOver: explicitly selected builtin overlays precede default DLLs. */
    if (!build_dir && count > 1 && getenv("CROSSEDOVER_DLL_OVERLAY"))
    {
        const char *default_path = dll_paths[0];
        for (i = 1; i < count; i++) dll_paths[i - 1] = dll_paths[i];
        dll_paths[count - 1] = default_path;
    }

'''
        if marker not in content: raise RuntimeError("Wine overlay patch no longer matches its locked source")
        loader.write_text(content.replace(marker, overlay_patch + marker, 1))
    process_source = SOURCE / "dlls/kernelbase/process.c"
    content = process_source.read_text()
    if "CROSSEDOVER_STEAM_CEF_COMPAT" not in content:
        marker = '    if (!(params = create_process_params( app_name, tidy_cmdline, cur_dir, env, flags, startup_info )))'
        patch = '''    /* CrossedOver: Steam's CEF shared-surface path is incompatible with Wine on macOS. */
    if (GetEnvironmentVariableW( L"CROSSEDOVER_STEAM_CEF_COMPAT", NULL, 0 ))
    {
        const WCHAR *base_name = wcsrchr( app_name, '\\\\' );
        base_name = base_name ? base_name + 1 : app_name;
        if (!wcsicmp( base_name, L"steamwebhelper.exe" ) && !wcsstr( tidy_cmdline, L"--type=" )
                && !wcsstr( tidy_cmdline, L"--single-process" ))
        {
            static const WCHAR extra[] = L" --disable-gpu --single-process";
            SIZE_T length = lstrlenW( tidy_cmdline ) + ARRAY_SIZE(extra);
            WCHAR *updated = HeapAlloc( GetProcessHeap(), 0, length * sizeof(WCHAR) );
            if (!updated) { status = STATUS_NO_MEMORY; goto done; }
            swprintf( updated, length, L"%s%s", tidy_cmdline, extra );
            if (tidy_cmdline != cmd_line) HeapFree( GetProcessHeap(), 0, tidy_cmdline );
            tidy_cmdline = updated;
        }
    }

'''
        if marker not in content: raise RuntimeError("Wine Steam CEF patch no longer matches its locked source")
        process_source.write_text(content.replace(marker, patch + marker, 1))
    WORK.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({
        "PATH": "/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "PKG_CONFIG": "false",
        "FREETYPE_CFLAGS": "-I/opt/homebrew/opt/freetype/include/freetype2",
        "FREETYPE_LIBS": f"-L{alias}/lib -lfreetype",
        "GNUTLS_CFLAGS": "-I/opt/homebrew/include",
        "GNUTLS_LIBS": f"-L{alias}/lib -lgnutls",
        "ac_cv_lib_soname_freetype": "libfreetype.dylib",
        "ac_cv_lib_soname_gnutls": "libgnutls.dylib",
        "ac_cv_lib_soname_vulkan": "libMoltenVK.dylib"
    })
    env["DYLD_FALLBACK_LIBRARY_PATH"] = str(alias / "lib") + ":/usr/lib"
    if not args.skip_build:
        run([SOURCE / "configure", "--build=x86_64-apple-darwin", "--host=x86_64-apple-darwin", "--enable-archs=i386,x86_64", "--without-x", "--without-alsa", "--without-pulse", "--without-dbus", "--without-cups", "--without-v4l2", "CC=clang -arch x86_64", "CXX=clang++ -arch x86_64", "CFLAGS=-O2 -mmacosx-version-min=15.0", "--prefix=" + str(OUTPUT)], cwd=WORK, env=env, log=WORK / "configure-output.log")
        if args.configure_only:
            return
        makefile = WORK / "Makefile"
        content = makefile.read_text()
        # Reintroduce the dependency lookup after SIP-protected make starts.
        # Patching the tool binary itself is insufficient: make may relink it.
        content = content.replace("\ttools/sfnt2fon/sfnt2fon ", "\t/usr/bin/env DYLD_FALLBACK_LIBRARY_PATH=" + str(alias / "lib") + ":/usr/lib tools/sfnt2fon/sfnt2fon ")
        makefile.write_text(content)
        run(["make", "-j" + str(args.jobs)], cwd=WORK, env=env, log=WORK / "build-output.log")
    if args.skip_build and args.x87:
        # An older cached Wine build may predate the opt-in loader handshake.
        run(["make", "-j" + str(args.jobs), "dlls/ntdll/ntdll.so"], cwd=WORK, env=env, log=WORK / "x87-loader-output.log")
    if args.skip_build:
        run(["make", "-j" + str(args.jobs), "dlls/winemac.drv/winemac.so"], cwd=WORK, env=env, log=WORK / "window-driver-output.log")
    run(["make", "install"], cwd=WORK, env=env, log=WORK / "install-output.log")
    # Development dependencies retain their @loader_path-relative dependency graph.
    for source in (dependency_root / "lib").iterdir():
        if source.name == "wine":
            continue
        target = OUTPUT / "lib" / source.name
        if target.exists() or target.is_symlink():
            if target.is_dir() and not target.is_symlink(): shutil.rmtree(target)
            else: target.unlink()
        if source.is_symlink(): target.symlink_to(os.readlink(source))
        elif source.is_dir(): shutil.copytree(source, target, symlinks=True)
        else: shutil.copy2(source, target)
    share = OUTPUT / "share/crossedover"
    share.mkdir(parents=True, exist_ok=True)
    run(["x86_64-w64-mingw32-gcc", "-O2", "-static", PROJECT / "runtime/process-observer.c", "-o", share / "process-observer.exe"])
    for bits, compiler in [(64, "x86_64-w64-mingw32-gcc"), (32, "i686-w64-mingw32-gcc")]:
        run([compiler, "-O2", "-static", PROJECT / "runtime/smoke.c", "-o", share / f"smoke-{bits}.exe"])
        for api, libraries in [("d3d9", ["-ld3d9", "-luser32"]), ("d3d11", ["-ld3d11", "-ldxgi"])]:
            run([compiler, "-O2", "-static", PROJECT / f"runtime/{api}-smoke.c", "-o", share / f"{api}-smoke-{bits}.exe", *libraries])
        run([compiler, "-O2", "-static", PROJECT / "runtime/d3d9-benchmark.c", "-o", share / f"d3d9-benchmark-{bits}.exe", "-ld3d9", "-luser32"])
        run([compiler, "-O2", "-static", PROJECT / "runtime/d3d9-textures.c", "-o", share / f"d3d9-textures-{bits}.exe", "-ld3d9", "-luser32"])
        if bits == 32:
            run([compiler, "-O2", "-static", "-Wl,--disable-nxcompat", PROJECT / "runtime/d3d9-mapped-copy.c", "-o", share / "d3d9-mapped-copy-32.exe", "-ld3d9", "-luser32"])
        run([compiler, "-O2", "-static", PROJECT / "runtime/x87-smoke.c", "-o", share / f"x87-smoke-{bits}.exe"])
    profiles = ["legacy"]
    if args.metal:
        dxmt_archive = fetch(LOCK["dxmt"])
        stage = CACHE / "dxmt"
        if not (stage / "v0.80").exists(): extract(dxmt_archive, stage)
        overlay = OUTPUT / "dxmt"
        if overlay.exists(): shutil.rmtree(overlay)
        shutil.copytree(stage / "v0.80", overlay)
        # Shared Unix component is installed in Wine's normal Unix module directory.
        shutil.copy2(overlay / "x86_64-unix/winemetal.so", OUTPUT / "lib/wine/x86_64-unix/winemetal.so")
        for architecture in ["i386-windows", "x86_64-windows"]:
            shutil.copy2(overlay / architecture / "winemetal.dll", OUTPUT / "lib/wine" / architecture / "winemetal.dll")
        profiles.append("metal")
    if args.d3d9:
        overlay = OUTPUT / "dxvk"
        if overlay.exists(): shutil.rmtree(overlay)
        overlay.mkdir()
        build_d9vk(overlay, args.jobs)
        profiles.append("performance")
    elif (OUTPUT / "dxvk").exists():
        shutil.rmtree(OUTPUT / "dxvk")
    helper = OUTPUT / "bin/x87sidecar"
    if args.x87:
        archive = fetch(LOCK["x87"])
        with tarfile.open(archive) as tar:
            entry = tar.getmember("runtime/bin/x87sidecar")
            if not entry.isfile() or not 0 < entry.size < 16 * 1024 * 1024:
                raise RuntimeError("Invalid x87 helper")
            helper.write_bytes(tar.extractfile(entry).read())
            helper.chmod(0o755)
            license_dir = OUTPUT / "share/crossedover/licenses/x87sidecar"
            license_dir.mkdir(parents=True, exist_ok=True)
            for entry in tar.getmembers():
                if entry.isfile() and entry.name.startswith("runtime/licenses/x87sidecar/"):
                    if entry.size > 1024 * 1024: raise RuntimeError("Invalid x87 license payload")
                    (license_dir / Path(entry.name).name).write_bytes(tar.extractfile(entry).read())
        run([helper, "--probe"], log=WORK / "x87-probe.log")
    elif helper.exists():
        helper.unlink()
    audio = OUTPUT / "audio"
    if audio.exists(): shutil.rmtree(audio)
    if args.audio:
        archive = fetch(LOCK["openal"])
        with zipfile.ZipFile(archive) as package:
            directory = "openal-soft-" + LOCK["openal"]["version"] + "-bin/"
            data = package.read(directory + "bin/Win32/soft_oal.dll")
            if not 0 < len(data) < 32 * 1024 * 1024 or data[:2] != b"MZ":
                raise RuntimeError("Invalid OpenAL Soft DLL")
            target = audio / "i386-windows/OpenAL32.dll"
            target.parent.mkdir(parents=True)
            target.write_bytes(data)
            license_dir = OUTPUT / "share/crossedover/licenses/openal-soft"
            license_dir.mkdir(parents=True, exist_ok=True)
            (license_dir / "COPYING").write_bytes(package.read(directory + "COPYING"))
            (license_dir / "SOURCE.txt").write_text("Unmodified official OpenAL Soft " + LOCK["openal"]["version"] + " Windows binary.\nSource: " + LOCK["openal"]["source"] + "\nDownload and SHA-256: runtime/source-lock.json in CrossedOver's source.\n")
        run(["i686-w64-mingw32-gcc", "-O2", "-static", PROJECT / "runtime/openal-smoke.c", "-o", OUTPUT / "share/crossedover/openal-smoke-32.exe"])
    # The application runtime does not need Wine's development SDK or PE debug
    # sections. Dynamic export tables and builtin module markers are retained.
    if (OUTPUT / "include").exists(): shutil.rmtree(OUTPUT / "include")
    for path in (OUTPUT / "lib").rglob("*.a"): path.unlink()
    for name in ["winegcc", "wineg++", "winecpp", "winebuild", "widl"]:
        path = OUTPUT / "bin" / name
        if path.exists() or path.is_symlink(): path.unlink()
    for architecture, compiler in [("i386-windows", "i686-w64-mingw32-strip"), ("x86_64-windows", "x86_64-w64-mingw32-strip")]:
        directory = OUTPUT / "lib/wine" / architecture
        for path in directory.iterdir():
            if path.is_file() and path.suffix in [".dll", ".exe"]:
                subprocess.run([compiler, "--strip-debug", str(path)], check=True, stdout=subprocess.DEVNULL)
    notices = OUTPUT / "share/crossedover/licenses"
    notices.mkdir(exist_ok=True)
    for name in ["COPYING.LIB", "LICENSE", "AUTHORS"]:
        shutil.copy2(SOURCE / name, notices / ("Wine-" + name))
    file_hashes = {str(p.relative_to(OUTPUT)): digest(p) for p in OUTPUT.rglob("*") if p.is_file() and not p.is_symlink() and p.name not in ["runtime.json", "build-provenance.json"]}
    content_id = hashlib.sha256(json.dumps(file_hashes, sort_keys=True).encode()).hexdigest()[:10]
    manifest = {
        "schemaVersion": 1, "id": "wine-11.0-cx26.3.0" + ("-dxmt0.80" if args.metal else "") + ("-d9vk-mvk1.4.2" if args.d3d9 else "") + ("-x87" if args.x87 else "") + ("-openal1.25.2" if args.audio else "") + "-" + content_id,
        "name": "CrossedOver source Wine 11.0" + (" + DXMT 0.80" if args.metal else "") + (" + D9VK / MoltenVK 1.4.2" if args.d3d9 else "") + (" + x87 acceleration" if args.x87 else ""),
        "version": "11.0-cx26.3.0", "architecture": "x86_64", "minimumMacOS": 15,
        "wineRelativePath": "bin/wine", "wineserverRelativePath": "bin/wineserver",
        "observerRelativePath": "share/crossedover/process-observer.exe", "profiles": profiles,
        "supportsMSync": True,
        "sourceURL": LOCK["wine"]["url"], "sourceSHA256": LOCK["wine"]["sha256"], "experimental": True,
        "fileHashes": file_hashes
    }
    if args.x87: manifest["x87RelativePath"] = "bin/x87sidecar"
    (OUTPUT / "runtime.json").write_text(json.dumps(manifest, indent=2))
    provenance = {"components": LOCK, "compiler": subprocess.check_output(["clang", "--version"], text=True), "patches": ["Expose five winemac Metal APIs with default visibility", "Opt-in CROSSEDOVER_DLL_OVERLAY prepends builtin module overlays", "Opt-in CROSSEDOVER_STEAM_CEF_COMPAT selects software single-process Steam CEF", "Opt-in cooperative x87 startup; runtime/patches/ntdll-x87-cooperative.patch"], "publicReleaseReady": False}
    provenance["winePatchHashes"] = {str(p.relative_to(PROJECT)): digest(p) for p in sorted((PROJECT / "runtime/patches").glob("*.patch"))}
    if args.d3d9:
        provenance["d9vkPatchHashes"] = {str(p.relative_to(PROJECT)): digest(p) for p in sorted((PROJECT / "runtime/patches/d9vk").glob("*.patch"))}
    (OUTPUT / "build-provenance.json").write_text(json.dumps(provenance, indent=2))
    print("Development runtime:", OUTPUT)
    print("Import with: .build/debug/CrossedOverCLI runtime-import", OUTPUT)

if __name__ == "__main__":
    main()
