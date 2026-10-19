# Architecture

`CrossedOver` is the SwiftUI app. `CrossedOverCore` owns Codable models, runtime installation, validation, SQLite records through GRDB, Wine configuration, the Steam VDF parser, process execution, backups, migrations, and diagnostic redaction. `CrossedOverSupervisor` accepts one versioned JSON request on stdin and returns a JSON reply. `CrossedOverCLI` exposes the same services for development and verification.

## Data flow

1. HostInspector verifies OS, Metal, disk capacity, and Rosetta execution.
2. RuntimeManager downloads a pinned archive over HTTPS, verifies SHA-256, extracts into staging through libarchive, validates executable paths, and atomically installs it.
3. EnvironmentManager persists a UUID before Wine initialization. Failure leaves `needsRepair` metadata, allowing an explicit retry without silently discarding user files.
4. SteamService downloads Valve's current installer over HTTPS, validates its PE signature bytes and size, stages it inside C:, and invokes the installer through Wine.
5. SteamDiscovery reads complete local application manifests. A partially rewritten file preserves the last successful library scan in SQLite.
6. Play routes to Windows Steam inside the selected prefix. A command acknowledgement is not reported as a running game.
7. Recipes and the Windows process-observer helper identify target processes. Games without recipes use a bounded inventory of installed executable basenames, without following symlinks. Missing observation becomes `unknown`; a missing expected process becomes a launch timeout. The user can dismiss tracking without claiming the game exited.

## Interfaces

Supervisor v1 commands: `openSteam`, `installGame`, `launchGame`, `uninstallGame`, `gameProperties`, `verifyGame`, `openDownloads`, `shutdown`, `forceStop`, `observe`. Each request identifies the data root and environment UUID. App IDs must be positive UInt32 decimal strings. The supervisor accepts at most 64 KiB of request data. It exposes no listening socket, privileged service, URL scheme, or global Wine kill command.

Runtime manifests declare schema version, identity, architecture, Wine/wineserver paths, optional observer path, graphics profiles, source provenance, and file hashes. Imported development runtimes are explicitly user-selected code. The curated download catalog is bundled with the app, so a compromised remote catalog cannot silently select a new executable artifact.

The GUI displays completed game installations from the managed Windows Steam libraries. Steamworks Common Redistributables and incomplete downloads are excluded. Cards use Steam's local cached artwork, including content-hash subdirectories, with a title fallback when artwork is unavailable. TrackMania remains the first tested demo; other games are labeled with untested compatibility. Discovery runs away from the main actor and persists the complete library. Session status is scoped to each game's app ID and environment UUID. Uninstall and verification require a closed-game process check; uncertain cases stay under Steam's management.

Graphics selection is environment-wide. Performance selects native 32/64-bit DXVK D3D9 modules and the matching MoltenVK library. Legacy forces Wine builtin D3D9, including after native modules have been installed. Metal uses the DXMT builtin overlay in `WINEDLLPATH` and is selected by the experimental CS2 recipe. Optional recipe launch arguments are passed directly after Steam's `-applaunch` app ID without shell evaluation. Source-runtime manifests explicitly advertise MSync support; all processes in such an environment use it. Profile changes require Steam and game shutdown; there is no automatic backend retry or concurrent-game support in v1.

`GameWindowingPolicy` supplies scoped Mac Driver settings for TrackMania and CS2. The shooter keeps cursor capture enabled while disabling capture-driven window locking, native size constraints in fullscreen, and exclusive display capture. The supervisor confirms these games are closed before preparing settings. `CS2WindowSettings` converts an existing borderless video configuration once and separately disables internal FSR upscaling once. Each migration retains its original bytes and records a marker so subsequent user changes are preserved. The per-CS2 `NativeFullscreen` flag enables native fullscreen on fixed-size game windows and retains captioned native frames for client-drawn windows in the patched Mac driver. It is off for TrackMania and upstream defaults remain unchanged. The CS2 recipe requests a bounded desktop viewport on each launch so saved fullscreen-sized dimensions do not become the next normal window.

## Persistence and recovery

GRDB manages the `crossedover.sqlite` database and schema migration. Codable record kinds are environment, game, operation, and session. Installed-game replacement is transactional and scoped to one environment UUID. Runtime versions, prefixes, backups, downloads, and logs are separate subdirectories.

An advisory `flock` file next to each prefix serializes app, CLI, supervisor, and recovery operations. Backups clone files on APFS. Restore stages the saved prefix before renaming the live prefix, then restores metadata. Runtime migration creates a backup, initializes the replacement runtime, and restores prefix bytes and metadata together on failure.

## Security and remaining constraints

Archive extraction rejects absolute paths, parent traversal, special files, hard links, symlink escapes, excessive entry counts, and decompression above 12 GiB. Managed path resolution checks symlink ancestors even when the final file does not exist. Hash verification runs before extraction.

Wine's broad Z: mapping and user-folder symlinks escaping the prefix are removed after initialization and repair. Windows software still runs with the user's OS permissions; this is not a sandbox. Development runtimes are not a trusted public update channel. Logs and secrets are never uploaded automatically. Diagnostic exports exclude Steam account files and raw runtime output.

The GUI refreshes local manifests every four seconds, preserving prior data on transient parse failures. A filesystem event watcher can replace polling without changing the discovery interface. The runtime supervisor acknowledges launch requests and detaches a worker that drains inherited runtime output into a 1 MiB bounded log. Wine process observation supplies game-session status where supported.
