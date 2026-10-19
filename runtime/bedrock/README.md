# Minecraft Bedrock backend · v1.4.0 development

This is the **local Windows Bedrock** backend, separate from crossedover's
Steam/Epic runtime. The Game Launchers menu opens a Minecraft panel; its install
button stays disabled if the compiled backend is absent or fails verification.
This is not the Windows Xbox app and does not enable its general catalog.

The source preview is based on [Bedrock for Mac](https://github.com/1JRobertson/bedrock-mac/tree/99fc9aa7d79b34aaee25a447b964e5d8235a2cec),
with pinned WineGDK, DXMT, and Xodus components. Our tracked integration patch:

- honors `BEDROCK_HOME` inside crossedover's data directory;
- uses the separate **crossedover Minecraft** Keychain service;
- requires certificate-verified HTTPS for game bytes and every redirect;
- reports game startup only after observing the Minecraft process;
- forwards reviewed status codes instead of arbitrary exception text;
- selects installed developer toolchains without changing global tools.

The upstream HTTP download is deliberately unavailable here: upstream records
an integrity gap for some package sections. The helper requires an HTTPS URL
from Microsoft's authenticated package catalog and checks foreground and
background CDN candidates without rewriting their hostnames. Normal TLS
validation remains enabled on every request and redirect.

The owner successfully signed in during the local test. The current catalog's
HTTP asset roots did not provide a usable certificate-verified game download.
Trying the same path on Microsoft's HTTPS asset endpoint returned HTTP 404;
retaining the original virtual host returned HTTP 503. Those failed mirror
experiments were removed. **Minecraft has not installed or launched in
crossedover.** Setup now stops with a specific secure-download message instead
of blaming sign-in. Completing authenticated package integrity verification or
finding a supported secure package source remains necessary before release.

## Build locally

Use an Apple silicon Mac on macOS 26+, Rosetta, Xcode Command Line Tools,
Python 3.12+ (3.14 for the current freeze), Rust 1.98+, Homebrew LLVM 20, Bison,
GnuTLS and FreeType headers. The build acquires the official pinned Protocol
Buffers compiler in its own cache. No compilers are installed for app users.
The default build uses two compiler jobs to limit memory use.

From the crossedover root:

```sh
python3 runtime/bedrock/prepare.py --prepare
python3 runtime/bedrock/prepare.py --wine
python3 runtime/bedrock/prepare.py --helper
python3 runtime/bedrock/prepare.py --stage
swift test -j 2
swift build -c release -j 2
python3 scripts/package.py --skip-build \
  --bedrock-backend runtime/output/bedrock-backend \
  --output .cache/previews/crossedover-bedrock.app
```

`--prepare` fetches exact source revisions and verifies the compiler download.
`--wine` builds the separate WineGDK runtime and stages verified DXMT binaries.
`--helper` compiles the account helper and runs its account-free unit tests.
`--stage` freezes Python and copies an explicit list of components into a
portable backend with an exact file/symlink inventory. Existing output is never
overwritten. The package step verifies that inventory, signs its nested code,
then records the signed hashes. It does not publish or replace the existing app.

`CROSSEDOVER_RUST_TOOLCHAIN` selects an installed rustup toolchain (default
`stable`; the local build uses 1.98.1). `CROSSEDOVER_LLVM` selects the installed
LLVM prefix. For a source build, set `CROSSEDOVER_BEDROCK_BACKEND` to the absolute
staged backend directory before launching crossedover. App users use bundled
components, with no shell configuration or Python installation.

For account-free status through the same Core boundary, set
`CROSSEDOVER_BEDROCK_BACKEND` and run `CrossedOverCLI minecraft-status`.
`CrossedOverCLI minecraft` starts a real setup/play session; Control-C/TERM asks
the owned worker to unwind its children. This developer path uses the same data
root as the native app unless `--root` is supplied. Do not start a second session
from the native app during that CLI session. Microsoft credentials never belong
in terminal arguments or chat.

## Account and files

Microsoft sign-in happens in its own window. The owning account's real content
license remains required. Games, Microsoft DLLs, credentials, and worlds are
not included in the backend or source. Sign-out uses only the backend's own
Keychain namespace and keeps installed files and worlds.

Data lives at `~/Library/Application Support/CrossedOver/Bedrock/`:

| Path | Contents |
| --- | --- |
| `game/` | The user's downloaded/prepared Windows Minecraft installation |
| `bottles/Bedrock-Standalone/` | Separate Wine prefix, including worlds under its user's `AppData/Roaming/Minecraft Bedrock` |
| `runtime/standalone/` | Links to the selected backend and session metadata |
| `logs/standalone/` | Private local setup/game logs; review before sharing |

The native app owns one worker; that worker owns one account helper across
setup and play. Progress comes from bounded JSON messages. Cancel/Stop unwinds
only that worker's children and its own Bedrock prefix. The native app waits
for worker exit before clearing the active state. Steam and Epic remain
independent. Uninstall is blocked while the Bedrock session lock is held.

The helper currently uses `/tmp/xodus.sock`; another Bedrock/Xodus session must
be closed normally first. Unknown sockets and other apps' helpers are preserved.
Closing crossedover's window keeps its active Minecraft session alive; quitting
crossedover requires finishing or stopping that session first.

## Release boundary

Core tests, source builds, a valid package, and a real game session are separate
checks. Do not publish v1.4.0 as playable Bedrock support until owned-account
download, gameplay, controls/audio, world save/reopen, normal quit, cancellation,
window/fullscreen behavior and a repeat launch have been checked. The development app is v1.4.0/build 26. Existing public download links still
point to the previous artifact while this work is in progress.

The upstream portable-library notice/source inventory and clean-Mac validation
also remain binary-release work. This backend is for local preview testing.
Preserve the upstream GPLv3, Wine LGPL, DXMT and dependency notices. The source
revision plus `patches/crossedover-backend.patch` are the durable build inputs;
generated source changes alone are not an integration patch.
