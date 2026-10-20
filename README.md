<p align="center">
  <a href="https://corypearl.github.io/crossedover/">
    <img src="docs/assets/app-icon.png" width="96" height="96" alt="crossedover — splitting arrows app icon">
  </a>
</p>

<h1 align="center">crossedover</h1>

<p align="center">Windows apps and games, at home on your Mac.</p>

<p align="center">
  <a href="https://corypearl.github.io/crossedover/"><strong>Website ↗</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/CoryPearl/crossedover/releases">Downloads</a>
  &nbsp;·&nbsp;
  <a href="QUICKSTART.md">Quickstart</a>
  &nbsp;·&nbsp;
  <a href="TECHNICAL_README.md">Technical README</a>
</p>

<p align="center"><sub>v1.4.3 · Your library, your choice &nbsp;·&nbsp; macOS &nbsp;·&nbsp; Apple silicon &nbsp;·&nbsp; Open source</sub></p>

<br>

<p align="center">
  <img src="website/assets/library.png" width="1100" alt="crossedover’s empty monochrome game library with Add .exe, launcher setup options, search, and a Game Launchers menu">
  <br>
  <sub>A little less launcher. A little more library. New installation · v1.4.3. No games included.</sub>
</p>

crossedover is a **macOS home for Windows apps and games**. Install games through Steam or Epic, play Minecraft Bedrock, or add a local Windows `.exe`. Keep what you play in **Games** and everything else in **Apps**, with search, grid/list views, and launch controls in one place.

| Steam & Epic | Minecraft Bedrock | Your Windows apps |
| --- | --- | --- |
| Install through the official Windows clients. Completed games appear automatically; Epic can hand off to Ubisoft Connect. | Sign in with the Microsoft account that owns Minecraft for Windows. Install locally, then launch from its Games card. | Add games, utilities, installers, and mod managers as cards. Choose **Play** or **Run**. No store launcher is required. |

**[Download v1.4.3](https://github.com/CoryPearl/crossedover/releases/tag/v1.4.3)** — starts with empty Games and Apps libraries. No preinstalled games, sample cards, or TrackMania demo-install prompts. The Windows runtime and separate Minecraft backend are included; install only what you choose. Minecraft sign-in, verified installation, and local gameplay with controls, sound, and saving have been tested on the current Mac. Downloads require repository access while this GitHub repository is private. [v1.4.3 notes](docs/RELEASE_NOTES_1.4.3.md) · [Validation](docs/VALIDATION.md).

## Get started

1. Open the DMG and drag **crossedover** into **Applications**.
2. Choose a store from **Game Launchers**, or use **Add .exe** for local Windows software. Sign in through each launcher's own window.
3. Installed games appear in **Games**. Added executables go in **Games** or **Apps**. Use the card's **Play / Run** button and **⋯** menu for files and management.

For Minecraft, choose **Game Launchers → Minecraft Bedrock… → Install & Play**. After installation, its card appears in Games. Requires an owned Windows edition, Apple silicon, **macOS 26+**, and Rosetta. [Minecraft setup](QUICKSTART.md#xbox-and-minecraft-bedrock).

**Steam, Epic, and imported apps:** Apple silicon, macOS 15 or 26, Rosetta, and **8 GiB free plus app/game storage**. **Recommended:** M4-class performance, **16 GB+ unified memory**, and SSD space for updates. Heavier games may benefit from 24–32 GB+. These are guidelines, not a 60 FPS guarantee. The current build is not notarized. [Hardware](docs/HARDWARE.md) · [Quickstart](QUICKSTART.md).

## Your software, your library

- **Find a setting.** Search Settings by name or topic, including Advanced controls. Press **⌘F** while in Settings to focus search.
- **One place to launch.** Open clients from Game Launchers; launch installed games and added executables from their cards. Minecraft uses its own environment alongside the shared Steam/Epic/app environment.
- **Graphics guidance per game.** Library cards show a renderer recommendation from known profiles or detected DirectX imports. Unknown games get a labeled starting point; open the recommendation for details. CS2 includes a low-detail preset targeting 60 FPS, with performance depending on hardware, resolution and gameplay.
- **Files and mods stay accessible.** Open installation folders in Finder. Use Steam Workshop where supported, or add Windows mod managers as Apps. Steam, Epic, and Ubisoft keep their own verification/uninstall flows.
- **Keep control.** The bottom status bar tracks opening and running software. Stop closes the managed Windows session; Minecraft's Stop action affects only Minecraft. Unsaved progress can be lost.
- **No automatic full backups.** Create or clear backups in Settings. Use the in-app uninstaller for complete app/data removal; dragging only the Mac app to Trash leaves its separate data folder behind. Minecraft's game uninstaller keeps worlds.

Compatibility varies by app and game. TrackMania, Brawlhalla, CS2, and Minecraft have local test evidence; that does not guarantee every title, a minimum frame rate, or all hardware. Drivers, anti-cheat, DRM, and extra frameworks can prevent software from working. CS2’s window controls and online matchmaking are owner-confirmed with normal Steam overlay handling restored. In the latest online test, the owner confirmed sharper visuals and smooth play with the 1600×900 preset and Metal presentation timing. Retained Windows environments stay visible in one library; each game uses its own installation, and the preferred environment supplies duplicate titles. The Windows Xbox app and general PC Game Pass catalog are not implemented.

Games and accounts are not included. Software runs locally through Wine with your Mac user permissions. Use your own accounts and executables you trust. More launchers, platforms, and compatibility improvements are coming soon.

## Build

Read the [Technical README](TECHNICAL_README.md) for an in-depth explanation of the architecture, Windows runtime, launchers, graphics, storage, recovery, and release process.

~~~sh
swift test
python3 scripts/package.py --thin --dmg
~~~

This makes a developer app without a Windows runtime. See [development](docs/DEVELOPMENT.md), [runtime builds](docs/RUNTIME.md), and [website source](website/README.md).

[GPL-3.0-or-later](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md) · [Validation](docs/VALIDATION.md)

An independent project, unaffiliated with Valve, Epic Games, CodeWeavers, or Apple.
