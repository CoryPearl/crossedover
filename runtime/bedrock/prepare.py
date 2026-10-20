#!/usr/bin/env python3
"""Build the separate, local Bedrock preview. Never downloads Minecraft or signs in.

Run --prepare, then --wine, --helper, and --stage. Player Macs do not build code.
All generated sources, dependencies, and binaries stay in ignored directories.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.cache/bedrock-build'
SOURCE = WORK / 'source'
OUTPUT = ROOT / 'runtime/output/bedrock-backend'
REVISION = '99fc9aa7d79b34aaee25a447b964e5d8235a2cec'
PROTOC_SHA = '9cd98a532c5c5e0c4161314de0225de27e4c8a323917b6ea7b1b714d3ae23466'
PROTOC_URL = 'https://github.com/protocolbuffers/protobuf/releases/download/v36.2/protoc-36.2-osx-aarch_64.zip'
PATCH = ROOT / 'runtime/bedrock/patches/crossedover-backend.patch'


def run(*args, **kwargs):
    subprocess.run(list(map(str, args)), check=True, **kwargs)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def prepare():
    WORK.mkdir(parents=True, exist_ok=True)
    if not SOURCE.exists():
        with tempfile.TemporaryDirectory(prefix='source-', dir=WORK) as temporary:
            checkout = Path(temporary) / 'checkout'
            run('git', 'init', '--quiet', checkout)
            run('git', '-C', checkout, 'fetch', '--depth', '1',
                'https://github.com/1JRobertson/bedrock-mac.git', REVISION)
            run('git', '-C', checkout, 'checkout', '--quiet', '--detach', 'FETCH_HEAD')
            run('git', '-C', checkout, 'apply', '--check', PATCH)
            run('git', '-C', checkout, 'apply', PATCH)
            (checkout / '.crossedover-patch-sha256').write_text(digest(PATCH))
            checkout.rename(SOURCE)
    actual = subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != REVISION or (SOURCE / '.crossedover-patch-sha256').read_text() != digest(PATCH):
        raise RuntimeError('Bedrock build inputs changed. Preserve this build and use a fresh workspace.')
    run('git', '-C', SOURCE, 'apply', '--reverse', '--check', PATCH)
    for project in ('winegdk', 'xodus'):
        command = [sys.executable, SOURCE / 'bootstrap-sources.py', '--project', project]
        if (SOURCE / 'sources' / project).exists():
            command.append('--check')
        run(*command)
    protoc = WORK / 'protoc/bin/protoc'
    if not protoc.exists():
        with tempfile.TemporaryDirectory(prefix='protoc-', dir=WORK) as temporary:
            archive = Path(temporary) / 'protoc.zip'
            with urllib.request.urlopen(PROTOC_URL, timeout=60) as response, archive.open('wb') as out:
                shutil.copyfileobj(response, out)
            if archive.stat().st_size != 2625514 or digest(archive) != PROTOC_SHA:
                raise RuntimeError('Protocol Buffers compiler failed verification.')
            stage = Path(temporary) / 'protoc'
            with zipfile.ZipFile(archive) as bundle:
                # Exact members only; no extraction of archive paths or links.
                for name in ('bin/protoc',):
                    target = stage / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(bundle.read(name))
                    target.chmod(0o755)
                for item in bundle.infolist():
                    if item.filename.startswith('include/google/protobuf/') and item.filename.endswith('.proto'):
                        relative = Path(item.filename)
                        if '..' in relative.parts or relative.is_absolute():
                            raise RuntimeError('Unsafe compiler archive member.')
                        target = stage / relative
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(bundle.read(item))
            stage.rename(WORK / 'protoc')


def environment():
    env = dict(os.environ)
    # These select installed developer tools; no global symlink/toolchain changes.
    env.setdefault('CROSSEDOVER_RUST_TOOLCHAIN', 'stable')
    env.setdefault('CROSSEDOVER_LLVM', '/opt/homebrew/opt/llvm@20')
    env['PROTOC'] = str(WORK / 'protoc/bin/protoc')
    env['STANDALONE_JOBS'] = '2'
    return env


def stage():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        raise RuntimeError('Backend output exists; preserve it before staging a new build.')
    python = shutil.which('python3.14') or shutil.which('python3.12')
    if python is None:
        raise RuntimeError('Python 3.12+ is required to freeze the development worker.')
    venv = WORK / 'freeze-env'
    if not venv.exists():
        run(python, '-m', 'venv', venv)
    run(venv / 'bin/python', '-m', 'pip', 'install', 'pyinstaller==6.22.3')
    run(venv / 'bin/pyinstaller', '--noconfirm', '--clean', '--onedir',
        '--name', 'BedrockWorker', '--distpath', WORK / 'frozen',
        '--workpath', WORK / 'freeze-work', '--specpath', WORK, SOURCE / 'launcher/setup.py')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.bedrock-stage-', dir=OUTPUT.parent) as temporary:
        candidate = Path(temporary) / 'backend'
        candidate.mkdir()
        shutil.copytree(WORK / 'frozen/BedrockWorker', candidate / 'worker', symlinks=True)
        wine = SOURCE / 'runtime/standalone/wine'
        target = candidate / 'runtime/wine'
        (target / 'bin').mkdir(parents=True)
        for name in ('wine', 'wine64', 'wineserver', 'wine-preloader', 'wine64-preloader'):
            path = wine / 'bin' / name
            if path.exists():
                shutil.copy2(path, target / 'bin' / name, follow_symlinks=False)
        shutil.copytree(wine / 'lib', target / 'lib', symlinks=True,
                        ignore=shutil.ignore_patterns('*.a', '*.o', '*.def', '*.debug'))
        shutil.copytree(wine / 'share/wine', target / 'share/wine', symlinks=True)
        shutil.copy2(wine / 'build-manifest.json', target / 'build-manifest.json')
        dxmt = SOURCE / 'runtime/standalone/dxmt'
        for name in ('manifest.json', 'x86_64-windows', 'x86_64-unix', 'licenses'):
            path, target = dxmt / name, candidate / 'runtime/dxmt' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if path.is_dir():
                shutil.copytree(path, target, symlinks=True)
            else:
                shutil.copy2(path, target)
        shutil.copy2(SOURCE / 'sources/xodus/target/release/examples/standalone_helper', candidate / 'standalone_helper')
        (candidate / 'scripts').mkdir()
        for name in ('standalone.py', 'standalone-setup.py', 'standalone-gameinput.py', 'winrt.reg'):
            shutil.copy2(SOURCE / name, candidate / 'scripts' / name)
        shutil.copytree(SOURCE / 'LICENSES', candidate / 'LICENSES')
        for name in ('LICENSE', 'THIRD_PARTY.md'):
            shutil.copy2(SOURCE / name, candidate / name)
        shutil.copy2(PATCH, candidate / 'crossedover-backend.patch')
        (candidate / 'verification').mkdir()
        for name in ('README.md', 'package_integrity.rs', 'GreenGamesPublicKey.public.bin', 'GreenXvdPublicKey.public.bin'):
            shutil.copy2(ROOT / 'runtime/bedrock/verification' / name, candidate / 'verification' / name)
        metadata = dict(schemaVersion=1, sourceRevision=REVISION, downloadPolicy='signed-xvd-v1',
                        minimumMacOS=26, previewOnly=True,
                        toolchain=subprocess.check_output(['rustc', '--version'], text=True).strip())
        # All symlinks must remain portable inside the staged backend.
        for path in candidate.rglob('*'):
            if path.is_symlink() and not path.resolve().is_relative_to(candidate.resolve()):
                raise RuntimeError('Backend contains an external symlink: ' + str(path.relative_to(candidate)))
        metadata['fileHashes'] = {str(p.relative_to(candidate)): digest(p) for p in candidate.rglob('*')
                                  if p.is_file() and not p.is_symlink()}
        metadata['symlinks'] = {str(p.relative_to(candidate)): os.readlink(p) for p in candidate.rglob('*') if p.is_symlink()}
        (candidate / 'backend.json').write_text(json.dumps(metadata, indent=2) + '\n')
        candidate.rename(OUTPUT)
    print('Staged local Bedrock preview:', OUTPUT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('prepare', 'wine', 'helper', 'stage', 'check'):
        parser.add_argument('--' + name, action='store_true')
    args = parser.parse_args()
    if args.prepare:
        prepare()
    env = environment()
    if args.wine:
        run(SOURCE / 'build-standalone-wine.sh', env=env, cwd=SOURCE)
        run(SOURCE / 'build-standalone-graphics.sh', '--wine-runtime', SOURCE / 'runtime/standalone/wine', env=env, cwd=SOURCE)
    if args.helper:
        examples = SOURCE / 'sources/xodus/crates/xodus-cli/examples'
        examples.mkdir(parents=True, exist_ok=True)
        for name in ('package_integrity.rs', 'GreenGamesPublicKey.public.bin', 'GreenXvdPublicKey.public.bin'):
            shutil.copy2(ROOT / 'runtime/bedrock/verification' / name, examples / name)
        shutil.copytree(ROOT / 'runtime/bedrock/verification/fixtures', examples / 'fixtures', dirs_exist_ok=True)
        run(sys.executable, SOURCE / 'standalone-setup.py', '--build-helper', '--jobs', '2', env=env, cwd=SOURCE)
        run('cargo', '+' + env['CROSSEDOVER_RUST_TOOLCHAIN'], 'test', '--release', '--locked', '-j', '2',
            '-p', 'xodus-cli', '--example', 'standalone_helper', env=env, cwd=SOURCE / 'sources/xodus')
        run(sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_onboarding.py', cwd=SOURCE)
    if args.stage:
        stage()
    if args.check:
        print(json.dumps({'sourcePrepared': SOURCE.is_dir(), 'backendStaged': (OUTPUT / 'backend.json').is_file(),
                          'sourceRevision': REVISION, 'downloadPolicy': 'signed-xvd-v1', 'gameDownloaded': False}, indent=2))


if __name__ == '__main__':
    main()
