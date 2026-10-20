# crossedover v1.4.3 — Start with your own library

Version **1.4.3**, build **28**.

- New installations start with empty Games and Apps libraries.
- Removed the TrackMania demo-install buttons and placeholder game-card paths.
  Choose a launcher or add your own Windows `.exe` to populate the library.
- Store game cards require a discovered installation; added .exe cards remain
  available. Existing games, apps and saves
  are preserved when updating. TrackMania compatibility tuning still applies if
  you install it yourself through Steam.
- The README and website show the empty first-install experience. Settings
  search and Steam, Epic, Minecraft and `.exe` support remain available.

The DMG includes the Windows runtime and separate Minecraft backend, with no
games, examples, accounts or user data. The standalone Pong test executable is
not included. Windows runtime and game compatibility policies are unchanged.

[Download](https://github.com/CoryPearl/crossedover/releases/download/v1.4.3/crossedover-1.4.3.dmg)
· [Quickstart](../QUICKSTART.md)
· [Website](https://corypearl.github.io/crossedover/)

Apple silicon and Rosetta are required. Steam/Epic/.exe support targets macOS 15
or 26; Minecraft requires macOS 26+ and an owned Windows edition. Locally signed,
**not Developer ID signed or notarized by Apple**. Downloads require repository
access while the GitHub repository is private. Existing compatibility and
[release validation limits](RELEASE.md) still apply.
