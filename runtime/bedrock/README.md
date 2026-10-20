# Minecraft Bedrock backend · v1.4.0

This is the **local Windows Bedrock** backend, separate from crossedover's
Steam/Epic runtime. The Game Launchers menu opens a Minecraft panel; its install
button stays disabled if the compiled backend is absent or fails verification.
This is not the Windows Xbox app and does not enable its general catalog.

The source preview is based on [Bedrock for Mac](https://github.com/1JRobertson/bedrock-mac/tree/99fc9aa7d79b34aaee25a447b964e5d8235a2cec),
with pinned WineGDK, DXMT, and Xodus components. Our tracked integration patch:

- honors `BEDROCK_HOME` inside crossedover's data directory;
- uses the separate **crossedover Minecraft** Keychain service;
- keeps account/catalog/license traffic on certificate-verified HTTPS;
- verifies the package signature and complete hash tree before parsing or extracting any game data;
- reports game startup only after observing the Minecraft process;
- forwards reviewed status codes instead of arbitrary exception text;
- selects installed developer toolchains without changing global tools.

The `signed-xvd-v1` download policy uses a separate client without account
headers or cookies. It accepts HTTPS catalog candidates and limits HTTP to
Microsoft's `assets1.xboxlive.com` / `assets2.xboxlive.com` origins on port 80.
Redirects obey the same policy. It never rewrites hostnames or disables TLS.
All candidates go through the same complete package verifier: the Microsoft
RSA-PSS signature authenticates the header/root hash, the root authenticates
all lower hash-tree pages, and leaf hashes authenticate every data page,
including plaintext package metadata. Unsupported layouts fail closed.

The complete archive is staged privately and checked before the XVD/filesystem
parsers or extraction run. The installer still obtains the owning account's
real Microsoft content license. Only required metadata and extracted game files
are retained; cancellation, failure and successful extraction remove the
temporary complete archive. No automatic full-package backup is created.
See [verification design, public-key provenance and fixtures](verification/README.md).

The owner successfully signed in during the local test, and a real package
header passed signature verification. Owned signed fixture archives pass full
verification; changed headers, tree pages, metadata and game data are rejected.
The full approximately 2 GB live package passed signature/tree/data verification,
Microsoft granted the content license, and all 12,177 files extracted. The
owner confirmed the game menu, playable local-world controls/sound, save and
normal quit. The installation check reports ready. The complete temporary
archive is gone; only 14,614,528 bytes of metadata remain with the game.
Card-based repeat launch and saved-world reopen are being checked.
The v1.4.0 DMG includes this backend; broader compatibility is still being checked.

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
checks. The owner requested publishing v1.4.0/build 26 after confirming
owned-account download, gameplay, controls/audio, saving and normal quit.
Saved-world reopen, cancellation, window/fullscreen behavior, repeat launch and
broader hardware remain validation work; their completion is not implied by
publishing this version.

The upstream portable-library notice/source inventory and clean-Mac validation
also remain work for broader public distribution. The backend retains its
preview status and is included in the owner-requested private-repository release.
Preserve the upstream GPLv3, Wine LGPL, DXMT and dependency notices. The source
revision plus `patches/crossedover-backend.patch` are the durable build inputs;
generated source changes alone are not an integration patch.
