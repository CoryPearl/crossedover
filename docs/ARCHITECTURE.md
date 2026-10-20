# Architecture

For a consolidated walkthrough of the current implementation, see the [Technical README](../TECHNICAL_README.md). The notes below also retain context from earlier development stages.

`CrossedOver` is the SwiftUI app. `CrossedOverCore` owns Codable models, runtime installation, validation, SQLite records through GRDB, Wine configuration, Steam VDF and Epic installation-manifest parsers, process execution, backups, migrations, and diagnostic redaction. `CrossedOverSupervisor` accepts one versioned JSON request on stdin and returns a JSON reply. `CrossedOverCLI` exposes the same services for development and verification.

## Data flow

1. HostInspector verifies OS, Metal, disk capacity, and Rosetta execution.
2. RuntimeManager downloads a pinned archive over HTTPS, verifies SHA-256, extracts into staging through libarchive, validates executable paths, and atomically installs it.
3. EnvironmentManager persists a UUID before Wine initialization. Failure leaves `needsRepair` metadata, allowing an explicit retry without silently discarding user files.
4. SteamService downloads Valve's current installer over HTTPS, validates its PE signature bytes and size, stages it inside C:, and invokes the installer through Wine.
5. SteamDiscovery reads complete local application manifests. A partially rewritten file preserves the last successful library scan in SQLite.
6. Play routes to Windows Steam inside the selected prefix. A command acknowledgement is not reported as a running game.
7. Recipes and the Windows process-observer helper identify target processes. Games without recipes use a bounded inventory of installed executable basenames, without following symlinks. Missing observation becomes `unknown`; a missing expected process becomes a launch timeout. The user can dismiss tracking without claiming the game exited.

## Interfaces

Supervisor v1 commands: `launchWindowsApp`, `openSteam`, `installGame`, `launchGame`, `uninstallGame`, `gameProperties`, `verifyGame`, `openDownloads`, `shutdown`, `forceStop`, `observe`. Each request identifies the data root and environment UUID. Steam App IDs must be positive UInt32 decimal strings. Epic IDs use a bounded ASCII identifier alphabet. The supervisor accepts at most 64 KiB of request data. It exposes no listening socket, privileged service, URL scheme, or global Wine kill command.

Runtime manifests declare schema version, identity, architecture, Wine/wineserver paths, optional observer path, graphics profiles, source provenance, and file hashes. Imported development runtimes are explicitly user-selected code. The curated download catalog is bundled with the app, so a compromised remote catalog cannot silently select a new executable artifact.

The GUI displays completed game installations from managed Windows Steam and Epic libraries. Steamworks Common Redistributables and incomplete downloads are excluded. Cards use Steam's local cached artwork, including content-hash subdirectories, with a title fallback when artwork is unavailable. TrackMania remains the first tested demo; other games are labeled with untested compatibility. Discovery runs away from the main actor and persists the complete library. Session status is scoped to each game's app ID and environment UUID. Uninstall and verification require a closed-game process check; uncertain cases stay under Steam's management.

Steam and directly imported apps share the selected graphics profile. Epic’s launcher and game process tree use Metal without changing the saved profile. Performance selects native 32/64-bit DXVK D3D9 modules and the matching MoltenVK library. Legacy forces Wine builtin D3D9, including after native modules have been installed. Metal uses the DXMT builtin overlay in `WINEDLLPATH` and is selected by the experimental CS2 recipe. Optional recipe launch arguments are passed directly after Steam's `-applaunch` app ID without shell evaluation. Source-runtime manifests explicitly advertise MSync support; all processes in such an environment use it. Profile changes require Steam, game, and Windows app shutdown; there is no automatic backend retry or concurrent-game support in v1.

