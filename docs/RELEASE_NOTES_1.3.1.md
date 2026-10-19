# crossedover v1.3.1

A local validation candidate for Brawlhalla launch and native window controls. Publication is pending user confirmation.

- Epic-installed Brawlhalla now launches through Epic’s composite game URI, preserving the owning client’s authorization and Ubisoft handoff. Previously the card sent a bare Ubisoft URL, which opened the launcher without starting the game.
- The cold Epic startup path now also applies to partner games. Windows launchers start from their own executable directory.
- The included runtime contains Brawlhalla’s scoped native title-bar controls. Existing environments need **Settings → Advanced → Use included runtime** with Windows software closed; updating the Mac app alone does not change their selected runtime.
- A **Game Launchers** menu groups Steam, Epic Games, and installed Ubisoft Connect.
- The bottom launch bar shows preparation, waiting, and running states. **Stop & close Windows** cancels the operation, blocks stale queued launches, and closes all Windows games/apps/launchers in the managed environment. Unsaved progress may be lost.
- Game cards show their store without Demo, Experimental, or Untested badges.
- Universal graphics labels and descriptions, plus a combined **DirectX 9–11** renderer when both DXVK and DXMT components are available. Existing choices keep their behavior; no game-specific names are needed to choose a renderer.
- Backup creation sits beside Clear backups. Documentation includes hardware guidelines, an in-depth Technical README, updated website previews, and a branded README.

The user environment’s runtime was migrated to the included candidate while stopped, preserving its Performance profile. Real card launch, cold/warm Epic behavior, and the red/yellow/green game-window controls still need confirmation. Owned fixtures test routing and graphics, not store authentication or gameplay.

More launcher and platform support is coming soon. Local Windows Xbox app, PC Game Pass downloads, and Minecraft Bedrock are not included.

This private evaluation build is locally signed and not notarized. No games, accounts, or credentials are bundled. Nothing is pushed or published until the requested Brawlhalla checks pass.
