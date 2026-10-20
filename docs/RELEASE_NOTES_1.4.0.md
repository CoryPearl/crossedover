# crossedover v1.4.0 — Minecraft

Version **1.4.0**, build **26**. The DMG includes the Windows runtime and separate Minecraft backend.

[Download](https://github.com/CoryPearl/crossedover/releases/download/v1.4.0/crossedover-1.4.0.dmg) · [Quickstart](../QUICKSTART.md) · [Website](https://corypearl.github.io/crossedover/)

Locally signed, **not notarized by Apple**. Downloads require repository access while the GitHub repository is private. No games or accounts are bundled.

- Minecraft Bedrock has a dedicated entry in Game Launchers and Settings, with
  Microsoft sign-in, setup progress, cancellation, sign-out and files/worlds access.
- A completed installation appears in Games as a card or list row, with Play
  and launcher options. Search, the Minecraft filter and game counts include it.
  Startup, library refresh and session completion check installation status.
- Minecraft uses a separate WineGDK runtime and data directory. Its Stop action
  leaves Steam and Epic sessions independent; uninstall preserves Minecraft worlds.
- CS2 has an opt-in input-bounds fix for native window moves/resizes. Owned
  32/64-bit fixtures pass, and the owner confirmed clicks align across the
  larger monitor after moving the running game.
- CS2 gains a one-time low-detail performance preset targeting 60 FPS in
  matches: MSAA and ambient occlusion off, lower scene detail, with dynamic
  shadows, audio and the confirmed window/input policy retained. Later user
  graphics choices remain intact. The old 720p preset upgrades once to 1600×900;
  later resolution choices are respected. Executable-scoped Metal presentation
  timing complements the game’s 60 FPS cap. The owner confirmed matchmaking
  works and the latest online run is sharper and smooth; a universal minimum
  frame rate is not established.
- Every installed store game has a renderer recommendation in card/list views
  and its graphics details. Known recipes and bounded executable API hints
  take precedence; unknown titles get a labeled starting point. Minecraft
  shows its separate DXMT configuration. Recommendations don't add DirectX 12.
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

v1.4.0 is published at the owner’s request with the local test results below.
Broader hardware coverage, saved-world repeat testing, clean-Mac setup and the
remaining [release checklist](RELEASE.md) are not certified by this release.
CS2 retains the working native window/input policy and normal Steam overlay
handling. Its policy removes crossedover’s earlier forced overlay-disable
entries. After the sharper 1600×900 and presentation-timing update, the owner
confirmed **“Matchmaking works; sharper and smooth”** in the requested online
test. No game binaries or anti-cheat components were changed. A sustained minimum
frame rate across maps, displays and hardware remains unmeasured. TrackMania
keeps its separate, previously tested overlay optimization.
Retained Windows environments now contribute to one library, with game actions
routed to their owning installation and duplicate titles preferring the default.
Rendering recommendations do not certify every game’s online compatibility.
See [backend build instructions](../runtime/bedrock/README.md) and the
[validation record](VALIDATION.md).
