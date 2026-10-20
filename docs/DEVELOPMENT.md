# Developer reference

For installation, see [the v1.4.0 quickstart](../QUICKSTART.md). For a full implementation walkthrough, see the [Technical README](../TECHNICAL_README.md). The notes below describe build tools and runtime limitations.

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

The CLI's experimental download catalog contains Wine 11.18 with **OpenGL fallback** graphics (`legacy`). This community runtime has a known black Steam-window issue and is not selected automatically by the GUI. It is an independently published community build, not copied from CrossOver.app. Its exact download hash and provenance are visible in `Sources/CrossedOverCore/Resources/runtimes.json`.

Build Wine 11.0 from CodeWeavers' published CrossOver 26.3.0 FOSS sources:

```sh
python3 runtime/build.py --jobs 6 --metal --d3d9 --x87 --audio
dist/bin/crossedover runtime-import runtime/output/source-wine
```

See [runtime build notes](docs/RUNTIME.md) first. The source build currently uses pinned community x86-64 dependency libraries as a development shortcut; it is not ready for public redistribution. Optional DXMT 0.80 is an experimental builtin overlay. Merely installing a backend does not certify games.

Imported runtimes appear under Settings → Advanced. **Use runtime** changes an existing environment only after Steam, games, and Windows apps close. It updates the prefix in place without creating a full backup. On failure, the environment is marked as needing repair and launches are blocked; files stay in place. Make a manual backup first if you need a complete restore point.

Counter-Strike 2 uses the **DirectX 10–11** renderer (`metal`, DXMT Direct3D 11). Its launch recipe requests a Steam restart when the environment lacks that path; the combined DirectX 9–11 mode is also compatible. First-run Steam prerequisite installation can delay the game process. CS2 starts in windowed mode for native Mac window controls with a 60 FPS cap; this is a limit, not a verified achieved frame rate. A backed-up conversion of its existing video configuration restores a framed window. Each launch requests a 1280 × 720 desktop window so a saved fullscreen-sized viewport cannot hide its title bar; use the native green button to expand it. Other graphics-quality preferences are preserved. The bundled patched Wine Mac Driver opts CS2 into native fullscreen on fixed-size windows while retaining mouse capture for aiming. A separate backed-up clarity migration disables the game’s internal FSR upscaler once, without changing later user choices or the prefix’s Retina coordinate policy. Green-button behavior and the sharper image still need visual confirmation. Actual match performance and long-session stability remain unverified.

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

New installations start with empty Games and Apps libraries. Choose a launcher, install games through your own account, or add a local .exe. There is no preinstalled game or promoted demo. The CLI `install APP_ID` command explicitly opens that game’s install dialog in Windows Steam; completed installations appear automatically.

The monochrome interface uses a fixed sidebar and bordered content panels. The library checks for library changes every eight seconds while active, using background discovery and database work; unchanged results do not redraw the library and shows completed installations from the managed Windows Steam libraries, sorted by name. Multiple games use an adaptive card grid with Steam's cached artwork or a title fallback. Incomplete downloads and Steamworks Common Redistributables are excluded. **Play** and **Manage** sit together in each game card; **Open Steam** is a separate outlined sidebar button. The game’s **Manage** menu opens Steam properties, shows its files, verifies the installation, or requests uninstall. Steam presents the uninstall confirmation; crossedover refreshes the library afterward. **Open download folder** opens `steamapps/common` in Finder; **Steam Downloads** opens download/update progress. Full environment backups are manual only; Settings includes backup cleanup and full app/data uninstall. Uninstall and verification require a process check; if the game cannot be tracked, use Steam to manage its files. Listing or requesting a launch does not certify compatibility.

Steam owns authentication, purchases, DRM, installs, and downloads. crossedover reads installed-game manifests and asks Windows Steam to launch games. Native macOS Steam remains separate. No account import, password capture, telemetry, or public Steam API key is involved.

## Design and validation

- [Architecture and interfaces](docs/ARCHITECTURE.md)
- [Runtime build and provenance](docs/RUNTIME.md)
- [Research observations](docs/RESEARCH.md)
- [Validation record](docs/VALIDATION.md)
- [Release checklist](docs/RELEASE.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

Original code: GPL-3.0-or-later. Upstream components retain their own licenses. No affiliation with CodeWeavers, Valve, or Apple.

## Mods and Steam host identity

The per-game **Mods & files** sheet opens the game's discovered install folder or a contained Windows Documents directory. Steam's Properties → Installed Files → Browse continues to use Wine's built-in explorer. Mods use their normal Windows paths; external mod managers and DLL overrides are not configured automatically.

The optional runtime `steamLoaderRelativePath` points to a copy of Wine's native loader named `crossedover Steam`, beside its ordinary Wine modules. Steam launch and installation requests use it; older manifests fall back to the ordinary loader. The opt-in macOS naming patch covers direct Steam startup, child Steam/web-helper processes, the application menu, and generic Steam/Wine captions, while preserving game and descriptive dialog titles.

`runtime/modding-smoke.c` verifies a Windows file round trip and can exercise shell folder opening with `--browse`. It uses a temporary test folder under `C:\crossedover\modding-smoke`; compile it for Windows with MinGW and run only in an isolated managed prefix.


## Windows app and game cards (v1.1.0)

crossedover now runs local x86/x64 Windows .exe files alongside its Steam integration, with separate Games and Apps libraries. Use Add .exe in the GUI. For development, `crossedover app-add /path/to/app.exe --folder` creates a persistent Apps card (use `--game` for Games), `apps` lists the cards, `app-run UUID` requests a detached launch, and `app-runs` reports persisted results. These commands use the managed runtime and environment; Steam installation is optional. Cards can be retargeted after an installer finishes. Additional dependencies and compatibility remain app-specific.

## Epic Games (v1.2.0)

`epic-install` installs the official Windows MSI; `epic` opens its library. `games` discovers both stores. `epic-launch APPNAME` uses Epic’s composite launch URI. `epic-manage`, `epic-verify`, `epic-uninstall`, and `epic-downloads` open the official client; verification, removal, and download progress remain under its own controls. Never pass account credentials to the CLI.

Run `python3 scripts/epic-integration.py` for the owned launcher handoff fixture, or add `--app dist/crossedover.app` to use packaged binaries/runtime. It tests complete/incomplete manifest discovery, URI handoff, a real D3D11 pixel-readback child, management library routes, and removal discovery in a temporary prefix without accounts. It does not test Epic authentication or real store downloads. Stop only that test prefix during cleanup.
