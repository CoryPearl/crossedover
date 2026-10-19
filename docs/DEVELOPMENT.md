# Developer reference

For installation, see [the v1.0.0 quickstart](../QUICKSTART.md). The notes below describe implementation and runtime limitations.

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

Counter-Strike 2 uses the **Metal** graphics profile (DXMT Direct3D 11). Its launch recipe requests a Steam restart when the environment is using a different profile. First-run Steam prerequisite installation can delay the game process. CS2 starts in windowed mode for native Mac window controls with a 60 FPS cap; this is a limit, not a verified achieved frame rate. A backed-up conversion of its existing video configuration restores a framed window. Each launch requests a 1280 × 720 desktop window so a saved fullscreen-sized viewport cannot hide its title bar; use the native green button to expand it. Other graphics-quality preferences are preserved. The bundled patched Wine Mac Driver opts CS2 into native fullscreen on fixed-size windows while retaining mouse capture for aiming. A separate backed-up clarity migration disables the game’s internal FSR upscaler once, without changing later user choices or the prefix’s Retina coordinate policy. Green-button behavior and the sharper image still need visual confirmation. Actual match performance and long-session stability remain unverified.

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

The **Install in Steam** action on the TrackMania demo opens its installation dialog in the managed Windows Steam client. Confirm the download there; completed installations appear automatically in crossedover's library.

The monochrome interface uses a fixed sidebar and bordered content panels. The library automatically refreshes every four seconds and shows completed installations from the managed Windows Steam libraries, sorted by name. Multiple games use an adaptive card grid with Steam's cached artwork or a title fallback. Incomplete downloads and Steamworks Common Redistributables are excluded. **Play** and **Manage** sit together in each game card; **Open Steam** is a separate outlined sidebar button. The game’s **Manage** menu opens Steam properties, shows its files, verifies the installation, or requests uninstall. Steam presents the uninstall confirmation; crossedover refreshes the library afterward. **Settings → Windows Steam → Downloads** opens download/update progress. Uninstall and verification require a process check; if the game cannot be tracked, use Steam to manage its files. Listing or requesting a launch does not certify compatibility.

Steam owns authentication, purchases, DRM, installs, and downloads. crossedover reads installed-game manifests and asks Windows Steam to launch games. Native macOS Steam remains separate. No account import, password capture, telemetry, or public Steam API key is involved.

## Design and validation

- [Architecture and interfaces](docs/ARCHITECTURE.md)
- [Runtime build and provenance](docs/RUNTIME.md)
- [Research observations](docs/RESEARCH.md)
- [Validation record](docs/VALIDATION.md)
- [Release checklist](docs/RELEASE.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

Original code: GPL-3.0-or-later. Upstream components retain their own licenses. No affiliation with CodeWeavers, Valve, or Apple.
