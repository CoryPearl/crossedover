# crossedover v1.0.0 quickstart

## Before you start

You need an **Apple silicon Mac**, **macOS 15 or 26**, **Rosetta 2**, an internet connection, and your own Steam account. Allow **8 GiB free for setup, plus space for your games**.

Compatibility is experimental. TrackMania Nations Forever is the first tested demo, CS2 is experimental, and other games are untested. A version number does not certify every game or sustained performance.

## Install

1. Download **crossedover-1.0.0.dmg** from the [v1.0.0 release](https://github.com/CoryPearl/crossedover/releases/tag/v1.0.0).
2. Open it and drag **crossedover** onto **Applications**.
3. Eject the disk image and open crossedover from Applications.

## First open

The release is locally signed and **not notarized by Apple**. If macOS blocks it and you trust the download, try opening it once, then use **System Settings → Privacy & Security → Open Anyway**. Confirm the app name before continuing. See [Apple's instructions](https://support.apple.com/en-us/102445). Do not disable Gatekeeper system-wide.

If macOS offers to install Rosetta 2, follow Apple's prompt.

## Set up Steam

1. Click **Set up Steam**. The app prepares its included runtime and downloads Windows Steam directly from Valve. Allow a few minutes.
2. Sign in **inside Steam's window**, completing Steam Guard if requested.
3. Install a Windows game through that Steam client.

Your native Mac Steam installation stays separate. No Steam account, game files, or saved games are bundled with crossedover.

## Play and manage

Completed installs appear automatically. Press **⌘R** to refresh and **⌘F** to search. The grid/list selector remembers your preference.

Press **Play** to launch. If a known game's graphics profile needs to change, close your current game and accept the Steam restart.

Use **⋯** for properties, game files, verification, or uninstall. Steam handles the uninstall confirmation. **Settings → Windows Steam → Downloads** opens download progress.

TrackMania uses Performance; CS2 uses Metal and opens in a desktop-sized window. CS2's native window controls and match performance are still being validated.

## Your files

The app is in **/Applications/crossedover.app**. Games, Windows Steam, runtimes, saves, and environment backups live separately under:

~~~text
~/Library/Application Support/CrossedOver/
~~~

Use **⋯ → Show game files** to find a game. Removing the app does not remove its data. Uninstall games through Steam; review backups before deleting anything manually.

## Need a hand?

- **Missing game:** wait for its install to finish, then press ⌘R.
- **Slow first launch:** check Steam for a prerequisite/setup dialog.
- **Frozen game:** try ⌘Tab and quit normally. Recovery tools are in **Settings → Advanced**; force quit can lose unsaved progress.
- **Reporting a problem:** save a diagnostic report from **Settings → Advanced**, review it, and [open an issue](https://github.com/CoryPearl/crossedover/issues). Never share passwords or Steam Guard codes.

[Project](https://github.com/CoryPearl/crossedover) · [Validation notes](docs/VALIDATION.md)
