# crossedover

Windows apps and games, at home on your Mac.

**crossedover v1.1.0** runs Windows software through Wine, with separate **Games** and **Apps** libraries. Steam games are our focus: install through Windows Steam and play from your library. Add a local **.exe** for other games, tools, installers, or mod managers. Support for more launchers and platforms is coming soon.

![The crossedover library](website/assets/library.png)

**[Download v1.1.0](https://github.com/CoryPearl/crossedover/releases/tag/v1.1.0)** · **[Quickstart](QUICKSTART.md)** · **[Website](https://corypearl.github.io/crossedover/)**

## Get started

1. Open the DMG and drag **crossedover** into **Applications**.
2. For Steam, choose **Set up Steam**, sign in inside its window, and install a game. It appears in **Games**.
3. For other software, choose **Add .exe**, pick **Games** or **Apps**, and add the card. Press **Play** or **Run** whenever you need it. Steam is optional.

Requires **Apple silicon**, **macOS 15 or 26**, **Rosetta 2**, and **8 GiB free plus app/game storage**. This release is not notarized; see the [quickstart](QUICKSTART.md).

Search either library and switch between grid and list views. Include an app’s containing folder when it needs nearby files. After running an installer, use the card’s **⋯ → Edit app / choose executable** to select the installed program. Files stay local; nothing is uploaded. Only add software you trust: Windows apps run with your Mac user permissions.

Compatibility varies. TrackMania Nations Forever is our first tested game; CS2 is experimental. Importing an executable does not guarantee it will work. Drivers, anti-cheat, extra frameworks, and some apps need functionality this runtime does not provide.

Use **⋯** to manage cards and browse files. Steam games keep Steam’s uninstall and verification controls; imported cards can be renamed, moved between libraries, or removed. Removing an imported card keeps its files. [Mods and file access](QUICKSTART.md#mods) use normal Windows locations.

Full environment backups are **manual only**. **Settings → Uninstall crossedover** removes the app, managed Windows apps, games, saves, and data after Windows software is closed. Empty Trash afterward. Dragging only the Mac app to Trash leaves its separate data folder behind.

## Build

~~~sh
swift test
python3 scripts/package.py --thin --dmg
~~~

This makes a developer app without a Windows runtime. See [development](docs/DEVELOPMENT.md), [runtime builds](docs/RUNTIME.md), and [website source](website/README.md).

[GPL-3.0-or-later](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md) · [Validation](docs/VALIDATION.md)

An independent project, unaffiliated with Valve, CodeWeavers, or Apple.
