# Third-party notices

CrossedOver original code is GPL-3.0-or-later; see LICENSE.

| Component | License / source | Use |
|---|---|---|
| GRDB.swift | MIT, https://github.com/groue/GRDB.swift | SQLite persistence; exact revision in Package.resolved |
| Sparkle | Sparkle's license, https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE | Application update framework; exact revision in Package.resolved |
| libarchive public headers | BSD-style; Sources/CArchive/LICENSE.libarchive | Headers vendored from libarchive 3.8.2; links macOS system libarchive |
| Wine | LGPL-2.1-or-later and file-specific notices | Separately installed runtime, not app source |
| DXMT | LGPL-2.1-or-later, https://github.com/3Shain/dxmt | Optional experimental runtime overlay |
| D9VK | Zlib, https://github.com/Sikarugir-App/d9vk | Direct3D 9 Performance profile; built from the revision in runtime/source-lock.json |
| TrackMania-MacOS patches | https://github.com/vakesz/TrackMania-MacOS/tree/main/patches/d9vk | Attributed volume-slice and reflection fixes; see runtime/patches/d9vk/README.md |
| MoltenVK | Apache-2.0, https://github.com/KhronosGroup/MoltenVK | Metal implementation of Vulkan, official pinned 1.4.2 development binary; Apache license included in runtime |
| x87sidecar | MIT, https://github.com/athei/x87sidecar | Optional cooperative x87 accelerator; PC24-aware build from the pinned TrackMania-MacOS 0.3.0 release, license included |
| Community runtime dependencies | Component-specific | Development-only dependency shortcut; see runtime/source-lock.json |

Preserve upstream notices and provide corresponding source for redistributed runtime components. The source-build script currently packages Wine's license and authors; full dependency source/notice collection is a public-release blocker. Downloading Steam does not grant rights to redistribute Valve's client or game content; CrossedOver downloads Steam directly from Valve for each installation.

The application uses Apple's system frameworks and SF Symbols. No CodeWeavers branding or proprietary assets are included. Steam, CrossOver, Wine, and Apple product names identify their respective third-party projects.

The TrackMania logo is read from the user’s existing Steam artwork cache and displayed in its original colors. No game artwork is redistributed in the app bundle.

The optional cooperative Wine loader handshake is adapted from https://github.com/vakesz/TrackMania-MacOS/blob/main/patches/wine/0008-ntdll-rosetta-cooperative-sidecar.patch for the CodeWeavers Wine 11.0 loader signature. It is inactive without an explicitly selected helper.

The website contains app-interface previews with cached game artwork visible in context. It hosts no game files. Full GRDB and Sparkle license texts are in licenses/ and included with the packaged app.

Epic Games Launcher is downloaded directly from Epic for each setup; it and its games are not included in the app or disk image. Epic Games names identify their respective owner. crossedover is independent of Epic Games. Epic installation metadata and artwork remain local to the user’s Windows environment.

Epic launch-support setup can download Wine Mono 10.4.1 from [its upstream release](https://github.com/wine-mono/wine-mono/releases/tag/wine-mono-10.4.1), checking the digest pinned by the Wine runtime source. Wine Mono has component-specific upstream licenses and notices; its [matching source](https://github.com/wine-mono/wine-mono/tree/wine-mono-10.4.1) is maintained by that project. This installer is downloaded per environment, not bundled in the Mac app or DMG. Epic's online-services helper comes from Epic's own installed launcher; no account or game content is redistributed.

Ubisoft Connect and Brawlhalla names identify their respective owners. Connect is installed by its official launcher flow where required; it, accounts, and game payloads are not bundled. Local Windows metadata is used only for installation discovery. The Xbox Cloud link opens Microsoft’s official service in a browser. The v1.4.1 package includes the separate Bedrock backend described below. No affiliation with Microsoft, Mojang, or Xbox is implied.

## Separate Bedrock backend

The Bedrock preview backend included in v1.4.1 builds [Bedrock for Mac](https://github.com/1JRobertson/bedrock-mac/tree/99fc9aa7d79b34aaee25a447b964e5d8235a2cec) (GPLv3), with pinned WineGDK/Wine (LGPL 2.1 or later), Xodus (GPLv3), DXMT 0.80 (MIT plus its embedded notices), and their dependencies. Its scripts, helper and compatibility work remain attributed to their upstream authors. The staging process retains the upstream LICENSE, THIRD_PARTY.md, LICENSES directory, exact revisions, build manifests, and crossedover's integration patch. The patch to the Wine build script follows its upstream terms; worker/helper changes retain GPLv3. No Minecraft payload, Microsoft DLL, account, world, Apple SDK, Rosetta, or proprietary graphics runtime is redistributed by this backend. Its portable dependency source/notice inventory is still a public binary release gate. See [the build/readiness notes](runtime/bedrock/README.md).

The package integrity verifier uses public RSA verification parameters from Microsoft's official GDK package. These are public keys, not private signing or content-decryption keys. Their exact provenance and fingerprints are recorded in [verification notes](runtime/bedrock/verification/README.md). No GDK executable is bundled. Format behavior was checked against the pinned msixvc source and the [xvdtool verifier](https://github.com/emoose/xvdtool/blob/master/LibXboxOne/XVD/XVDFile.cs); no xvdtool code or executable is incorporated.

Minecraft’s library artwork is read at runtime from the owner’s installed game. The Minecraft/Mojang marks belong to their respective owners; no standalone Minecraft artwork or game asset is bundled with crossedover. The documentation’s interface screenshots show these marks to identify installed games.
