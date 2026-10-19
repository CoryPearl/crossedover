# crossedover v1.0.0

A native Mac home for Windows Steam games. This first release includes a searchable library, compact grid and list views, Steam installation, per-game Play and management controls, and the independently built game runtime.

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
