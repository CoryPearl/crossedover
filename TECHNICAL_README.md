# crossedover — Technical README

This document explains how the **v1.4.3 source implementation** works, from the macOS interface to Windows process execution. It is intended for contributors and readers who want to understand the whole app. For installation, use the [quickstart](QUICKSTART.md); for system requirements, see the [hardware guidelines](docs/HARDWARE.md).

v1.4.3 removes demo-install affordances and placeholder game cards. New data directories start empty; libraries are populated only by discovered installations and user-added executables. Existing libraries and compatibility profiles are retained, along with Settings search and Minecraft support. Describing a launch path or runtime patch here does not mean every affected game has passed interactive validation. The [validation record](docs/VALIDATION.md) distinguishes automated checks, user observations, and pending work.

## Contents

- [1. What the app does](#1-what-the-app-does)
- [2. Architecture and source map](#2-architecture-and-source-map)
- [3. How Windows code runs on a Mac](#3-how-windows-code-runs-on-a-mac)
- [4. Files, storage, and persistence](#4-files-storage-and-persistence)
- [5. Startup and environment setup](#5-startup-and-environment-setup)
- [6. How installed games become cards](#6-how-installed-games-become-cards)
- [7. What happens when you press Play](#7-what-happens-when-you-press-play)
- [8. Imported Windows executables](#8-imported-windows-executables)
- [9. Graphics and synchronization](#9-graphics-and-synchronization)
- [10. Game tuning, audio, and window controls](#10-game-tuning-audio-and-window-controls)
- [11. Interface design and responsiveness](#11-interface-design-and-responsiveness)
- [12. Game files, mods, downloads, and removal](#12-game-files-mods-downloads-and-removal)
- [13. Backups, repair, and runtime changes](#13-backups-repair-and-runtime-changes)
- [14. Security, accounts, and diagnostics](#14-security-accounts-and-diagnostics)
- [15. Building, packaging, and updates](#15-building-packaging-and-updates)
- [16. Website and download counter](#16-website-and-download-counter)
- [17. Tests and verification](#17-tests-and-verification)
- [18. Troubleshooting by subsystem](#18-troubleshooting-by-subsystem)
- [19. Current boundaries and future integrations](#19-current-boundaries-and-future-integrations)

## 1. What the app does

crossedover is a native macOS library and compatibility manager for Windows software. It provides **Games** and **Apps** views, manages a Wine runtime and its Windows environment, installs official Windows launchers, discovers installed games, and requests launches through the appropriate client. It supports Steam, Epic (including Ubisoft partner handoffs), local `.exe` cards, and a separate Minecraft Bedrock backend in v1.4.0 development.

Wine supplies Windows APIs and process loading. Graphics components translate supported Direct3D calls to APIs available on macOS. Rosetta supplies Intel translation on Apple silicon. crossedover coordinates these components and their configuration; it does not install a Windows virtual machine.

The app's Wine build comes from CodeWeavers' published FOSS sources, with the patches in this repository. It does not copy the proprietary CrossOver application. Store clients, credentials, and games are not bundled. Steam, Epic, and Ubisoft retain their own sign-in, entitlement, download, update, and DRM flows. Minecraft uses Microsoft sign-in and the owner’s real content license.

New Windows installs use a **preferred default environment**. Previously installed environments can remain registered in the same library: game/app cards keep their owning environment, and duplicate store games prefer the default installation. Steam opens in the default environment; Epic and Ubisoft open where their launchers are installed. Minecraft Bedrock uses a separate WineGDK runtime, account helper, prefix, and worlds under `Bedrock/`. The interface does not offer arbitrary environment creation or an environment picker.

## 2. Architecture and source map

The project is a Swift package with a small C archive bridge, a native interface, a shared core, and two command-line executables. [Package.swift](Package.swift) declares the targets and dependencies.

~~~mermaid
flowchart LR
    UI[SwiftUI and AppKit interface] --> Model[AppModel]
    Model --> Core[CrossedOverCore services]
    Core --> DB[(SQLite through GRDB)]
    Core --> Files[Runtime and Windows files]
    Model --> Client[SupervisorClient]
    Client -->|JSON over stdin and stdout| Supervisor[CrossedOverSupervisor]
    CLI[CrossedOverCLI] --> Core
    CLI --> Engine[SupervisorEngine]
    Supervisor --> Engine
    Engine --> Worker[Detached launch worker]
    Worker --> Wine[Wine and Windows launcher or app]
~~~

| Area | Main source | Responsibility |
| --- | --- | --- |
| App entry and menus | [CrossedOverApp.swift](Sources/CrossedOver/CrossedOverApp.swift) | App lifetime, commands, Sparkle setup, and app-owned preview rendering |
| Interface state | [AppModel.swift](Sources/CrossedOver/AppModel.swift) | Setup actions, background refresh, operation history, game sessions, and UI-facing errors |
| Views | [ContentView.swift](Sources/CrossedOver/ContentView.swift) | Libraries, search, grid/list modes, settings, sheets, and confirmations |
| Runtime installation | [RuntimeManager.swift](Sources/CrossedOverCore/RuntimeManager.swift) | Runtime catalogs, import, archive installation, manifests, and validation |
| Windows environment | [EnvironmentManager.swift](Sources/CrossedOverCore/EnvironmentManager.swift) | Prefix creation, graphics configuration, locking, repair, backup, restore, and migration |
| Persistence | [Models.swift](Sources/CrossedOverCore/Models.swift), [Store.swift](Sources/CrossedOverCore/Store.swift) | Codable models and SQLite records |
| Store integration | [SteamService.swift](Sources/CrossedOverCore/SteamService.swift), [EpicService.swift](Sources/CrossedOverCore/EpicService.swift), [UbisoftDiscovery.swift](Sources/CrossedOverCore/UbisoftDiscovery.swift) | Official launcher setup, paths, graphics policy, and launch links |
| Known game recipes | [recipes.json](Sources/CrossedOverCore/Resources/recipes.json) | Per-title graphics profiles, expected processes, status, notes, and fixed arguments |
| Discovery | [VDF.swift](Sources/CrossedOverCore/VDF.swift), [EpicDiscovery.swift](Sources/CrossedOverCore/EpicDiscovery.swift) | Installed-game parsers and merged library |
| Executable cards | [WindowsApps.swift](Sources/CrossedOverCore/WindowsApps.swift) | PE validation, import, card metadata, and run records |
| Launch supervision | [SupervisorProtocol.swift](Sources/CrossedOverCore/SupervisorProtocol.swift) | Request validation, detached workers, launcher routing, and bounded output logs |
| Process observation | [GameProcessDetection.swift](Sources/CrossedOverCore/GameProcessDetection.swift), [process-observer.c](runtime/process-observer.c) | Expected executable names and Windows process snapshots |
| File safety and support | [Security.swift](Sources/CrossedOverCore/Security.swift), [Diagnostics.swift](Sources/CrossedOverCore/Diagnostics.swift), [ManagedStorage.swift](Sources/CrossedOverCore/ManagedStorage.swift) | Containment, hashes, redaction, support reports, and removal-target validation |
| Runtime construction | [runtime/build.py](runtime/build.py), [source-lock.json](runtime/source-lock.json) | Locked components, patches, probes, provenance, and runtime output |
| Distribution | [scripts/package.py](scripts/package.py), [website/](website/) | App/DMG assembly and the separate static website |

The GUI and CLI reuse the same core services. The supervisor is a normal process running as the current user, not a privileged daemon or a security boundary.

## 3. How Windows code runs on a Mac

There are three distinct jobs:

1. **CPU execution:** the included runtime uses Intel code on Apple silicon through Rosetta. The build supports x86 and x64 Windows programs; this does not require macOS to support native 32-bit Mac applications.
2. **Windows API compatibility:** Wine loads Windows Portable Executable (PE) files and dynamic-link libraries (DLLs), maintains Windows registry and filesystem state, and supplies implementations of supported Windows APIs. Its wineserver coordinates shared Windows process resources.
3. **Graphics translation:** the selected backend handles supported Direct3D calls and ultimately presents through macOS graphics facilities.

~~~mermaid
flowchart TD
    PE[Windows x86 or x64 executable] --> Wine[Wine loader and Windows API implementations]
    Wine --> CPU[Intel execution through Rosetta]
    Wine --> System[macOS files, windows, input, and audio]
    Wine --> D3D[Direct3D calls]
    D3D --> Legacy[WineD3D to OpenGL]
    D3D --> D9[D9VK to Vulkan to MoltenVK to Metal]
    D3D --> DXMT[DXMT to Metal]
~~~

Those layers have separate limits. A valid executable can require an unavailable Windows service. A game can reach its menu and still render incorrectly or perform poorly during gameplay. A powerful GPU cannot replace an unsupported kernel driver or anti-cheat implementation.

## 4. Files, storage, and persistence

### Application versus Windows data

The Mac app normally lives at `/Applications/crossedover.app`. Its default data root is separate:

~~~text
~/Library/Application Support/CrossedOver/
├── crossedover.sqlite
├── Runtimes/
│   └── <runtime-id>/
│       ├── runtime.json
│       ├── bin/
│       ├── lib/
│       ├── dxmt/                 # when included
│       ├── dxvk/                 # when included
│       └── share/crossedover/    # observer and owned test programs
├── Environments/
│   ├── <environment-uuid>.lock
│   └── <environment-uuid>/
│       ├── system.reg
│       ├── user.reg
│       ├── dosdevices/
│       └── drive_c/
│           ├── windows/
│           ├── users/
│           ├── Program Files/
│           ├── Program Files (x86)/
│           ├── ProgramData/
│           └── crossedover/
│               ├── Apps/        # copied executable payloads
│               ├── logs/
│               └── backups/     # small game-specific recovery copies
├── Downloads/
├── Backups/                     # explicit full environment backups
└── Logs/                        # operation/launch output files
~~~

A **runtime** is the reusable Wine code and supporting components. A **prefix**, called an environment in the UI, is Windows state: its C: drive, registry, launchers, apps, games, and saves. They are stored separately so importing a runtime does not itself replace a game's files or switch the environment to that runtime.

All installed Windows software shares this prefix's registry and DLL configuration. The Games/Apps and store categories organize the library; they do not isolate programs from one another. A dependency or mod change can affect other software in the same environment.

Steam generally installs under `C:\Program Files (x86)\Steam`; its default games folder is `steamapps\common` below that directory. Epic's default is `C:\Program Files\Epic Games`, but discovery uses each game's actual install location. Ubisoft partner games can live under Ubisoft's own installation directory. Finder actions open these real files.

The development checkout has additional generated data in `.build/`, `.cache/`, `runtime/output/`, and `dist/`. Source downloads, compiler output, test prefixes, and multiple DMGs can make the checkout much larger than the installed Mac app. These generated directories are ignored by Git.

### Database records

GRDB wraps a SQLite `records` table with a composite primary key of `(kind, id)`. Each payload is Codable JSON stored in a blob. The current schema is deliberately small rather than a separate SQL table for every model.

| Record kind | Meaning |
| --- | --- |
| `environment` | Prefix UUID, runtime selection, graphics profile, creation time, and readiness state |
| `game` | Discovered store installation, source, identifiers, install path, size metadata, and optional artwork |
| `operation` | Setup, management, and recovery operation history |
| `session` | Store-game launch request and observed session state |
| `windowsApp` | Persistent imported executable card and its category/path |
| `windowsRun` | Imported executable launch, worker PID, state, timestamps, and exit code |

Refreshing installations transactionally replaces only `game` records belonging to each scanned environment. A `defaultEnvironment` record selects the preferred environment without relying on UUID sort order; cross-environment discovery deduplicates by store and game ID while preserving the owning environment for launches, management, files, renderer choices and session observation. It cannot erase imported `windowsApp` cards. Restoring a backup commits its environment metadata and imported cards together in a SQLite transaction.

Legacy game records without a `source` decode as Steam. Store-aware session identifiers prevent a Steam App ID from colliding with an Epic or Ubisoft identifier. UI preferences such as library view mode use macOS preferences rather than the Windows registry.

## 5. Startup and environment setup

### Native app startup

`AppModel` creates the data directories, opens the database, loads bundled recipes, and marks previously unfinished operation records as interrupted. `start()` runs the host checks, refreshes the library, resumes available game-session tracking, and starts periodic refresh.

[HostInspector](Sources/CrossedOverCore/HostInspector.swift) checks the OS, build architecture, a Metal device, usable Intel translation, and available disk space. Setup requires at least 8 GiB free before game downloads. The current code blocks macOS below 15 and macOS 28 or later; macOS versions outside the targeted 15/26 set are flagged experimental. It reports memory but does not impose a RAM cutoff.

### Selecting and validating a runtime

The packaged app can include `Contents/Resources/BundledRuntime`. First setup imports it into the data root when needed. A thin developer build requires a runtime import. The GUI does not silently substitute a different runtime for an existing environment whose selected runtime is missing.

The older experimental community-runtime catalog remains available to the CLI. It is separate from the preferred source-built runtime; the GUI refuses Steam setup with its known black-window `wine-devel-11.18` entry.

A runtime manifest describes its identifier, architecture, minimum OS, executable paths, graphics profiles, optional observer/Steam loader/x87 helper, provenance, and file hashes. Imports validate the source, copy into a staging directory, validate again, then move it into the installed runtime directory.

Catalog archive installation requires HTTPS, an expected SHA-256, safe extraction, and executable validation. The catalog is bundled with the application. Imported runtimes are explicitly trusted local code, not authenticated merely because they have a manifest.

Import checks manifest-listed hashes. Regular runtime listing and launch validation avoid rehashing the entire runtime on every refresh. Packaging performs a stronger inventory check for the generated runtime, rejecting missing or unexpected regular files as well as hash mismatches. Hashes detect byte changes relative to the manifest; they do not establish publisher identity for an arbitrary imported manifest.

### Creating Windows state

`EnvironmentManager.create()` refuses to create a second environment. It saves a `creating` record before starting Wine, creates `drive_c`, and runs `wineboot -u -r`. It then waits for Wine's deferred registry writes, installs supported graphics extensions, removes the broad Z: mapping, and replaces user-folder links that escape the prefix with local directories.

A new environment initially selects DirectX 9 (`performance`) when the runtime advertises it, otherwise OpenGL fallback (`legacy`). Later profile changes remain explicit.

Successful setup records `ready`. Failed setup leaves `needsRepair` metadata and preserves the directory so the user can repair it instead of losing partially created data. These containment measures reduce accidental filesystem exposure; they do not sandbox Windows software.

### Installing launchers

Steam setup downloads the installer from Valve's configured HTTPS URL, checks its size and `MZ` signature, stages it inside C:, and runs its silent installer. Epic setup downloads the current official MSI, validates its final HTTPS host against an allowlist, checks size and the compound-file header, then runs `msiexec` with a prefix-local installer log. These are format/transport checks, not Authenticode publisher verification or pinned hashes of those changing launcher installers.

Epic and imported executables can prepare an environment without installing Steam. Ubisoft discovery uses an existing installed client; there is no separate automatic Ubisoft installer in the app. Epic can install that partner client as part of its own game setup.

Epic's external launch route also needs its EOSH component. `EpicLaunchSupport` checks the installed host and queries the live 32-bit `HKLM\Software\Epic Games\EOS\MainService` version before accepting an Epic game request. The current minimum is 5.3.0. Missing support produces an actionable error instead of a request receipt followed by a 90-second wait. Library Play and protocol activation follow different paths inside Epic; a working manual launch does not establish external-handler readiness.

Fresh Epic setup and **Repair launch support** use Epic's bundled `Portal/Extras/EOS/EpicOnlineServicesInstaller.exe /install productid=EpicGamesLauncher /quiet`. Repair requires a stopped prefix and holds its operation lock. If neither native .NET 4 nor Wine Mono is installed, it downloads Wine Mono 10.4.1 from its official release and checks the exact size and SHA-256 pinned by the bundled Wine source. Installer-only DLL overrides permit native .NET with a Mono fallback; ordinary launcher/game and Steam overrides remain unchanged. The staged MSI is removed, and vendor installer logs remain local. No account caches are inspected or changed by crossedover. Registration/version checks prove prerequisite setup, not game authorization or visible gameplay.

## 6. How installed games become cards

The library describes **local completed installations**, not every purchase in a user's online store account. crossedover does not need an account API token to list those installations.

### Steam

`SteamDiscovery` finds Windows Steam in the managed C: drive, reads `libraryfolders.vdf`, and follows supported C:-based library paths. It reads `steamapps/appmanifest_*.acf`, checks the installed-state flag and directory, and excludes Steamworks Common Redistributables (`228980`).

The VDF parser handles nested objects, comments, and escaped strings, with an 8 MiB input limit and a nesting limit. Local Steam artwork is preferred, including current content-hash cache directories. Missing artwork falls back to a title-based presentation.

### Epic

`EpicDiscovery` reads `.item` files from:

~~~text
C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests
~~~

Complete base-game entries need valid identifiers, a contained C: installation, and an existing launch executable. Incomplete installs, DLC/child entries, Unreal Engine entries, and known launcher helpers are excluded. Scans are bounded to 5,000 manifests and 8 MiB per normal manifest.

Epic's local manifests do not guarantee cover artwork. The app uses supported local cover/icon files when present and otherwise displays a fallback.

### Epic games installed through Ubisoft

Some games have no normal Epic `.item`. Epic records these in its literally named `Data/ThirPartyManagedApps` directory. The parser validates Ubisoft partner identifiers and correlates them with fixed Ubisoft installation/uninstall sections in Wine's `system.reg`. Partner records are limited to 1 MiB each and 5,000 entries.

The result keeps its **Epic source identity** and adds the Ubisoft game ID. The actual game path, executable, and artwork come from the correlated Ubisoft installation. Equivalent standalone Ubisoft cards are deduplicated by installation directory.

Discovery never executes a record's arbitrary `AdditionalCommandArgs` or follows an arbitrary registry path supplied by that metadata. The supported partner provider is currently Ubisoft Connect, not every possible third-party launcher.

### Refresh and transient failures

`GameLibrary` merges Steam, Epic, and independent Ubisoft results. If one provider throws while its metadata is being rewritten, its prior saved cards are retained while other providers can still update. A successful scan that no longer contains a game removes its card.

When a launcher omits installed-size metadata (including Epic's Ubisoft-managed Brawlhalla), discovery sums regular-file lengths in the game folder without following symbolic links. This runs in the background snapshot and caches complete measurements for up to five minutes; **Refresh Library / ⌘R** requests a fresh measurement. Incomplete, failed, or bounded-out scans remain unavailable rather than displaying a partial total. Cards retain the size during a tracked launch, and properties distinguish an unavailable size from zero bytes. These values describe installed file lengths, not APFS physical allocation or shared launcher storage.

Automatic refresh runs every eight seconds while the Mac app is active and not busy. Manual refresh is available through the interface and ⌘R. Discovery and database work run away from the UI actor; equal snapshots are not reassigned.

## 7. What happens when you press Play

### Requests and detached workers

The GUI sends a versioned JSON request to its sibling `CrossedOverSupervisor` executable over standard input. The request identifies the data root, environment UUID, command, and relevant game/card IDs. It does not carry a shell command or account credentials.

For example, a Steam launch request has this shape. The root and UUID below are illustrative and must identify an existing managed environment in a real request:

~~~json
{
  "version": 1,
  "root": "file:///Users/example/Library/Application%20Support/CrossedOver/",
  "environmentID": "00000000-0000-0000-0000-000000000001",
  "command": "launchGame",
  "appID": "11020"
}
~~~

The supervisor limits request size to 64 KiB, resolves current metadata and the selected runtime, validates the action, and acquires the environment lock. Game launch and management checks vary by route: Epic/Ubisoft launch, verification, and uninstall check that the target game is closed; Steam management and supported game-preparation paths have their own closed-game checks. Imported apps reject duplicate active runs for that card.

For a launch, the parent writes a managed `.launch-<uuid>.json` file and starts a detached copy of its executable with `--launch-worker`. The worker validates and removes that request file, resolves the environment again, acquires the operation lock, and starts Wine with structured arguments. The CLI uses the same engine and can re-execute itself as the worker.

The parent returns an acknowledgement without waiting for a whole game session. The worker drains runtime output independently of the native window. The lock protects preparation and process startup, not the entire duration of a game. Each managed request captures a prefix-local launch generation under that lock. A worker checks the generation immediately before starting Wine. Force Stop changes the generation while holding the lock, so a queued worker cannot reopen Windows after the stop. Old requests without this field are accepted only before the first generation change. See [LaunchGeneration.swift](Sources/CrossedOverCore/LaunchGeneration.swift).

Launcher/app worker logs retain a tail of at most 1 MiB. Shorter setup and management commands use [ProcessRunner](Sources/CrossedOverCore/ProcessRunner.swift), which supports captured output, cancellation, and timeouts. Terminating one timed-out command does not prove every Windows child has stopped. Closing crossedover's native window also does not automatically quit its Windows clients.

~~~mermaid
sequenceDiagram
    actor User
    participant App as AppModel
    participant Sup as Supervisor
    participant Worker as Detached worker
    participant Client as Windows launcher
    participant Obs as Process observer
    User->>App: Play
    App->>Sup: Versioned request and stored IDs
    Sup->>Sup: Validate environment and applicable closed-game checks
    Sup->>Worker: Managed launch request
    Sup-->>App: Request accepted
    Worker->>Client: Start Wine with launcher arguments
    loop Approximately every 3 seconds while tracking
        App->>Obs: Observe Windows processes
        Obs-->>App: Executable basenames and PIDs
    end
    App-->>User: Requested, running, exited, failed, or unknown
~~~

### Store routing

| Installation | Launch behavior | Management behavior |
| --- | --- | --- |
| Steam | Windows `steam.exe -silent -applaunch <id>`, plus any fixed recipe arguments | Steam install/uninstall/properties/validate/download routes |
| Normal Epic | Composite namespace/catalog/artifact URI activated through Windows ShellExecute and Epic’s registered handler | Opens Epic Library; the user chooses Manage → Verify or Uninstall |
| Epic with Ubisoft partner ID | Epic composite launch URI through Windows ShellExecute; Epic handles authorization and the Ubisoft handoff | Ubisoft's own Library controls |
| Independent Ubisoft | `UbisoftConnect.exe` with validated `uplay://launch/<id>/0`, using its own store identity | Ubisoft's own Library controls |

Epic partner cards keep their Epic identity and launch through Epic, including Brawlhalla. Ubisoft still supplies their completed install registration and management controls. Sending a bare Ubisoft link failed in real Brawlhalla checks, so crossedover leaves authorization and partner dispatch to the owning Epic client. Initial account linking remains inside Epic's Library. Current real-game launch/window confirmation remains tracked in the validation record.

Normal Open Epic starts its visible client directly. Game and library URLs activate through Wine’s `start.exe` / Windows ShellExecute, using the client’s registered protocol handler; they are not simply passed as arguments to a second Epic executable. This follows Epic’s [protocol activation guidance](https://assets-unreal2-epic-prod-us2.s3.dualstack.us-east-1.amazonaws.com/original/4X/f/c/4/fc4342c50e1a0abf34943e019ee90bacccc62950.pdf); it does not establish that every partner game accepts a deep link. Any cold Epic game launch, including a partner installation, primes that client before submitting the URI. Windows launchers start with their own executable directory as the working directory. The supervisor computes this hint from observed processes. The primer uses separate output handles: sharing the URI process's `Pipe` caused a Foundation file-handle exception and is covered by a regression test.

### Session tracking

New game sessions share their UUID with the launch Activity operation. `Store.putSession` commits observation and operation status together: request sent, process running, exited, failed, or stopped. `finishOperation` cannot overwrite a newer observed state with a delayed request receipt. Historical launch operations recorded as completed display as Request sent because they only established handoff. This avoids presenting a finished supervisor request as a successful game startup.

The observer is a small Windows program using `CreateToolhelp32Snapshot`. It returns process IDs and executable basenames, not a screenshot or a gameplay measurement. Known recipes provide expected names; other games use a bounded, non-symlink inventory of installed executables, excluding known helpers. The inventory stops at 50,000 visited entries.

| State | Meaning |
| --- | --- |
| `requested` | The launch action was accepted; the game has not yet been observed |
| `running` | A matching Windows executable is present |
| `exited` | A previously observed matching process disappeared |
| `failed` | No matching game appeared within the 90-second startup window |
| `unknown` | Observation is unavailable or repeatedly failed, or tracking was dismissed |

After three observation errors the GUI records unknown status. Dismissing unknown tracking does not stop the Windows process or assert that it exited. On app restart, available unfinished sessions can resume observation.

Basename matching is a heuristic. Games with shared executable names, unusual helper chains, or very large installations can defeat it. A `running` label does not prove a visible, responsive window, working sound, or an acceptable frame rate. The GUI tracks one store-game session at a time.

## 8. Imported Windows executables

An imported `.exe` creates a `WindowsApp` card in Games or Apps; it does not become a store installation. The category changes its presentation, not the Wine execution model.

The importer checks the extension, regular-file status, DOS and PE signatures, machine type, executable/DLL flags, optional-header format, and section-table bounds. It accepts supported x86/x64 PE executables and rejects Windows ARM binaries, DLLs, and incomplete headers. This is structural validation, not malware detection or compatibility certification.

External files are copied into `C:\crossedover\Apps\<uuid>`. The optional containing-folder import preserves nearby DLLs and assets while rejecting links and special files. Files already inside the managed C: drive are referenced in place. Copying is cancellable, and failed imports remove their newly staged payload. Original files outside the prefix are left alone.

Run resolves the stored card, revalidates its executable, sets its containing directory as the working directory, and launches it through the normal Wine loader without Steam branding. Cards do not currently expose arbitrary launch scripts or custom argument strings.

`WindowsAppRun` records track the worker PID, requested/running/exited/failed state, timestamps, and exit code. Missing workers become interrupted so a retry is possible. The worker can outlive the GUI. Programs that spawn a different process and immediately exit may outlive the directly tracked launch.

Installers must be handled explicitly: run the installer, finish its own Windows UI, then edit the card to select the installed executable. Removing a card does not uninstall the application or delete its imported files.

## 9. Graphics and synchronization

### Saved graphics profiles

| Profile | Implementation | Intended role |
| --- | --- | --- |
| DirectX 9–11 (`combined`) | D9VK for Direct3D 9 + DXMT for Direct3D 10–11 | Mixed libraries and components requiring different DirectX versions |
| DirectX 10–11 (`metal`, formerly Metal) | DXMT builtin overlay → Metal; builtin D3D9 fallback | Software requiring DirectX 10 or 11 |
| DirectX 9 (`performance`, formerly Performance) | Native D9VK → Vulkan → MoltenVK → Metal | Software requiring DirectX 9 |
| OpenGL fallback (`legacy`, formerly Legacy) | Wine builtin Direct3D / OpenGL | Compatibility fallback for older DirectX software |

The Performance implementation is based on the pinned D9VK source listed in `runtime/source-lock.json`; the interface describes its DXVK-family path in simpler terms. These profiles are not interchangeable implementations of every DirectX version. crossedover provides no DirectX 12 graphics profile or validated general Direct3D 12 route.

In Wine terminology a **native DLL** is a Windows DLL used instead of Wine's builtin implementation. It does not mean that the DLL is an Apple-silicon-native Mac binary.

`WineConfiguration.environment()` clears relevant inherited Wine/graphics variables, then constructs prefix-specific paths and DLL policy. `WINEDLLOVERRIDES` chooses builtin or native modules; Metal uses `WINEDLLPATH` and the opt-in builtin overlay. Environment setup places supported architecture-specific DLLs and configuration files inside the prefix.

Steam and imported apps use the saved profile. Profile changes require a stopped environment. Existing saved enum values keep their meaning and remain selected after an update. `RuntimeManifest.graphicsProfiles` derives combined-mode availability only when the manifest advertises both the Performance and Metal components; it does not add a new runtime binary. Runtime validation rejects a combined-only manifest. Combined launches enable the DXMT overlay and native D3D9 together, using the existing D9VK configuration. They retain Wine’s OpenGL renderer for older fallback components rather than inheriting the dedicated D3D9 mode’s GDI-only tuning. They do not enable the optional x87 helper, which remains specific to the dedicated Performance mode. CLI `profile combined` selects it, and `smoke --graphics` then checks both D3D9 and D3D11 in both architectures. Unsupported modes cannot change environment metadata. Recipes can request a different profile, but crossedover does not automatically cycle through backends until a game happens to work.

### Epic and Ubisoft use a scoped combination

The current Epic client requires the Metal Direct3D 11 path. Its launch environment uses that path without changing the saved Steam/imported-app profile. When Performance components are available, the same tree can load native Direct3D 9 for games such as Brawlhalla.

D3D9 is intentionally left out of the process-wide DLL override string in this combined environment. Wine's environment overrides would take precedence over per-executable registry choices. Fixed `AppDefaults` policy selects builtin D3D9 for launcher helpers and native/builtin D3D9 for Brawlhalla. This avoids forcing the launcher's D3D9 choice onto its game.

### Per-game renderer recommendations

`RendererRecommendations` runs off the UI actor after discovery, with a five-minute cache keyed by installation identity and metadata. Manual size/library refresh invalidates the cache. Known Steam recipes take precedence and never match an Epic/Ubisoft ID by accident. Other games use their manifest's declared executable, or a bounded search of at most 1,200 entries, six directory levels and six non-helper executables. Each read is capped at 16 MiB. The PE reader checks normal and RVA-based delay imports against file-backed sections, not arbitrary strings or bundled DLL names. Malformed/large/dynamically loaded images can yield no hint.

Direct3D 9 imports suggest the dedicated DXVK mode; 10/11 suggest DXMT; mixed imports suggest the combination. An exclusively detected Direct3D 12 import reports that the runtime lacks that backend, without treating absence of a Direct3D 11 import as proof that no alternate mode exists. Unknown games receive a clearly labeled combined-mode starting point. Recommendations do not change profiles during scrolling or discovery, and aren't compatibility/performance guarantees. Applying a supported Steam recommendation uses the existing stopped-environment guard. Epic/Ubisoft retain launcher-managed policy; Minecraft displays its fixed separate DXMT configuration. CLI `renderers` exposes the same recommendations without account paths.

### MSync and x87

Runtimes can advertise MSync support. `WINEMSYNC` is enabled only when supported and when the prefix's `.crossedover-server-sync` marker is absent. That marker selects standard Wine server synchronization instead. The choice is prefix-local so the GUI, CLI, and workers agree.

Performance can opt into a runtime-provided x87 helper through `ROSETTA_X87_PATH`. x87 is the older x86 floating-point instruction set; PC24 refers to its 24-bit precision mode. The Wine loader patch uses cooperative startup with the pinned PC24-aware helper. It does not replace system Rosetta files. This is a specialized compatibility/performance component, not a guarantee that every CPU-heavy game will improve. [The owned precision probe](runtime/x87-smoke.c) checks the relevant behavior separately from gameplay.

## 10. Game tuning, audio, and window controls

Store discovery is generic. Special changes are deliberately attached to known recipes or executable-specific policies.

A recipe is an explicit configuration for a known Steam App ID: preferred/compatible profiles, expected executable names, compatibility notes, and optional fixed launch arguments. It is not a downloadable game, an entitlement record, or a mechanism that discovers arbitrary compatibility fixes automatically.

| Game | Preparation in this source version |
| --- | --- |
| TrackMania Nations Forever (`11020`) | Performance-oriented settings, window/cursor policy, optional OpenAL Soft replacement, overlay disable policy, and fixed D9VK tuning |
| Counter-Strike 2 (`730`) | Metal profile, a one-time 720p→1600×900 upgrade, preserved later resolutions, scoped Metal presentation timing and a 60 FPS game cap, one-time framed-window/FSR/performance migrations, and native fullscreen/input-bounds policy |
| Brawlhalla | Scoped D3D9 selection and a per-executable native window-controls policy |

[TrackManiaSettings](Sources/CrossedOverCore/TrackManiaSettings.swift) preserves an original settings copy and uses a marker for the initial Performance preset. [TrackManiaAudio](Sources/CrossedOverCore/TrackManiaAudio.swift) verifies the runtime's optional OpenAL component and keeps distinct replaced originals by content hash before installing it for that game. Other applications do not receive that game-specific audio replacement.

[CS2WindowSettings](Sources/CrossedOverCore/CS2WindowSettings.swift) retains small original-file backups and migration markers. Its FSR migration disables internal upscaling once. A separate performance migration disables MSAA/CMAA, ambient occlusion and VSync, lowers textures/particles/shaders/shadow resolution, and selects performance HDR, retaining dynamic shadows, audio and window settings. Only existing numeric keys are changed. Separate markers preserve later user choices. Preparation runs only after the supervisor confirms CS2 is closed. A recipe's 60 FPS cap is an upper limit, not an achieved minimum. The old 720p dimensions upgrade once to 1600×900; fixed `-w`/`-h` launch flags have been removed so later Video settings survive. Metal/combined profiles pass a managed `DXMT_CONFIG_FILE` whose `[cs2.exe]` section requests `d3d11.preferredMaxFrameRate = 60`; other executables keep their normal timing. This is presentation scheduling, so it does not replace the game’s bounded render-work cap. See [DXMT’s pinned configuration](https://github.com/3Shain/dxmt/blob/v0.80/dxmt.conf). CS2 leaves Steam’s official overlay handling at its defaults; its policy deletes the forced-disable registry entries from earlier builds. TrackMania retains its separately tested overlay-disable policy. This Steam setting is distinct from the DXMT DLL overlay used by the graphics runtime.

The Wine Mac Driver patches in [runtime/patches/](runtime/patches/) address cursor capture, fullscreen sizing, fixed-window fullscreen eligibility, caption preservation, and Steam host identity. The Brawlhalla-only `ForceWindowControls` option is default-off in the runtime and opt-in through its app policy. It adds native controls to eligible main windows, including shaped and layered game content, while preserving the content mask/alpha and excluding helpers, owned dialogs and inactive tools. Disabled main windows keep a title bar with disabled buttons. Desktop frames are constrained to the display work area so a screen-sized content request cannot push the title bar offscreen; native AppKit fullscreen transitions keep their own frames. The owner confirmed Brawlhalla's buttons, minimize and fullscreen work with the new runtime. Importing the runtime alone does not activate it in an environment still using an older runtime.

The optional named Steam loader and branding flag label Steam's Mac host as crossedover Steam. Generic Windows apps and Epic/Ubisoft launch through the normal loader without that Steam identity. Windows game titles still belong to their applications.

## 11. Interface design and responsiveness

The interface uses SwiftUI, with AppKit where native behavior matters. `AppModel` is `@MainActor` and observable, while discovery, large file work, and image decoding are moved off the interface's execution path.

Games combines discovered store installations and imported game cards. Apps shows imported tool/app cards. Search, store filters, and grid/list modes operate on local library data. The sidebar's Game Launchers menu groups Steam, Epic Games, and installed Ubisoft Connect, separately from each game's Play action. The macOS menu bar reuses the same actions and availability checks. Steam and Epic offer setup when missing; Ubisoft Connect requires an existing installation. Launcher executable discovery runs in the background refresh snapshot, so opening the menu does not scan the filesystem.

Responsiveness work has several independent parts:

- Refresh happens in background work and assigns only changed results, avoiding repeated full-library redraws and database writes.
- [LibraryArtwork](Sources/CrossedOver/LibraryArtwork.swift) uses a serial actor and ImageIO to decode/decompress thumbnails up to 640 pixels. Its cache has 64-item/64 MiB limits, plus bounded short-lived misses.
- Library grids and lists retain lazy views, so offscreen cards do not all need immediate image work.
- [NativePageScroll](Sources/CrossedOver/NativePageScroll.swift) hosts Settings and Activity in `NSScrollView`. It measures document height when content or viewport width changes and disables intrinsic-size feedback and viewport safe-area propagation. Scrolling moves the clip view instead of repeatedly relaying size constraints through SwiftUI.
- Launch workers drain output continuously but throttle bounded-log rewrites to roughly four per second, with a final flush.

Settings uses a separate local query, matched against setting names and topic keywords. Multiple words must all match a group. Recovery, runtime and support results open inside Advanced automatically; clearing the query restores its previous disclosure state. The search header stays outside the native scroll document. `NativePageScroll` resets to the top only when the query changes, retaining its cached size measurement during scrolling. ⌘F focuses the current Settings or library search; queries remain independent.

The app's own `--render-preview` mode uses SwiftUI ImageRenderer and can preload artwork for deterministic interface previews. These renders verify presentation; they are not screenshots of a Windows game or evidence of gameplay performance.

## 12. Game files, mods, downloads, and removal

Per-game file actions re-resolve the installation before opening Finder. [GameFiles](Sources/CrossedOverCore/GameFiles.swift) also locates contained Windows Documents folders. Mods are normal files in the Windows environment; mod loaders and managers may need their own dependencies. Steam Workshop subscriptions continue through Windows Steam for titles that support Workshop.

The app does not implement a separate game downloader. Steam, Epic, and Ubisoft download and update their games. Open Download Folder opens the relevant default installation folder in Finder; the separate Steam/Epic download actions open the vendor client. Per-game Show Files uses the discovered path when the default folder differs.

Verification and uninstallation are vendor operations. Steam has dedicated routes. Epic and Ubisoft management actions open their own controls and require the user to finish the action there. crossedover does not report an acknowledgement as a completed uninstall. A subsequent successful discovery scan removes a card after its installation metadata/files disappear.

The full app uninstaller requires the managed Windows environment to be stopped. It validates the fixed default data root and writable app bundle, moves app data and the app to Trash, clears app preferences, and exits. Custom/linked data roots and read-only DMG app locations must be managed in Finder. If moving the app itself fails after data was trashed, the user is told to finish removing the app manually. Storage is reclaimed when Trash is emptied.

Dragging only the Mac app to Trash leaves its separate Windows data behind. Native Mac Steam/Epic installations are outside this managed removal flow.

## 13. Backups, repair, and runtime changes

### Operation locking

`EnvironmentLock` uses an advisory `flock` on a sibling prefix lock file, opened without following a symlink. This coordinates GUI, CLI, and supervisor operations across processes. Runtime/profile changes, repair, backup, and restore additionally require Wine to be stopped. A native window closing is not proof that its Windows clients have exited.

### Full backups

Full backups are **manual only**. Create Backup and Clear Backups live together in Settings → Backups. A backup copies the whole prefix with APFS clone support and saves `environment.json` plus `windows-apps.json`. It records the runtime selection rather than duplicating every installed runtime or the entire application database.

Restore requires the matching environment UUID and an available referenced runtime. It validates card paths, stages the saved prefix, renames the current prefix aside, installs the staged prefix, and restores environment/card metadata transactionally. Errors in that swap attempt restore the previous prefix. This is not a claim of a single crash-atomic transaction spanning SQLite and the filesystem.

Older backups without imported-card metadata restore an empty imported-card library. Store installations are rediscovered. APFS clones can share blocks, so apparent folder size and actual reclaimable space differ.

Clear Backups moves the full-backup directory to Trash. Small game-settings/audio recovery copies inside the prefix are a separate mechanism and do not mean automatic full backups are enabled.

### Runtime migration and repair

Importing a runtime and selecting it are separate actions. Migration requires a stopped environment, marks it as needing repair before updating it in place, runs Wineboot, reinstalls extensions, reapplies containment, and records the new runtime when successful. It preserves the saved graphics profile when the replacement supports it.

An unsuccessful migration preserves files and blocks normal launches until repair or an explicit manual restore. It does not create a full backup automatically. Repair runs Wineboot and restores the managed setup invariants using the selected runtime. Neither repair nor migration promises to repair a game's own corrupted files or account state.

**Close Windows Steam** requests Steam shutdown. The bottom **Stop & close Windows** action cancels and awaits the native operation, cancels game observation, then requests Force Stop. The bottom bar appears from the initial Play click, persists through requested/running/unknown tracking, and also covers imported executable runs. Its indeterminate spinner does not estimate a completion percentage. A running process does not prove a usable game window.

Force Stop waits up to ten seconds for an in-flight preparation/worker lock, invalidates queued workers, sends `wineserver -k`, and confirms shutdown with `wineserver -w`. Only after confirmation does it mark active sessions and app runs for this environment stopped. If shutdown fails, the UI retains the session and resumes observation so the user can retry. Late observer replies cannot restore cancelled tracking. The client permits a longer, 60-second timeout for this action. It uses the selected runtime and prefix, rather than a global Wine kill; the GUI sends this scoped action to every registered Windows environment, closing their games, apps, and launchers; unsaved work can be lost. Native Mac launchers are outside this action.

## 14. Security, accounts, and diagnostics

Windows programs run with the Mac user's permissions. A contained prefix is **not a malware sandbox**, and the unprivileged supervisor does not change that. Users must trust imported programs and runtimes.

`FileSafety.containedURL()` rejects unsafe relative paths and resolves existing symlink ancestors, including when the final file does not yet exist. Managed removal separately rejects custom or linked roots and unrelated application bundles. These checks protect management operations from unintended paths, not the whole host from arbitrary Windows code.

The C libarchive bridge requires an empty staging directory, rejects unsafe archive paths, hard links and special files, constrains symlinks, limits entry count to 150,000, and limits declared extraction size to 12 GiB. Runtime downloads are hash-checked before extraction. Source/build provenance is recorded separately from a user's Windows state.

Account entry stays in the official clients. crossedover does not provide password fields, import login stores, request a public Steam API key, or implement a service for collecting credentials. Clients can still create their own local account files and network connections inside the Windows environment.

Launcher/app output logs are bounded, but raw runtime output can contain private information. [DiagnosticsService](Sources/CrossedOverCore/Diagnostics.swift) exports selected host/environment information and recent operation/session/run records, not launcher authentication files or raw runtime logs. [Redaction](Sources/CrossedOverCore/Security.swift) removes the home-path prefix and entire recognized authentication-bearing lines, including exchange codes and token/cookie markers. Redaction is a best-effort filter; review reports before sharing them.

The app does not upload diagnostics automatically. The website download counter is aggregate release-asset data, not client telemetry.

## 15. Building, packaging, and updates

### Native app

Use a compatible Swift 6/Xcode toolchain and macOS SDK. The package targets macOS 15. GRDB and Sparkle revisions resolve through [Package.resolved](Package.resolved).

~~~sh
swift test --jobs 2
swift build -c release --jobs 2
python3 scripts/package.py --skip-build --thin --dmg
~~~

That example makes a thin developer app which requires an explicit runtime import. The native package does not compile Wine as part of `swift build`.

### Source runtime

After installing the prerequisites in [runtime build notes](docs/RUNTIME.md):

~~~sh
python3 runtime/build.py --jobs 2 --metal --d3d9 --x87 --audio
python3 scripts/package.py --skip-build --dmg
~~~

The runtime builder uses [source-lock.json](runtime/source-lock.json) for component URLs, hashes, and source revisions. The current component set includes Wine 11.0-cx26.3.0, DXMT 0.80, a pinned D9VK revision, MoltenVK 1.4.2, the selected x87 helper, and optional OpenAL Soft 1.25.2. Its runtime ID includes a digest derived from the output file-hash inventory. `build-provenance.json` records component and patch information.

The v1.4.3 runtime still uses some pinned prebuilt dependency components. Independent source-complete dependency builds, licensing/source delivery, and the other [public-release gates](docs/RELEASE.md) remain separate work. Being based on published FOSS source does not by itself complete those gates.

### App bundle and DMG

Packaging copies the GUI and supervisor, the core resource bundle, Sparkle, notices/licenses, the icon, and optionally the validated runtime into an app bundle. It sets version information, signs nested Sparkle code, the supervisor, and the app, and verifies the result. CLI output is placed in `dist/bin`.

The DMG contains the app, an Applications shortcut, a self-contained Start Here guide, hardware guidelines, and license information. Packaging creates artifacts locally; it does not push Git commits, upload a release, change repository visibility, or notarize the application.

The default signature is ad hoc. A public Developer ID/notarization workflow is a separate requirement. `VERSION`, `AppVersion`, documentation, and package metadata must stay consistent.

### Updates

Sparkle is initialized only when the bundle includes both an update feed and public signing key. Packaging reads `CROSSEDOVER_UPDATE_FEED` and `CROSSEDOVER_UPDATE_PUBLIC_KEY`, requires both together, and requires an HTTPS feed. The local build leaves updates unconfigured and automatic update flags disabled by default.

Updating the Mac app is distinct from selecting a new Wine runtime or updating Steam/Epic. A runtime import must not silently migrate a running game environment.

## 16. Website and download counter

The website is a separate plain HTML/CSS project in [website/](website/). Its images are app-owned interface previews. `website/build.py` copies the site into `website/dist`; it does not publish source caches, runtimes, account data, or the whole repository.

The Pages workflow builds on relevant main-branch changes, manual dispatch, published releases, and a roughly six-hour schedule. GitHub scheduling can be delayed. The configured site is `https://corypearl.github.io/crossedover/`; deploying updated source is a separate step from editing it locally.

`website/download_stats.py` uses an authenticated build-host GitHub CLI call to read release asset counts. It counts uploaded DMGs on published releases, including prereleases, excludes drafts and other assets, and emits only an aggregate count, release count, timestamp, schema version, and metric description.

The static HTML renders that snapshot and can include `downloads.json`. Repeat downloads count; the metric is not unique people, installations, or active users. The browser receives no repository token and does not call the private release API. Failure to fetch statistics displays unavailable rather than a fabricated zero.

During private evaluation, public Pages hosting does not grant visitors access to private release assets. The website explains the download-access requirement.

## 17. Tests and verification

| Layer | Checks | What it does not prove |
| --- | --- | --- |
| Core tests | Models, VDF/manifests, path safety, runtime validation, recovery, PE imports, routing, duplicate-run guards, and redaction | Successful login or real game compatibility |
| Native build/package | Swift compilation, bundle layout, signatures, runtime inventory, and DMG contents | Apple notarization or gameplay performance |
| Runtime integration | Owned x86/x64 executables, graphics readbacks, textures, x87, audio progression, observation, backup/restore | Every Windows API or a long game session |
| Epic/Ubisoft fixture | Owned launcher stand-ins, URI dispatch, partner discovery, graphics policy, management routing, uninstall discovery | Official store authentication, entitlements, or real game UI |
| Executable-card fixture | Imports with sidecars, registry I/O, launch state, duplicate rejection, source removal, and relaunch | Compatibility of arbitrary installers/tools |
| Website checks | Version/link consistency and release-count aggregation | A complete visual check in every browser |

The current local core suite has 64 tests. The expanded owned runtime integration and packaged Epic/Ubisoft fixture passed for the current candidate. These results are recorded in [VALIDATION.md](docs/VALIDATION.md), rather than promoted into a universal compatibility label.

Useful verification entry points:

~~~sh
swift test --jobs 2
python3 -m unittest discover -s runtime -p 'test_*.py'
python3 -m unittest discover -s website -p 'test_*.py'
python3 scripts/check-release.py
python3 scripts/integration.py --runtime runtime/output/source-wine --cli .build/release/CrossedOverCLI
python3 scripts/epic-integration.py --app dist/crossedover.app
python3 scripts/windows-app-integration.py --app dist/crossedover.app
~~~

The integration scripts create separate test data roots. They may stop their own test prefix during cleanup. Do not substitute a user's live environment for those fixtures. For manual CLI work, use `--root /absolute/test/path`; the GUI supports `CROSSEDOVER_DATA_ROOT`. Custom-root installations are intentionally excluded from the full in-app removal flow.

CI runs core tests, native builds, thin packaging, and website checks. It does not download users' games or validate store accounts. Owned program success and a green CI run are not substitutes for launch/input/audio/fullscreen checks and sustained gameplay on real supported Macs.

## 18. Troubleshooting by subsystem

| Symptom | First place to investigate |
| --- | --- |
| Game missing from Games | Its completed-install metadata and actual contained C: path; use the provider parser, then manual refresh |
| Epic-installed Brawlhalla missing | Epic partner record, Ubisoft install registration, installed bootstrapper, and deduplication |
| Play opens a launcher only | Correct store/partner route, initial account linking, prerequisites, the worker log, and process observation |
| Running status but no visible game | Treat observation as process evidence only; inspect the game's own client/window and graphics compatibility |
| Blank Epic UI | Metal-capable runtime and Epic-specific graphics environment; the saved Steam profile alone does not describe Epic's backend |
| Missing native window buttons | Game display mode, selected runtime version, and executable-specific Mac Driver policy; candidate fixes require a fresh process |
| Poor race/match performance | Actual gameplay workload, resolution/detail, backend choice, memory/power conditions, and game-specific validation |
| Imported installer runs again | Retarget the card to the installed executable and check required sibling files/dependencies |
| Another operation is using the environment | Prefix lock holder or unfinished operation; avoid changing the runtime beneath an active client |
| Large disk footprint | Separate app/data roots, game downloads, installed runtime versions, manual backups/Trash, and development caches |
| Support report needed | Use the selected diagnostic preview/export; review it rather than uploading raw launcher logs |

## 19. Current boundaries and future integrations

The implementation has a local library, not a universal Windows compatibility guarantee. Important boundaries are:

- One default environment for new installs, retained installations in a unified library, and one tracked store-game session in the GUI.
- Contained C:-based store discovery, not arbitrary external Windows drive libraries.
- Supported x86/x64 `.exe` cards, not general Windows ARM packages or automatic dependency resolution.
- Experimental Direct3D 9/10/11 coverage; no exposed DirectX 12 profile or validated general Direct3D 12 launch route.
- No guarantee for kernel anti-cheat, DRM, unsupported Windows services, or every Steam/Epic/Ubisoft title.
- No supported local Windows Xbox app, PC Game Pass installation flow, or Minecraft Bedrock integration. Xbox Cloud is a browser shortcut, not a local game provider.
- Brawlhalla card launch and native window controls have user confirmation on the development Mac. Other game/runtime changes still need their own validation, as recorded in the validation record.
- Current testing centers on an M4/16 GB Mac. The short TrackMania 55–60 FPS result is not a guaranteed minimum or a benchmark for other games or Macs.

Adding another launcher requires more than a sidebar button: official setup/authentication, bounded installation discovery, validated launch/manage routes, process tracking, file access, appropriate runtime behavior, uninstall discovery, and real account/game testing. The v1.4.0 Bedrock development backend adds separate runtime/account/licensing integration and preserves worlds on game uninstall; live account/game validation remains required. See [the assessment](docs/XBOX_AND_BEDROCK.md).

For source changes, keep parsing and lifecycle logic in `CrossedOverCore`, orchestration in `AppModel`, and presentation in the GUI views. Never turn store metadata into an arbitrary shell command. Add tests for meaningful parsing/lifecycle boundaries, use owned integration programs, and record actual game observations separately from the implementation's intended behavior.


## Epic partner launch handoff

Epic partner games use a separate compatibility queue in `EpicLaunchQueue.swift`:
the public validated launch URI is serialized as Unix seconds plus `|` plus URI
in the `PendingUri` REG_SZ value under `HKCU\Software\Epic Games\EpicGamesLauncher`. This is a compatibility interface observed in the installed client, rather than a general Xbox or Ubisoft API. The supervisor holds
the environment lock, checks prerequisites and the game’s stopped state, writes
an app-owned receipt, and starts Epic with `-SkipBuildPatchPrereq -forwarduri`.
The detached worker checks its generation and receipt again before startup.
Epic retains ownership and generates any partner authentication itself. This
route never reads or replays an exchange code. Generic Epic games retain the
Windows shell route. Stop removes only a value matching the app’s receipt,
preserving a newer external request, and handles Windows CRLF output from
`reg.exe`. A request acknowledgement still means Requested; process observation
is required for Running.

## Minecraft backend in v1.4.0 development

`BedrockService.swift` implements an independent backend boundary, outside the Steam/Epic supervisor. `BedrockBackend.load` validates a pinned schema/revision, `signed-xvd-v1` package verification policy, required components, every file digest and the exact file/symlink inventory. Verification runs off the UI actor. The worker receives a minimal environment with `BEDROCK_HOME=<CrossedOver root>/Bedrock` and `BEDROCK_BUNDLE=<verified backend>`, without inherited Wine/DYLD/Python overrides. A bounded JSON stream maps only known states and progress to reviewed UI text; arbitrary account strings never become status or activity entries. Unknown states, oversized lines, malformed progress, or a worker exit without a terminal state fail the session.

`MinecraftLauncherView` is opened from the shared Game Launchers menu or Settings. Play owns one worker through account checks, download, preparation and observed gameplay. Stop terminates that worker; the worker unwinds its own subprocess groups/helper/prefix, and the native app waits for its exit before clearing the active state. Steam/Epic sessions are independent. The app stays alive after its window closes during Minecraft and prevents quit/uninstall while its own session is active; uninstall also checks the backend onboarding lock. Microsoft sign-out preserves worlds.

`runtime/bedrock/prepare.py` builds from pinned Bedrock for Mac/WineGDK/Xodus sources, applies the tracked compatibility patch, tests the helper, freezes Python, and stages only allowed components. `scripts/package.py --bedrock-backend` verifies the staged inventory, signs nested code, and records the signed hashes. `--output` creates a separate local preview app. No account, game or Microsoft DLL enters the backend. Account data uses the `crossedover Minecraft` Keychain service. The local preview requires macOS 26, Apple silicon, Rosetta and an owned Windows Bedrock edition.

The package downloader uses a separate client with no account headers/cookies.
Account and license traffic remains certificate-verified HTTPS. Catalog package
candidates may use HTTPS or the two official HTTP asset origins on port 80;
redirects keep that restriction and hosts are never rewritten. Every candidate
must pass Microsoft's RSA-PSS/SHA-256 header signature, its signed root hash,
every parent/child hash-tree page and all data-page hashes before the XVD or
filesystem parsers consume it. The complete archive stays in private temporary
storage through verification/extraction, then is removed. Only the required
verified metadata prefix is retained with the game for later ownership checks.
Unsupported layouts and any failed verification stop installation. Public keys,
source provenance and owned tamper-test fixtures live under
`runtime/bedrock/verification/`; test signing keys are never trusted by production.
The full live package passed signature/tree/data verification, extracted using
the owner's real license, and launched. The owner confirmed local-world play,
controls/sound, saving and normal quit. Card-based repeat launch, world reopen,
window behavior and clean-machine tests remain separate release checks. See [the backend guide](runtime/bedrock/README.md) and
[current assessment](docs/XBOX_AND_BEDROCK.md).

The Games library checks Minecraft’s offline installation status on startup, library refresh (including ⌘R), and after a setup/play session ends. A ready installation adds a Minecraft card or list row with Play and launcher options, and participates in search, counts and the Minecraft filter. Routine refreshes reuse the verified backend rather than hashing the entire runtime again; Play verifies runtime bytes again. Failed downloads do not add an installed card.

The owned window-controls fixture (`python3 scripts/window-controls-integration.py`) checks actual AppKit close/minimize/zoom button presence and enabled state, fullscreen eligibility and title-bar placement for 32/64-bit windows. Its diagnostic runs only for an explicit test environment flag and owned fixture title, on the receiving window; it does not enumerate or inspect the user’s game windows.

CS2 opts into `CursorClippingFollowsWindow` in its own Mac Driver settings.
The driver saves a foreground window's full-client capture rectangle before a
native frame change. After the Win32 move/resize messages finish, it follows the
new client bounds only if capture still equals the old rectangle. Per-monitor
DPI context keeps client and cursor coordinates comparable. Smaller/point
captures, released or replaced captures, and changed foreground windows are
preserved. Other games retain the default-off policy. The owned input-bounds
fixture triggers native geometry changes only on its receiving window, gated
by both an explicit test flag and fixture title; it sends no mouse events and
never enumerates game windows. Real mixed-display behavior requires its own
interactive check. The owner confirmed CS2 menu clicks align across the larger
monitor after moving the running game with this runtime.

Minecraft’s grid card and list row load the official grass-block logo from the
owner’s installed game (`LargeLogo.png`, with smaller-logo fallbacks). Path
resolution and image decoding run away from UI layout, using the same bounded
artwork cache as the other games. No Minecraft asset is bundled with the app.
