# crossedover

A quiet home for Windows Steam games on your Mac.

crossedover brings a native Mac library, Windows Steam, and a Wine-based runtime together in one app. Windows Steam games are the starting point; more games, stores, and platforms are a direction for the future.

![The crossedover library](website/assets/library.png)

**[Download v1.0.0](https://github.com/CoryPearl/crossedover/releases/tag/v1.0.0)** · **[Quickstart](QUICKSTART.md)** · **[Website](https://crossedover.corypearl561.chatgpt.site)**

## Get playing

1. Open the DMG and drag **crossedover** into **Applications**.
2. Choose **Set up Steam**, then sign in inside Steam's window.
3. Install a Windows game in that Steam client, then press **Play**.

Requires **Apple silicon**, **macOS 15 or 26**, **Rosetta 2**, and **8 GiB free plus game storage**. This release is not notarized; see the [first-open guide](QUICKSTART.md#first-open).

Search your games, switch between grid and list views, and manage installations from the **⋯** menu. TrackMania Nations Forever is the first tested demo. CS2 is experimental; other titles are untested. Compatibility, performance, and long-session stability vary. Games are downloaded through your own Steam account.

## Build

~~~sh
swift test
python3 scripts/package.py --thin --dmg
~~~

This makes a developer app without a game runtime. See [development](docs/DEVELOPMENT.md), [runtime builds](docs/RUNTIME.md), and [website source](website/README.md).

[GPL-3.0-or-later](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md) · [Validation](docs/VALIDATION.md)

An independent project, unaffiliated with Valve, CodeWeavers, or Apple.
