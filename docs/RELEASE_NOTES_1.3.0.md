# crossedover v1.3.0

> Historical development notes. This candidate was superseded by [v1.3.1](RELEASE_NOTES_1.3.1.md) before publication.

Windows Epic Games joins Steam and local Windows apps in one library, with smoother native scrolling and discovery of Ubisoft handoffs.

- Separate **Open Steam** and **Open Epic** controls, with official Windows launcher setup.
- Completed Epic downloads appear as Games cards alongside Steam. Filter by store or added .exe, search, and use grid or list views.
- Play Epic games through their own launcher; browse files, open mod folders, and inspect installation properties.
- **Verify files in Epic…** and **Uninstall in Epic…** open Epic Library; choose the game’s **⋯ → Manage** action and confirm there. Download progress remains inside Epic.
- Epic uses Metal for its Direct3D 11 interface and DirectX 10–11 games, plus Performance rendering for DirectX 9. Steam and imported apps retain their selected graphics profile.
- Artwork loading and decompression move off the interface thread. Settings and Activity use native scrolling with cached content measurement. The user confirmed smooth interaction after this change. Launcher log writes are throttled while output is continuously drained.
- Epic partner records plus Ubisoft install discovery fix missing cards for games Epic delegates to Ubisoft, including Brawlhalla. Play opens the installed Ubisoft game link after initial account linking in Epic; file management and mods remain accessible. The user confirmed Brawlhalla works from Epic’s Library; crossedover’s card launch and native window controls are still being checked.
- GitHub Pages shows aggregate release DMG download counts, refreshed during server-side builds. No visitor tracking or browser credentials.
- Settings adds an Xbox Cloud browser shortcut. Local Windows Xbox app, PC Game Pass downloads, and Minecraft Bedrock are not supported by the included runtime; the guide explains the separate experimental Bedrock route.
- Required and recommended hardware guidelines in the README, quickstart, website, and DMG, with memory/storage planning and measured-test limits.
- Updated quickstart, offline guide, and GitHub Pages site. More launcher and platform support is coming soon.

Compatibility varies by game, DRM, anti-cheat, and required Windows features. Epic sign-in was confirmed by the user; real Epic game validation is still in progress. The owned handoff/graphics fixture is not a real store-game compatibility test. No accounts or games are bundled.

This private evaluation release is locally signed and not notarized. Previous releases remain available. See the quickstart and validation notes for current limits.