`GameWindowingPolicy` supplies scoped Mac Driver settings for TrackMania and CS2. The shooter keeps cursor capture enabled while disabling capture-driven window locking, native size constraints in fullscreen, and exclusive display capture. The supervisor confirms these games are closed before preparing settings. `CS2WindowSettings` converts an existing borderless video configuration once and separately disables internal FSR upscaling once. A separate one-time performance migration lowers scene detail and disables MSAA/ambient occlusion while retaining dynamic shadows, audio and the window/input policy. Each migration retains its original settings bytes and records a marker so subsequent user changes are preserved. These are small configuration copies, not full environment backups. The per-CS2 `NativeFullscreen` flag enables native fullscreen on fixed-size game windows and retains captioned native frames for client-drawn windows in the patched Mac driver. It is off for TrackMania and upstream defaults remain unchanged. The CS2 recipe requests a bounded desktop viewport on each launch so saved fullscreen-sized dimensions do not become the next normal window.

## Persistence and recovery

GRDB manages the `crossedover.sqlite` database and schema migration. Codable record kinds are environment, game, operation, session, windowsApp, and windowsRun. Installed-game replacement is transactional and scoped to one environment UUID. Runtime versions, prefixes, backups, downloads, and logs are separate subdirectories.

An advisory `flock` file next to each prefix serializes app, CLI, supervisor, and recovery operations. Backups clone files on APFS. Restore stages the saved prefix before renaming the live prefix, then restores metadata. Full backups are manual only. Runtime migration requires a stopped environment and updates it in place; a failure preserves files and marks the environment as needing repair.

## Security and remaining constraints

Archive extraction rejects absolute paths, parent traversal, special files, hard links, symlink escapes, excessive entry counts, and decompression above 12 GiB. Managed path resolution checks symlink ancestors even when the final file does not exist. Hash verification runs before extraction.

Wine's broad Z: mapping and user-folder symlinks escaping the prefix are removed after initialization and repair. Windows software still runs with the user's OS permissions; this is not a sandbox. Development runtimes are not a trusted public update channel. Logs and secrets are never uploaded automatically. Diagnostic exports exclude Steam and Epic account files, cookies, and raw runtime output.

The GUI refreshes local manifests every eight seconds while the Mac app is active, preserving prior data on transient parse failures. A filesystem event watcher can replace polling without changing the discovery interface. The runtime supervisor acknowledges launch requests and detaches a worker that drains inherited runtime output into a 1 MiB bounded log. Wine process observation supplies game-session status where supported.


## Windows executable cards (v1.1.0)

Games and Apps are separate views over Steam installations and persistent `WindowsApp` cards. Steam discovery replaces only `game` records; it cannot erase custom app cards. Imported apps carry an environment UUID, category, display name, and a relative C: executable path. Cards can be renamed, recategorized, or retargeted after an installer finishes. Removing a card leaves files in place. New manual backups include windows-apps.json; restore commits card and environment metadata together. Legacy backups predate imported apps and restore an empty custom-card library.

`WindowsApps` validates DOS/PE signatures, x86/x64 machine type, executable/DLL flags, optional-header magic, and section-table bounds. External .exe files are copied into a unique `drive_c/crossedover/Apps` directory. An explicit folder option copies sibling files and subdirectories with cancellation checks; links and special files are rejected. Files already inside C: are referenced in place. Failed imports discard their newly staged files. Every launch revalidates containment and executable headers.

`launchWindowsApp` identifies a stored card UUID and run UUID rather than accepting a caller-supplied command. It works without Steam installed. A detached worker runs the normal Wine loader with a single structured executable argument and the app’s own working directory. Steam branding is removed. The worker persists requested/running/exited/failed state, exit code, and end time; launch errors also become persisted failures. Its per-card log is capped at 1 MiB. The GUI can close while the worker runs, then recover status on reopening. Missing workers are marked interrupted, allowing retry. A running status confirms the launched process, not UI responsiveness or compatibility; apps that hand off to unrelated processes may outlive this tracking.

All apps share the existing environment and graphics profile. The first custom import can prepare the included runtime and environment without installing Steam. Existing user environments and Steam authentication are preserved. No game-specific tuning is applied to arbitrary .exe cards. Windows code has the Mac user’s permissions; containment of imports is not an OS sandbox.

## Epic Games (v1.2.0)

