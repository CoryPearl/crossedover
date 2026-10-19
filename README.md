# CrossedOver

A native macOS Windows-game compatibility prototype, currently focused on **TrackMania Nations Forever as its only demo**. SwiftUI interface, managed Windows Steam, an independent Wine runtime, graphics profiles, a command-line interface, and recovery tools.

**Status: development prototype.** Steam installation, client self-update, 32/64-bit Windows execution, Direct3D 9 pixel readback, and Direct3D 11 pixel readback through DXMT have been exercised on an Apple M4 with macOS 26.6.2. Steam sign-in, TrackMania's download, game startup and audio are confirmed. The user reported severe lag with Legacy graphics. The D9VK/MoltenVK Performance profile includes a correction for a reproduced legacy executable/mapped-buffer stall and a 60 FPS limit. The menu, fullscreen sizing, window controls and pointer alignment are confirmed improved. With updated audio, the Steam overlay disabled and reduced scene load, the latest short race was confirmed smooth at 55–60 FPS. A strict 60 FPS minimum and long-session stability remain unverified. The user previously reported whole-Mac freezes; sustained gameplay remains unverified. This is not a finished CrossOver replacement.

## Run

The local application is generated at `dist/CrossedOver.app`. Open it in Finder and choose **Set Up Steam**. The full package includes independently compiled Wine, a source-built D9VK/MoltenVK Performance profile for TrackMania, and an experimental DXMT overlay. Setup verifies and installs this runtime, creates one environment, and installs official Windows Steam. Thin developer builds require a runtime import first. Sign in inside Steam's own window.

Requirements: Apple silicon, macOS 15 or 26, Intel translation support, at least 8 GiB free before game downloads. Other operating systems are experimental; macOS 28+ is blocked pending a validated translation strategy. Wine is a compatibility layer, not a security sandbox.

## Build

```sh
swift test
python3 scripts/package.py
```

Requires Xcode 26.1.1 / Swift 6.2.1 or compatible. SwiftPM resolves GRDB and Sparkle; exact revisions are committed in `Package.resolved`. The app and CLI have different SwiftPM product names because default macOS filesystems are case insensitive.

```sh
python3 scripts/package.py --debug       # faster local build
python3 scripts/package.py --dmg         # includes source runtime if built locally
python3 scripts/package.py --thin        # developer app requiring a runtime import
dist/bin/crossedover help
```

Local builds use ad-hoc signing and are not notarized. Public signing requires a Developer ID identity, notarization, a source-complete runtime, and the acceptance checks in [release checklist](docs/RELEASE.md). Packaging never publishes anything.

## Runtime options

The CLI's experimental download catalog contains Wine 11.18 with **Legacy** graphics. This community runtime has a known black Steam-window issue and is not selected automatically by the GUI. It is an independently published community build, not copied from CrossOver.app. Its exact download hash and provenance are visible in `Sources/CrossedOverCore/Resources/runtimes.json`.

Build Wine 11.0 from CodeWeavers' published CrossOver 26.3.0 FOSS sources:

```sh
python3 runtime/build.py --jobs 6 --metal --d3d9 --x87 --audio
dist/bin/crossedover runtime-import runtime/output/source-wine
```

See [runtime build notes](docs/RUNTIME.md) first. The source build currently uses pinned community x86-64 dependency libraries as a development shortcut; it is not ready for public redistribution. Optional DXMT 0.80 is an experimental builtin overlay. Merely installing a backend does not certify games.

Imported runtimes appear under Settings → Advanced. **Back up and use** changes an existing environment only after Steam and games close, creates a backup, runs the prefix upgrade, and restores the previous prefix and runtime selection if the upgrade fails.

After building the runtime, run `python3 scripts/package.py --runtime runtime/output/source-wine --dmg` to include it. Runtime identities include a content digest, so an installed version is never silently overwritten.

## CLI

```sh
dist/bin/crossedover host
dist/bin/crossedover runtime-list
dist/bin/crossedover runtime-install
dist/bin/crossedover create
dist/bin/crossedover steam-install
dist/bin/crossedover steam
dist/bin/crossedover games
dist/bin/crossedover benchmark
dist/bin/crossedover install 11020
dist/bin/crossedover launch 11020
dist/bin/crossedover stop
dist/bin/crossedover backup
dist/bin/crossedover diagnostics
```

Use `--root /absolute/path` to isolate a test installation. The GUI supports `CROSSEDOVER_DATA_ROOT` for the same purpose. Default data lives in `~/Library/Application Support/CrossedOver`.

The **Install in Steam** action on the TrackMania demo opens its installation dialog in the managed Windows Steam client. Confirm the download there; completed installations appear automatically in CrossedOver's library.

The monochrome interface uses a fixed sidebar and bordered content panels. **Play** and **Manage** sit together in the game card; **Open Steam** is a separate outlined sidebar button. The game’s **Manage** menu opens Steam properties, shows its files, verifies the installation, or requests uninstall. Steam presents the uninstall confirmation; CrossedOver refreshes the library afterward. **Settings → Windows Steam → Downloads** opens download/update progress. Uninstall and verification are blocked while the game is running.

Steam owns authentication, purchases, DRM, installs, and downloads. CrossedOver reads installed-game manifests and asks Windows Steam to launch games. Native macOS Steam remains separate. No account import, password capture, telemetry, or public Steam API key is involved.

## Design and validation

- [Architecture and interfaces](docs/ARCHITECTURE.md)
- [Runtime build and provenance](docs/RUNTIME.md)
- [Research observations](docs/RESEARCH.md)
- [Validation record](docs/VALIDATION.md)
- [Release checklist](docs/RELEASE.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

Original code: GPL-3.0-or-later. Upstream components retain their own licenses. No affiliation with CodeWeavers, Valve, or Apple.
