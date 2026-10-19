# crossedover v1.0.0 · build 21

A native Mac home for Windows Steam games. This first release includes a searchable library, compact grid and list views, Steam installation, per-game Play and management controls, and the independently built game runtime.

Settings includes descriptions for all graphics profiles, separate Finder games-folder and Steam Downloads actions, manual-only full backups with cleanup, and a complete app/data uninstaller. Library refresh work runs away from the interface thread and skips unchanged results and background polling.

**More than Steam games is coming soon:** other games, launchers, and platforms are planned.

This build adds **⋯ → Mods & files**, with Finder shortcuts to the installed game and Windows Documents, plus manual-mod and Workshop guidance. Steam's native host is labelled **crossedover Steam**; games retain their own names. Windows mod managers and DLL-based loaders may require additional setup.

The app's version remains 1.0.0, with build number 21. The original v1.0.0 release remains available; this build has its own source tag.

## Install

Download **crossedover-1.0.0.dmg**, open it, and drag crossedover into Applications. **Start Here.html** in the disk image walks through Steam setup. SHA-256 checksums are included in **SHA256SUMS.txt**.

Requires Apple silicon, macOS 15 or 26, Rosetta 2, and 8 GiB free before game downloads. Sign in inside Windows Steam and install games through your own account.

## Current limits

- Compatibility is experimental. TrackMania Nations Forever is the first tested demo; CS2 is experimental and its native controls are still under validation. Other games are untested.
- Performance and long-session stability vary; no universal compatibility or minimum frame rate is promised.
- The app is locally signed, **not Developer ID signed or notarized**. Follow the first-open guide only if you trust the download.
- The included runtime still uses the documented development dependency shortcut. Full dependency source/notice closure and fresh-machine testing remain public-release gates. This repository and its release are being kept private for evaluation.

Steam and game files are downloaded separately. No accounts, credentials, saves, or game installations are included.

See the quickstart, third-party notices, runtime provenance, and validation record in the repository.