`EpicService` downloads the current official HTTPS MSI, validates the final host, size, and compound-file signature, and installs Windows Epic through Wine. It does not bundle the launcher, credentials, or games. Epic uses the normal Wine loader without Steam branding. Its current Direct3D 11 interface requires a Metal-capable runtime; its process tree uses Metal without altering the environment’s saved Steam/imported-app profile.

`EpicDiscovery` reads bounded local `.item` installation manifests from `C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests`. Complete base games with existing executables become cards. Incomplete installs, DLC, engines, launcher helpers, paths outside C:, and symlink escapes are excluded. `GameLibrary` merges stores with independent fallback on transient parse errors. Legacy Steam JSON defaults to Steam. New session IDs prefix Epic IDs with `epic:` to avoid collisions.

Supervisor v1 adds `openEpic`, `launchEpicGame`, `epicProperties`, `verifyEpicGame`, `uninstallEpicGame`, and `epicDownloads`. Launch re-resolves installed metadata and passes the composite namespace/catalog/app URI as one argument, without a shell. Management opens Epic’s Library; the user selects Manage → Verify or Uninstall there. No unsupported management URI is invented and acknowledgement never claims removal or verification completed. Discovery removes cards after Epic removes their installation manifests.

Visible game artwork decodes serially on a background actor through ImageIO, including first-draw decompression. Lazy rows request it asynchronously; a 64-item/64 MiB cache and bounded expiring misses avoid repeated disk work. App-owned previews preload the same cache. Launcher workers continuously drain output but limit atomic bounded-log rewrites to four per second, with a final flush.

Settings and Activity use an AppKit scroll document with explicit width/content-triggered measurement. The hosted view disables automatic intrinsic sizing and viewport safe-area propagation; scrolling only changes the clip origin. This avoids repeated height-constraint feedback into the parent SwiftUI graph. Library grids/lists retain their lazy SwiftUI containers.

## v1.3.1 partner installations and download totals

Epic’s `Data/ThirPartyManagedApps/*.json` records describe externally managed installations without ordinary `.item` manifests. For `UbisoftConnect`, discovery validates AppName/Namespace/CatalogID/GameID, then correlates the fixed Ubisoft registry install roots with an existing contained C: program. It never executes metadata `AdditionalCommandArgs` or arbitrary registry paths. The resulting card retains its Epic source and catalog identity. For a completed Ubisoft partner installation, Play activates its composite game URI through Windows ShellExecute and Epic’s registered handler so the owning client handles authorization and the Ubisoft handoff. A bare Ubisoft URL opened the launcher but failed to start Brawlhalla during real checks. Independent Ubisoft installations still use `UbisoftConnect.exe`, the registered URL bootstrapper, rather than the internal `upc.exe`. Initial entitlement/account linking still happens in Epic’s own Library. Equivalent independent Ubisoft cards are deduplicated by installation directory. Ubisoft-only installs use their own source/session namespace and normal launcher URI.

Epic/Ubisoft trees combine DXMT for D3D11 with native Performance D3D9 when the runtime advertises both. Steam and generic imported apps retain their selected profile. No game binary, credentials, account cache, or anti-cheat implementation is modified.

GitHub Pages reads release-asset download counts on the build host using the read-only Actions token. `website/download_stats.py` filters uploaded DMGs from published releases and emits only aggregate counts, a timestamp, and metric description. The static site renders that snapshot, also available as `downloads.json`; no visitor JS calls the private repository API. Scheduled/release-triggered deployment refreshes the number. API failures show unavailable, not zero.

The combined renderer leaves D3D9 out of `WINEDLLOVERRIDES`, since Wine prioritizes environment overrides ahead of AppDefaults. Fixed per-executable policy keeps Epic/Ubisoft launcher helpers on builtin D3D9 and selects native/builtin D3D9 for Brawlhalla. Policy import is serialized under the environment lock. Normal Open Epic starts its UI directly; every cold Epic game launch, including partner installations, primes that UI before submitting the composite URI. Game requests keep the client visible for sign-in/linking prompts. The supervisor computes the cold-start hint from its own process observation and does not accept a caller-selected executable.
