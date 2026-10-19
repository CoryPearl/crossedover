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
