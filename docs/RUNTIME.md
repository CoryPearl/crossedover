# Development runtime

The lock file records the downloaded CodeWeavers FOSS archive (Wine 11.0), experimental community dependency archive, and optional DXMT 0.80 artifact, pinned D9VK source revision, and official MoltenVK 1.4.2 archive. No installed CrossOver files are used in the runtime build.

Prerequisites on an Apple silicon build host:

- Xcode command-line toolchain.
- Homebrew `bison` 3+, `mingw-w64`, `freetype`, and `gnutls` headers.
- For `--d3d9`: Homebrew `meson`, `ninja`, and `glslang`.
- About 10 GiB available for sources, object files, runtime, and a test prefix.

```sh
python3 runtime/build.py --jobs 6 --metal --d3d9 --x87
```

The builder verifies each archive, extracts only Wine from the FOSS source archive, builds the i386/x86_64 PE architectures with an x86-64 Unix side, and packages an observer plus 32/64-bit smoke programs. Three narrow source patches export five Wine Metal driver APIs, allow an explicitly selected builtin overlay to precede the normal Wine DLL directory, and select software single-process rendering for Steam's primary CEF helper. The overlay is opt-in through CROSSEDOVER_DLL_OVERLAY and does not change Legacy profile lookup. CROSSEDOVER_STEAM_CEF_COMPAT affects only steamwebhelper.exe; it does not force games into software rendering.

Apple's system make strips DYLD environment variables. The generated Makefile explicitly supplies the dependency lookup when invoking the build-only FreeType font tool. Packaged Wine libraries use names resolved through the runtime's explicitly selected library directory. Build directories are not part of the application bundle.

`--configure-only` checks prerequisites. `--skip-build` packages an already compiled tree. `--metal` installs DXMT into a separate builtin overlay. `--d3d9` builds D9VK from the exact Git revision in the lock file, applies the attributed volume-slice and reflection fixes in `runtime/patches/d9vk`, and includes the hash-verified official MoltenVK 1.4.2 binary. This Wine build loads MoltenVK directly. The earlier DXVK 3.1/MoltenVK combination passed clear/readback but failed real textured draws; it has been replaced. All generated runtimes remain marked experimental.

The development build supplies dependency shared libraries from the pinned Gcenx Wine archive. Before public redistribution, replace this shortcut with a source-complete locked dependency build and verify every component's license, notices, and source delivery. The runtime includes a dynamically loaded MoltenVK dependency but no GStreamer integration; media-heavy games may fail independently of graphics rendering.

## Verification

Use a dedicated `--root` for smoke testing. Run both `share/crossedover/smoke-32.exe` and `smoke-64.exe` inside the prefix; verify pointer widths 32 and 64. Run the observer, then official Windows Steam. Verify login visually and interactively, not just process presence. `smoke --graphics` also checks actual 2D and volume-textured draws in six legacy color/luminance formats, in both Windows architectures. Test real gameplay before setting any recipe to verified.

## Lifespan

This runtime uses Rosetta. Apple documents general-purpose translation through macOS 27 and a restricted gaming subset afterward. macOS 28+ is not supported by this prototype. Replacing Rosetta is a separate compatibility-engine project, not a Swift compilation flag.

## Graphics renderers

The GUI offers **DirectX 9–11**, **DirectX 10–11**, **DirectX 9**, and **OpenGL fallback**. Saved/CLI IDs remain `combined`, `metal`, `performance`, and `legacy`. Existing choices keep their behavior. DirectX 9 uses the source-built D9VK D3D9 DLLs and official MoltenVK library; `d3d9=n` selects the installed architecture-matched DLLs. OpenGL fallback selects Wine’s builtin implementation with `d3d9=b`. DirectX 10–11 enables the DXMT builtin overlay. Combined mode enables both paths and is offered only if the runtime advertises both components. It adds no new runtime binary or DirectX 12 implementation. The dedicated DirectX 9 mode retains the optional x87 helper; combined mode does not enable it. Known recipes may still request a dedicated mode for their tuning.

Source-runtime manifests advertise `supportsMSync`. The app enables `WINEMSYNC=1` only when advertised, and removes inherited ESYNC/FSYNC settings. Every process in the environment must use the same synchronization mode; changing it requires a full environment restart. Older manifests remain readable and use the previous server synchronization mode.

The DXVK configuration is copied into `C:\crossedover\dxvk.conf` so it remains reachable with broad host drive mappings disabled. Reported D3D9 texture memory is limited to 1024 MiB for the old 32-bit demo. Normal Performance launches disable the DXVK FPS/frame-time overlay (`DXVK_HUD=0`). This is an experimental profile; GPU smoke checks and synthetic benchmarks do not establish game frame rate.

Run `crossedover benchmark` for the fixed 1280×720, 256-draw-call D3D9 comparison workload. It waits for GPU completion and reports mean/p95 frame durations. Run the same game track and settings to evaluate actual playability.

For a synchronization compatibility comparison, close Steam and games, then run `crossedover sync server`. All app/CLI launchers read the same prefix-local setting. Use `crossedover sync automatic` after stopping the environment to restore advertised MSync. Prefix backups preserve the choice. A successful GPU probe does not establish game responsiveness.

`--x87` includes a hash-verified PC24-aware x87sidecar from the TrackMania-MacOS 0.3.0 release. Its MIT license is packaged. Wine remains the local CodeWeavers FOSS build, with an opt-in cooperative startup patch; no installed CrossOver files or system Rosetta files are modified. The helper must pass `--probe` on the build host. Manifests advertise `x87RelativePath`; only Performance selects it. Legacy and DXMT do not use it. Older runtime manifests remain valid without the field.

