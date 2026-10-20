# crossedover v1.4.0 — Minecraft

**In development. Not published.** Local builds use version **1.4.0**, build **26**.

- Minecraft Bedrock has a dedicated entry in Game Launchers and Settings, with
  Microsoft sign-in, setup progress, cancellation, sign-out and files/worlds access.
- A completed installation appears in Games as a card or list row, with Play
  and launcher options. Search, the Minecraft filter and game counts include it.
  Startup, library refresh and session completion check installation status.
- Minecraft uses a separate WineGDK runtime and data directory. Its Stop action
  leaves Steam and Epic sessions independent; uninstall preserves Minecraft worlds.
- CS2 has an opt-in input-bounds fix for native window moves/resizes. Owned
  32/64-bit fixtures pass; the larger-monitor case is awaiting confirmation.
- Epic partner launches use the repaired prerequisites and queued client handoff.
  Brawlhalla opens from crossedover. A new scoped runtime patch adds native
  controls to shaped/layered main windows and keeps desktop title bars onscreen.
  The owned 32/64-bit tests pass, and the owner confirmed the real game's
  red/yellow/green buttons, minimize and fullscreen work.

Microsoft sign-in, verified package download/install and local gameplay are
confirmed. The owner tested controls/sound, saved a world and quit normally.
The installer authenticates the signed hash tree and every metadata/game-data
page before extraction, then removes the complete temporary archive. Card-based
repeat launch, saved-world reopen and remaining release checks are in progress.
Failed setup does not create an installed-game card. The current preview requires
Apple silicon, Rosetta, macOS 26+ and an owned Windows edition. This does not add
the Windows Xbox app or general Game Pass compatibility.

Existing public download URLs still point to the previous v1.3.1 artifact.
Publishing v1.4.0 waits for the Minecraft flow and remaining release checks.
See [backend build instructions](../runtime/bedrock/README.md) and the
[validation record](VALIDATION.md).
