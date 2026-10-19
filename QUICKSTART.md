# crossedover v1.3.0 quickstart

## Before you start

You need an **Apple silicon Mac**, **macOS 15 or 26**, **Rosetta 2**, an internet connection for setup. Steam and Epic accounts are needed only for games from those stores. Allow **8 GiB free for setup, plus space for apps and games**. Recommended: **16 GB+ unified memory**, or **24–32 GB+** for heavier games. [Hardware guidelines](#hardware-guidelines).

Compatibility is experimental. TrackMania Nations Forever is the first tested demo, CS2 is experimental, and compatibility with other games and apps varies. A version number does not certify every game or sustained performance.

## Install

1. Download **crossedover-1.3.0.dmg** from the [v1.3.0 release](https://github.com/CoryPearl/crossedover/releases/tag/v1.3.0).
2. Open it and drag **crossedover** onto **Applications**.
3. Eject the disk image and open crossedover from Applications.

## First open

The release is locally signed and **not notarized by Apple**. If macOS blocks it and you trust the download, try opening it once, then use **System Settings → Privacy & Security → Open Anyway**. Confirm the app name before continuing. See [Apple's instructions](https://support.apple.com/en-us/102445). Do not disable Gatekeeper system-wide.

If macOS offers to install Rosetta 2, follow Apple's prompt.

## Games and Apps

**Games** contains completed Windows Steam and Epic installs and Windows game cards you add yourself. **Apps** contains tools, mod managers, installers, and other Windows software. Both libraries support search (⌘F), refresh (⌘R), and grid/list views.

## Add a Windows .exe

1. Choose **Add .exe** (⌘O), then select a local x86 or x64 Windows executable.
2. Give it a name and choose **Games** or **Apps**.
3. Enable **Include files from the containing folder** if it needs nearby DLLs, assets, or installer data. Extract archives first and select a folder containing only that app.
4. Choose **Add to library**, then **Run** (Apps) or **Play** (Games) on its card. Steam is not required; the included runtime is prepared on the first import.

Files outside the Windows environment are copied into its `C:\crossedover\Apps` folder. Your source files stay in place. Executables already inside its C: drive are used in place. Nothing is uploaded. Apps run with your Mac user permissions: add software you trust. Windows ARM executables, DLLs, and incomplete downloads are rejected; accepting a file does not certify compatibility.

**Installers:** run the installer card and finish its Windows setup. Then choose **⋯ → Edit app / choose executable → Choose** and select the installed program under the Windows C: drive (usually Program Files). Save the card; subsequent launches open the program instead of its installer.

The imported card’s **⋯** menu lets you rename it, change its executable, move it between Games and Apps, show files, inspect its launch log, or remove it from the library. **Remove from library** keeps files and installed software. To uninstall installed Windows software, run its supplied uninstaller from the C: drive; delete unused portable app folders in Finder only after closing Windows apps. Full removal through **Settings → Uninstall crossedover** includes all managed imported files and installed apps. Your original source files outside the environment stay on your Mac.

Apps share one Windows environment and its graphics profile with Steam games. Close Windows software before changing profiles. Extra frameworks, DLL overrides, drivers, anti-cheat, and some launchers may need setup or be unsupported. Use **Show launch log** if a launch fails.

## Set up Steam

1. Click **Set up Steam**. The app prepares its included runtime and downloads Windows Steam directly from Valve. Allow a few minutes.
2. Sign in **inside Steam's window**, completing Steam Guard if requested.
3. Install a Windows game through that Steam client.

Your native Mac Steam installation stays separate. No Steam account, game files, or saved games are bundled with crossedover.

## Epic Games

1. Choose **Set up Epic**. crossedover downloads Epic’s official Windows MSI installer and installs it in the managed Windows environment; Steam is not required.
2. Sign in **inside Epic’s own window**, including any two-factor prompt. crossedover does not ask for your Epic password.
3. Install a Windows game through that Epic client. Use its default C: drive location, or another folder inside the same Windows C: drive.
4. Completed installs appear automatically in **Games**, with an **Epic Games** label. Press **⌘R** to refresh, or use the **All games / Steam / Epic Games / Added .exe** filter.
5. Press **Play** on the game’s card. Launches go through Windows Epic so it can handle account authorization and DRM; crossedover tracks the game process.

**Open Steam** and **Open Epic** are separate sidebar buttons. Each uses crossedover’s Windows client; your native Mac launchers stay separate. Both clients and their downloads live under crossedover’s existing data folder. The in-app uninstaller removes both clients and all their managed games.

Use an Epic card’s **⋯** menu for **Game properties**, **Show game files**, **Mods & files**, and **Manage in Epic**. **Verify files in Epic** and **Uninstall in Epic** open Epic Library: find the game, choose **⋯ → Manage → Verify / Uninstall**, then confirm in Epic. These buttons open the supported management flow; they do not silently verify or delete files. The card disappears after Epic finishes uninstalling and the library refreshes.

**Settings → Windows Epic Games → Open download folder** opens the default `C:\Program Files\Epic Games` folder in Finder. Per-game **Show game files** opens the actual install folder if you chose a different C: location. The **Epic downloads → Open Epic** button opens Epic; use its Downloads control for progress, pause/resume, and updates.

Epic’s current Windows launcher needs DirectX 11 and uses **Metal**. Its game processes use Metal for DirectX 10–11 and **Performance** for DirectX 9 when available. Steam and directly added apps retain their chosen graphics profile. The launcher can self-update. Compatibility, DRM, anti-cheat, and extra dependencies vary by game; inclusion in the library is not a compatibility guarantee.

## Play and manage

Completed Steam installs appear automatically in **Games**. Press **⌘R** to refresh and **⌘F** to search. The grid/list selector remembers your preference.

Press **Play** to launch. If a known game's graphics profile needs to change, close your current game and accept the Steam restart.

Use **⋯** for properties, game files, verification, or uninstall. Steam handles the uninstall confirmation. **Settings → Windows Steam → Open download folder** opens the installed games folder in Finder. The separate **Steam Downloads** button opens download progress and updates in Steam.

Graphics profiles are explained in Settings:

- **Legacy:** OpenGL for older DirectX 9 games; a compatibility fallback.
- **Performance:** DXVK and Metal for DirectX 9; recommended for TrackMania Nations Forever.
- **Metal:** DXMT for DirectX 10–11; used by CS2. Compatibility varies by game.

Quit Steam, Epic, games, and Windows apps before changing profiles. TrackMania uses Performance; CS2 uses Metal and opens in a desktop-sized window. CS2's native window controls and match performance are still being validated.

## Mods

Games keep their normal Windows files, so manual mods can be installed in the locations specified by each mod's instructions. Quit the game before changing files.

- **crossedover:** use **⋯ → Mods & files → Game folder** to open the installation in Finder, or **Windows Documents** for games that store maps, skins, or mods there. Copy extracted mod files into the folder required by the mod.
- **Steam:** open the game's **Properties → Installed Files → Browse**. This uses the runtime's Windows file explorer for the same installed game. Use crossedover's Finder action if you prefer.
- **Steam Workshop:** for games that support it, subscribe to items in Windows Steam, let downloads finish, and enable them in the game if needed. [Valve's Workshop guide](https://partner.steamgames.com/doc/features/workshop/implementation) explains how subscriptions are delivered.

Mod compatibility depends on the game and mod. Windows mod managers, script extenders, DLL overrides, and additional frameworks may need separate Wine setup; you can add their .exe as an App card, but crossedover does not automatically configure their extra dependencies. Steam updates and verification can replace modified files. Save a copy of files you replace yourself; crossedover does not make automatic full backups.

The managed Steam host is labelled **crossedover Steam** in macOS. For an older installation, quit Windows Steam and all games, then choose **Settings → Advanced → Use included runtime** after updating the app. Reopen Steam to apply the label. Game names and descriptive Steam dialog titles are retained.

## Your files

The app is in **/Applications/crossedover.app**. Games, imported apps, Windows Steam and Epic, runtimes, saves, and environment backups live separately under:

~~~text
~/Library/Application Support/CrossedOver/
~~~

Use **Open download folder** to browse installed games, or **⋯ → Show game files** for one game. Full environment backups are **manual only** and include all installed games, apps, and imported cards. Restoring a pre-v1.1.0 backup clears imported cards because that version did not have them. Small copies of settings changed by crossedover are kept for recovery. Use **Settings → Backups → Create backup** for a manual copy. **Clear backups**, beside it, moves old full backups to Trash; your current games and saves stay in place. Empty Trash in Finder to reclaim space (APFS clones can share blocks).

### Uninstall everything

Quit Steam, Epic, games, and Windows apps, then choose **Settings → Uninstall crossedover → Uninstall app and data**. This moves the app, its Windows Steam and Epic clients, runtimes, managed games and apps, local saves, and backups to Trash, clears app preferences, and quits. Empty Trash to reclaim storage. Export any local saves you want to keep first. Your separate Mac Steam installation is unaffected.

Dragging just crossedover.app to Trash does **not** remove `~/Library/Application Support/CrossedOver/`. Use the in-app uninstaller for complete removal. Custom data locations and apps opened from a read-only DMG must be managed in Finder.

## Coming soon

v1.3.0 adds Windows Epic Games alongside Steam and the local .exe cards introduced in v1.1.0. Support for more launchers and platforms, easier dependency setup, and broader app compatibility is coming soon.

## Need a hand?

- **Missing game:** wait for its install to finish, press ⌘R, and choose All games. Epic installs must stay inside the managed Windows C: drive.
- **Slow first launch:** check Steam for a prerequisite/setup dialog.
- **Frozen game:** try ⌘Tab and quit normally. Recovery tools are in **Settings → Advanced**; force quit can lose unsaved progress.
- **Reporting a problem:** save a diagnostic report from **Settings → Advanced**, review it, and [open an issue](https://github.com/CoryPearl/crossedover/issues). Never share passwords or Steam Guard codes.

[Project](https://github.com/CoryPearl/crossedover) · [Validation notes](docs/VALIDATION.md)

## Epic games that use Ubisoft Connect

Some Epic titles, including Brawlhalla, hand installation and launch to Ubisoft Connect. These installations have Ubisoft registry records rather than Epic `.item` manifests. crossedover combines Epic’s partner records with Ubisoft’s completed install registration. These games appear as **Epic Games** cards; Play opens their registered game link through Ubisoft Connect. Complete the initial account linking in Epic’s own Library first. Independent Ubisoft installs appear under **Ubisoft Connect**. Sign in/link accounts in the launcher's own window when requested. Play routes through the launcher that owns the installation. Files and mods open in Finder. Verification and uninstall continue in Ubisoft's own Library controls. Other Ubisoft titles remain untested.

The launcher uses Metal for Direct3D 11, with Performance rendering for Direct3D 9 games such as Brawlhalla. This does not change Steam's saved profile. An observed process is not proof of a visible or playable game. If a title opens no window, check its own launcher for sign-in/linking prompts and report the title; compatibility varies.

## Xbox and Minecraft Bedrock

**The Windows Xbox app, local PC Game Pass downloads, and Minecraft Bedrock are not supported by the included runtime.** Adding a launcher button cannot supply Windows Gaming Services, account/licensing integration, and game-specific GDK support. This release does not promise the whole Xbox library.

**Settings → Other platforms → Open Xbox Cloud** opens Microsoft's official site in your default browser. It streams only supported cloud titles; account, subscription, region, network, and controller requirements vary. This does not download games into crossedover or imply Minecraft Bedrock is available in the cloud.

Experimental [Bedrock for Mac](https://github.com/1JRobertson/bedrock-mac) work uses a separate WineGDK/DXMT runtime and Microsoft account helper. It establishes a possible future Bedrock-specific route, not support in crossedover or the Windows Xbox app. See [the technical assessment](docs/XBOX_AND_BEDROCK.md). Minecraft Java already has a separate native Mac version. No Microsoft credentials or games are included or collected by crossedover.


## Hardware guidelines

| Required to start | Recommended guidance |
| --- | --- |
| Apple silicon Mac (M1 or newer), with a Metal GPU | M4-class performance; larger GPUs may help heavier 3D games |
| macOS 15 or 26; working Rosetta / Intel translation | macOS 26 is the current test environment; macOS 27 is experimental and 28+ is blocked |
| Enough memory for macOS, the launcher, and your game; no separate RAM gate | **16 GB+ unified memory**, or **24–32 GB+** for demanding games, large mods, or multitasking |
| **8 GiB free for setup**, plus all app/game files and updates | SSD storage; leave **20–30 GiB spare after installs**, with more for large patches |
| Internet for setup, store downloads, sign-in, and activation | Stable broadband for larger downloads; offline play depends on the title |
| A game/app supported by the runtime | Start at **720p or 1080p**, low/medium detail; check performance during gameplay |

An 8 GB Mac has not been validated for gaming. Recommendations are not measured minimums or a promise of 60 FPS. Current testing uses an **M4 / 16 GB Mac on macOS 26.6.2**; the short TrackMania result does not predict other games or Macs. Large updates may temporarily need space comparable to the game itself. [Full hardware and storage guide](docs/HARDWARE.md).
