# Hardware guidelines — crossedover v1.4.0

These guidelines cover the included Windows runtime. Meeting them lets you try compatible software; each game still has its own requirements. Recommendations are planning guidance, not certified minimums or a promise of 60 FPS.

## Required to start

| Component | Requirement |
| --- | --- |
| Mac | Apple silicon, M1 or newer. Intel Macs are not supported by this build. |
| macOS | macOS 15 or 26 are the targeted versions. macOS 27 is experimental; the current runtime blocks macOS 28 and later. |
| Translation | Working Rosetta / Intel translation for the Windows runtime. Follow Apple's installation prompt where offered. |
| Graphics | An available Metal GPU. The Mac's built-in Apple GPU meets the architecture requirement; game compatibility varies. |
| Memory | Enough for macOS, the launcher, and the chosen app/game. crossedover does not enforce a separate RAM minimum. See the recommendations below. |
| Free storage | At least **8 GiB for Windows setup**, plus the full size of your games, apps, prerequisites, saves, and updates. |
| Connection and accounts | Internet for launcher setup, downloads, sign-in, and any game activation. Use your own store accounts. Offline use depends on the app/game. |
| Controls | The keyboard, mouse, or supported controller required by your game. Controller compatibility has not been broadly validated. |

Apple documents general Rosetta availability through macOS 27 and reduced functionality starting with macOS 28. That does not establish compatibility of this runtime with future macOS releases. [Apple's Rosetta guidance](https://support.apple.com/en-us/102527)

## Recommended for games

| Component | Guidance |
| --- | --- |
| CPU and GPU | **M4-class performance** is the current reference point. A faster CPU or larger Pro/Max-class GPU may help demanding games, depending on their bottleneck. Other Mac configurations have not been benchmarked here. |
| Unified memory | **16 GB or more** for older games and everyday Windows apps; **24–32 GB or more** for heavier 3D games, large mods, or multitasking. These are recommendations, not measured minimums. |
| Storage | Keep the Windows environment on an **SSD**, with **20–30 GiB spare after installation** as general headroom. Large updates can need another game's worth of temporary space. |
| Resolution | Start at **1280×720 or 1920×1080**, with low/medium game settings. Try higher resolution and detail after checking an actual race or match. |
| Power | For sustained laptop gaming, connect power and use Automatic energy mode rather than Low Power Mode. High Power Mode is optional on Macs that offer it. [Apple's power-mode guidance](https://support.apple.com/en-us/101613) |

An **8 GB Mac is not a validated gaming configuration** for crossedover. It may run lighter software, but is below our memory recommendation. Closing unused browsers, launchers, and apps can reduce memory pressure.

## What has actually been tested

The current test Mac has an **Apple M4, 16 GB unified memory, and macOS 26.6.2**. The user reported roughly **55–60 FPS in a short TrackMania Nations Forever race** with the tuned Performance profile and reduced detail. This is one game and one configuration, not a strict minimum, a long-session benchmark, or a prediction for CS2, Brawlhalla, or another Mac. See [validation notes](https://github.com/CoryPearl/crossedover/blob/main/docs/VALIDATION.md).

## Plan for downloads and saves

The app bundle and its Windows data are separate. Games, launchers, and saves live under `~/Library/Application Support/CrossedOver/`. The 8 GiB setup requirement does not include game downloads. Check the store's installation size and leave extra room for unpacking and patches; some updates temporarily need space comparable to the installed game.

Full backups are manual only and can need space for the entire Windows environment. They are not included in the setup allowance. Use **Settings → Backups** to create or clear them.

Windows CPU, GPU, and VRAM specifications do not translate into a guaranteed Mac equivalent. More powerful hardware cannot supply unsupported Windows features, DRM, or anti-cheat. The Windows Xbox app and general Game Pass catalog are unsupported. Minecraft Bedrock uses the separate v1.4.0 backend described below. [Quickstart](https://corypearl.github.io/crossedover/quickstart.html#hardware)
## Minecraft Bedrock development preview

The separate v1.4.0 Bedrock preview currently requires **Apple silicon, macOS 26
or later, Rosetta, a Minecraft for Windows license, an internet connection and
at least 8 GiB free for setup**. This is separate from the included Steam/Epic
runtime requirements. The local build has passed sign-in, verified download/install, local play with
controls/sound, saving and normal quit on an M4/16 GiB Mac. Frame-rate benchmarks,
lower-end Macs, multiplayer and broader compatibility remain unverified. No Bedrock frame-rate target is advertised yet. See
[the backend guide](../runtime/bedrock/README.md).