The source runtime includes 32/64-bit x87 square-root and PC24/PC53 boundary probes, run by CLI smoke checks when the accelerator is selected. Numeric probes do not certify all x87 semantics or TrackMania physics/replay fidelity. The helper implements a binary64-backed subset; full 80-bit state remains outside its qualification.

The runtime retains its opt-in HUD diagnostics for developer investigations, but normal launches do not enable the frame-sampling flag. Earlier sampled presentation rates do not by themselves establish responsive input or race simulation.


Build 6 adds `runtime/patches/d9vk/0006-opt-in-process-dep.patch`. Its `d3d9.forceProcessDEP` option defaults to false and affects only 32-bit processes. `dxvk.conf` opts TrackMania into permanent non-executable data mappings and a 60 FPS/one-frame latency bound. The non-NX regression probe submits no draws and has a ten-second deadline. See the validation ledger for the reproduced mapped-buffer stall and the remaining full-game stability check.


`0007-flush-live-warning-diagnostics.patch` flushes warning/error records to the renderer file. Without it, a short run could show an empty file despite policy/frame messages waiting in the C++ stream buffer. The bounded game monitor uses the flushed policy confirmation and frame samples, rather than inferring activity from process presence or an empty buffered file.


Build 7 adds two opt-in Wine Mac Driver patches: `winemac-optional-cursor-clipping.patch` adds the per-application `AllowCursorClipping` switch; `winemac-native-fullscreen-size.patch` adds `FullscreenIgnoreMaxSize`. Both preserve upstream defaults. CrossedOver configures them only under `AppDefaults\\TmForever.exe\\Mac Driver`, alongside native Command keys, movable windows, and no display capture. The fullscreen policy lifts content maxima during the native transition/session and restores application constraints afterward. The incremental builder now rebuilds the Mac driver even with `--skip-build`, and provenance records Wine patch hashes.

Build 12 applies a CS2 window policy under its per-application Mac Driver key. CS2 retains `AllowCursorClipping=Y` for aiming and uses `CursorClippingLocksWindows=N`, `FullscreenIgnoreMaxSize=Y`, and `NativeFullscreen=Y`. The new `winemac-fixed-window-fullscreen.patch` opts titled, minimizable game windows into AppKit fullscreen even when their Windows style is fixed-size. Disabled windows and utility dialogs retain their restrictions; desktop sizing constraints are restored outside fullscreen. The switch defaults off and TrackMania leaves it off. This requires the rebuilt runtime, not just a registry setting.

The CS2 recipe selects DXMT Metal, passes windowed mode and a frame cap through Steam, and performs one-time migrations of borderless window settings, FSR upscaling and scene-detail performance settings, retaining only small original configuration copies. CS2's shipped `panorama/layout/settings/settings_video.xml` maps FSR Disabled to zero; the clarity migration preserves resolution and other quality settings. Later user choices are preserved by separate migration markers. Global RetinaMode is not changed because its coordinate-space policy is shared by the prefix. Startup/menu, native window controls and external-display menu click alignment have been confirmed. The owner reports local play looks good around 60 FPS with the low-detail preset. This is a short-run result, not a measured minimum across monitors. VAC-secured matchmaking remains blocked by a signature warning after verification, a fresh client session, Steam's own Play button and blank saved launch options; its exact cause and a verified correction remain unresolved.

Before launching the demo, the supervisor checks that its process is absent, prepares its own GBX windowed flag and keyboard capture setting, and saves a backup on the first rewrite. Unknown chunks survive unchanged; unsupported settings formats fail safely. No pointer events or screenshots are synthesized to validate the game. User confirmation remains necessary for click alignment, native controls and race responsiveness.


Build 8's optional `--audio` payload is the official OpenAL Soft 1.25.2 Windows binary, pinned by the release archive SHA-256 in `source-lock.json`. It includes the LGPL notice and source link. Only the 32-bit TrackMania demo receives this library; the original game DLL is saved under `C:\\crossedover\\backups\\trackmania-audio`, named by its original SHA-256. Every different Steam repair/update version is preserved independently. Runtime hashes advertise the fixed audio component path; older runtimes omit it and remain usable. A silent 32-source playback/spatial-update probe checks that the device clock advances and API calls succeed, with a ten-second deadline.

The per-game policy also disables `gameoverlayrenderer` and its 64-bit equivalent. The user does not need Steam's overlay for this demo. Performance now caps frame latency at two and initializes reduced car/background/ghost detail once, allowing later changes in the game's own settings. These changes improved the user's observed race rate to about 40 FPS with drops to 20; a sustained 60 FPS race remains unqualified.

`0008-frame-work-diagnostics.patch` samples existing renderer counters alongside FPS at most every five seconds. It reports draw density, CPU time waiting on GPU and command submission, queue occupancy, and graphics pipeline growth. It introduces no GPU timestamp query or synchronization. The patch applicator reconstructs known series-prefix states in a temporary Git index so overlapping patches can be rebuilt repeatedly without erasing local edits. `python3 runtime/test_build_patches.py` covers partial/repeated application and rejects unknown edits without changing them.


With the final OpenAL/runtime configuration, the user subsequently confirmed a smooth short race at 55–60 FPS. The prior 40 FPS result is historical. This remains short-run qualification rather than a strict minimum of 60 or evidence for other Windows games.


Build 16 adds `winemac-preserve-game-titlebar.patch`. With the existing per-CS2 `NativeFullscreen` opt-in, Wine retains native decorations for captioned game windows even if their Windows client and visible-window rectangles coincide. This covers client-drawn window frames; shaped, layered, and captionless windows retain their existing policies. Other executables keep upstream behavior. The CS2 window migration advances to v2 (with a separate backup) and its launch recipe requests a bounded 1280×720 window on every launch. Native fullscreen remains available through AppKit; graphics-quality preferences are not reset.
