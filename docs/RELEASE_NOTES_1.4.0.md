# crossedover v1.4.0 — Minecraft

**In development. Not published.** Local builds use version **1.4.0**, build **26**.

- Minecraft Bedrock has a dedicated entry in Game Launchers and Settings, with
  Microsoft sign-in, setup progress, cancellation, sign-out and files/worlds access.
- A completed installation appears in Games as a card or list row, with Play
  and launcher options. Search, the Minecraft filter and game counts include it.
  Startup, library refresh and session completion check installation status.
- Minecraft uses a separate WineGDK runtime and data directory. Its Stop action
  leaves Steam and Epic sessions independent; uninstall preserves Minecraft worlds.
- Epic partner launches use the repaired prerequisites and queued client handoff.
  Brawlhalla opens from crossedover. A new scoped runtime patch adds native
  controls to shaped/layered main windows and keeps desktop title bars onscreen.
  The owned 32/64-bit tests pass, and the owner confirmed the real game's
  red/yellow/green buttons, minimize and fullscreen work.

Microsoft sign-in is confirmed. Minecraft's package download remains blocked;
installation, gameplay, audio/input, saves, fullscreen and repeat launches are
not verified. Failed setup does not create an installed-game card. The current
preview requires Apple silicon, Rosetta, macOS 26+ and an owned Windows edition.
This does not add the Windows Xbox app or general Game Pass compatibility.

Existing public download URLs still point to the previous v1.3.1 artifact.
Publishing v1.4.0 waits for the Minecraft flow and remaining release checks.
See [backend build instructions](../runtime/bedrock/README.md) and the
[validation record](VALIDATION.md).
