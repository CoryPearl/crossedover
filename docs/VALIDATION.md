# Validation record

Validated locally on 2026-10-18: Apple M4, 16 GiB, macOS 26.6.2, Xcode 26.1.1 / Swift 6.2.1.

## Automated core checks

22 tests cover defensive VDF parsing, partial manifests, hash verification, traversal and symlink rejection, shell-free process arguments, cancellation/timeouts, environment locks, bounded runtime logs, transactional library replacement, backups/restores, failed upgrade rollback, deferred Wine registry writes, idempotent shutdown, Steam installation request routing with invalid identifier rejection, and graphics profile migration. The initial 19 tests passed in both debug and optimized release builds; all 22 passed in the updated optimized release build. The additions cover both DXVK architectures, switching back to builtin Legacy graphics, rejecting an incomplete Performance runtime, and reading older synchronization manifests.

## Real runtime integration

Runtime: `wine-11.0-cx26.3.0-dxmt0.80-c6be777f29`. Wine 11.0 compiled from the pinned CrossOver 26.3.0 FOSS source archive; pinned development dependency libraries and DXMT 0.80. Payload hashes cover 1836 files.

Fresh-environment integration succeeded: **13 checks passed**. The run imported and verified the runtime, created a fresh prefix, changed profiles only after shutdown, ran Windows execution and graphics probes, queried Windows processes, backed up/restored the prefix, and installed official Windows Steam.

| Probe | Result |
|---|---|
| 32-bit Windows program | Passed; reported 32-bit pointers |
| 64-bit Windows program | Passed; reported 64-bit pointers |
| 32-bit Direct3D 9 hardware clear/readback | Passed; pixel `ff4080bf` |
| 64-bit Direct3D 9 hardware clear/readback | Passed; pixel `ff4080bf` |
| 32-bit Direct3D 11 through DXMT | Passed; RGBA `[64,128,191,255]` |
| 64-bit Direct3D 11 through DXMT | Passed; RGBA `[64,128,191,255]` |
| Windows process observer | Passed; returned seven process observations |
| Official Windows Steam installation in a fresh prefix | Passed |
| Existing Steam environment migrated from community Wine to source Wine | Passed; backup preserved |

Raw integration evidence is retained locally under `.cache/integration-212ccd3d-d682-4137-af6a-c7912c3faea3/results.json` and its sibling phase logs. Reproduce with `python3 scripts/integration.py --runtime runtime/output/source-wine --steam-install`. No Steam credentials are needed for these checks.

## Steam UI investigation

The initial community Wine runtime produced a black window, confirmed by the user. Logs identified CEF/ANGLE failures. The source runtime now appends software/single-process flags specifically to Steam's main browser helper. Process observations confirm those flags and a single helper process. Steam binaries were not replaced or patched. The user subsequently signed in and confirmed TrackMania's installation and game window. Computer Use still cannot access the Wine window, so interactive evidence comes from the user. Credentials were not embedded in code, command-line arguments, or project files.

## TrackMania Nations Forever

The managed Windows Steam client downloaded app `11020`. Its completed manifest reports `StateFlags=4`, 510,081,328 bytes downloaded, and 776,953,234 bytes installed. CrossedOver discovers the real installation in its library. The installed Steam release reports version `2.11.16`. Launch was requested through Windows Steam using the Legacy profile, and the user confirmed a game menu or playable race. The user subsequently confirmed that the game runs with sound but is severely laggy, especially during races. Startup and audio are confirmed; comfortable play, saves and sustained play are not certified.

The new **Install in Steam** action routes an install URI through the managed Windows Steam executable. It acknowledges the request and directs the user to Steam's download confirmation; it does not report a completed installation until Steam's manifest is ready.

A separate test environment also installed the publisher's standalone `2.11.26` build successfully from `https://nadeo-download.cdn.ubi.com/trackmaniaforever/tmnationsforever_setup.exe` (530,600,781 bytes; SHA-256 `2f659138ed4409da404970841e18f03d29921beaf6a424824c8312ddb20f6355`). Its command-line benchmark exited with status 1 and a Wine OpenGL framebuffer error. Normal startup remained running until the test environment was stopped. This is not benchmark or gameplay certification. The user's Steam files were not replaced with this build, and game files are not included in the app package.

## Application packaging

The SwiftUI views have an app-owned static rendering path for layout inspection. This does not certify native control interaction or actual window behavior. The final full package includes the independently compiled runtime, passes strict signature verification, and is ad-hoc signed for local use. Its disk image passed `hdiutil verify`. The packaged supervisor also passed a real JSON IPC and worker handoff check launching Steam from the normal app data directory. Worker selection uses the current process executable, avoiding an outer application bundle executable being selected accidentally. The normal app data directory has the source runtime and Windows Steam installed; the app and Steam have been launched. It is not notarized or approved for public release.

No game is marked verified. M1/macOS 15 hardware validation, sustained gameplay, audio/input/controller checks, account-dependent flows, source-complete dependency builds, release signing, and notarization remain release gates.

## TrackMania performance iteration

The GUI now exposes only TrackMania Nations Forever. The other suggested games have been removed. Steam discovery and CLI services remain general purpose; the demo UI filters to app `11020`.

New runtime: `wine-11.0-cx26.3.0-dxmt0.80-dxvk3.1-46e9a27c41`. The optional Performance profile selects the pinned DXVK-MacOS 3.1 D3D9 backend and its MoltenVK library. Source-runtime MSync support is explicitly advertised and enabled consistently across processes. The D3D9 texture-memory report is limited to 1024 MiB for this 32-bit game. A visible FPS/frame-time HUD supports the next real-game comparison.

Fresh integration passed **19 checks**, including all three graphics paths, returning to Legacy after native D3D9 installation, backup/restore, process observation and a fresh official Steam installation. Evidence: `.cache/integration-644f5a6c-3213-4f0d-ae9f-492d139256d6/results.json`.

The existing user's environment was stopped and backed up during runtime migration, switched to Performance, and TrackMania was relaunched. Process observation found `TmForever.exe`; its new `TmForever_d3d9.log` confirms that DXVK is active. The user is currently unavailable for gameplay testing. Improved playability and in-game FPS remain unverified.

A fixed synthetic 1280×720 workload with 256 draw calls and GPU completion measured 2.268 ms/440.93 FPS for the original OpenGL path, 2.031 ms/492.28 FPS with MSync, and 8.333 ms/120.01 FPS for DXVK with MSync. These are synthetic throughput results, not TrackMania frame rates. The later textured-draw investigation invalidated the old DXVK result as a workload comparison: that graphics stack could pass clears while failing to render textures. The old figures are historical evidence only. The DXVK result is consistent with a presentation limit in this workload; no game speedup is inferred from these results. The new backend's 32-bit and 64-bit pixel readback also passed. Evidence: `.cache/trackmania-performance/benchmark-results.json` and sibling logs.

Unattended attempts to run the installed game's `Bench.Replay.Gbx` through its command-line interface produced no fresh benchmark result within the observation windows. Isolated attempts and a live Steam launch were tried; neither counts as a successful game benchmark. The game's normal launch is restored afterward. Existing numeric display settings report 1512×982; the user's graphics configuration was inspected but not rewritten. Game launches now request Steam's documented `-silent` tray-start mode; opening Steam explicitly still presents its normal UI.

## Monochrome interface

The home screen now contains the TrackMania title, Play action and Open Steam link on a flat charcoal canvas. Settings holds graphics and Steam controls; recovery, runtime management, backups and diagnostics are under Advanced. The icon is monochrome as well.

The release build passed. App-owned static renders of home at 1100×760 and 840×620, plus Settings, were visually inspected. Pixel checks confirmed grayscale throughout all three renders and the icon. These checks cover layout, not live window interaction. The existing TrackMania process remained running during the update. Evidence: `.cache/monochrome/validation.json` and sibling images.

## TrackMania rendering correction and logo

The user reported wrong colors, missing/flickering textures and blurry/blocky rendering with the original Performance runtime. A new fixed-function textured-draw probe reproduced a rendering defect in the DXVK 3.1 stack: all 15 initial 2D/volume color samples retained the blue clear color instead of the expected texture color. Legacy/OpenGL passed the same probe. Strict shader arithmetic did not fix it. Native D3DX30 was already selected correctly and passed the legacy shader-qualifier check; no compiler override was added.

D9VK with the old bundled MoltenVK also failed those draws. D9VK with the community MoltenVK 1.4.0 passed the 64-bit probe but failed 32-bit buffer creation. Source-built D9VK at `f229921c1b7f14edeadeccff04a9e65d0a016148`, with the two attributed volume/reflection patches and official MoltenVK 1.4.2, passed the 32-bit probe. DXVK 3.1 with official MoltenVK 1.4.2 still failed; both components were therefore replaced.

New runtime: `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-442df3c8e1`. `runtime/build.py --d3d9` now builds the pinned D9VK source and verifies the official MoltenVK archive hash. Native D3D9 selection and the Performance profile remain unchanged. No asynchronous pipeline draw skipping is enabled.

The permanent `runtime/d3d9-textures.c` check exercises actual draws in six formats, including promoted A4R4G4B4 volume slices: 18 expected-color checks per Windows architecture. `smoke --graphics` now runs this probe in addition to clear/readback. Fresh integration passed all 19 phases, including 32/64-bit Legacy and Performance drawing, switching back to Legacy, DXMT D3D11 readback, backup/restore, and fresh official Steam installation. All 22 release unit tests passed. Evidence: `.cache/integration-d5b26b5b-1bfd-41cf-b6cc-8138413c6967/results.json` and `.cache/rendering-investigation/`.

The home screen displays TrackMania's official logo from the user's Steam artwork cache. The app converts it to grayscale and lifts its dark details for contrast on the charcoal background. The app-owned render was visually inspected and has zero RGB channel difference throughout. No game artwork is bundled. Missing cache artwork falls back to the existing title.

These probes establish that the reproduced texture-drawing defect is corrected in the replacement runtime. Actual TrackMania appearance and frame rate still require the user's next gameplay check; no speedup is inferred from the probes.

The existing environment was backed up as `E22534FA-41E6-46FE-938F-16538FE14431`, then migrated to the new runtime with Performance preserved. Both installed D3D9 DLL hashes match the built runtime. The updated app and TrackMania were launched; `TmForever.exe` was observed. App signature and disk-image verification passed. Final evidence: `.cache/rendering-investigation/results.json`.

## Frozen game investigation

The user confirmed that the replacement runtime renders colors and textures correctly, but reported a frozen game at 0 FPS. A three-second macOS process sample found the game thread largely waiting in alertable delay/server calls while the D9VK submission and command threads waited idle. This sample does not establish the cause of the freeze. The game later exited. A 32-bit timing probe completed 20,000 zero-time alertable waits in 173.754 ms and correctly delivered a queued APC. A separate D9VK synthetic workload completed at 120.14 FPS; neither number establishes actual game responsiveness.

Added an explicit, prefix-local standard-server synchronization fallback shared by app, CLI and detached workers. Changing it requires the environment to be stopped. The marker is included in prefix backups and restores. `crossedover sync server` selects it; `crossedover sync automatic` restores runtime-advertised MSync. No graphics backend or game settings changed for this comparison.

All 23 release tests passed, including backup/restore of the synchronization choice. The isolated environment also passed 32/64-bit execution, clear/readback, and all 36 textured-draw checks with standard synchronization. Steam and the native app were stopped before selecting the fallback in the user's environment; a normal TrackMania launch was then requested. The actual-game result of this comparison is awaiting user confirmation. Evidence: `.cache/trackmania-stall/`.

The user subsequently confirmed the stall is in the main menu and that standard synchronization remains around 0.4 FPS. The synchronization comparison did not resolve the problem.

## x87 translation iteration

The standard-synchronization process sample showed substantial Rosetta exception/translation activity. This led to an isolated x87 acceleration trial. The pinned PC24-aware x87sidecar from TrackMania-MacOS 0.3.0 passed its host compatibility probe. A locally adapted opt-in Wine loader handshake supports cooperative startup without privileged attachment or changes to system Rosetta files. With no selected helper, the loader follows its existing path.

An isolated 32-bit 100,000-square-root loop measured 14.148 ms on stock translation and 0.315 ms with the helper. Both produced exactly 2 and passed the tested PC24/PC53 precision boundary. These numbers describe one math loop, not game FPS. A later packaged-runtime probe measured 0.228/0.225 ms in 32/64-bit modes, with the same numeric checks passing.

Manifests now optionally advertise a contained, executable `x87RelativePath`. Only Performance selects it; Legacy and DXMT remove inherited helper/handshake settings. All 24 release tests passed, including helper validation, containment, profile selection, and old manifest compatibility. The full accelerated runtime passed all 19 integration phases with 32/64-bit textured rendering, precision probes, graphics fallback, DXMT, backups, and official Steam installation. Evidence: `.cache/integration-488cde8e-f844-43f1-b293-5ffe5674b5e8/results.json`.

Final runtime `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-eda6a2935f` also contains an original, opt-in D9VK HUD diagnostic patch. It records presentation rate at most once every five seconds when requested by the managed launcher. The final artifact separately passed graphics, precision and synthetic benchmark checks; evidence: `.cache/trackmania-stall/frame-verify-results.json`. The diagnostic patch changes logging only. Presentation rate does not by itself certify input responsiveness or race simulation.


## Data-buffer stall correction (build 6)

The user confirmed that x87 acceleration and the GDI auxiliary path both left the menu around 0.4 FPS. A later 1280×720/lower-shader-quality settings trial briefly showed 30–60 FPS, but the user reported recurring freezes and a whole-Mac hang. That trial does not establish playability. All user-game and diagnostic Wine processes were stopped following the report. The previous settings are saved beside the active config as `Default.SystemConfig.pre-performance-trial.Gbx`; the trial preserves every non-display GBX chunk byte-for-byte.

Read-only Windows thread samples repeatedly found the game inside UCRT's SSE copy, writing 64-byte shader constants into mapped graphics memory. The executable lacks NX compatibility. Wine's loader therefore enables executable data mappings; `vmmap` confirmed writable/executable shared graphics buffers. A small isolated test, submitting no draws or presentation commands, reproduced the distinction: 1,000 64-byte mapped-buffer copies timed out after five seconds under the legacy policy, while enabling process DEP completed them in 0.006 ms with identical bytes. Ordinary heap copies completed in both modes. Evidence: `.cache/trackmania-stall/mapped-copy-results.json` and `mapped-copy-{legacy,nx}.log`. This strongly identifies a reproduced buffer-write stall; it does not establish the cause of the reported whole-Mac hang.

The new opt-in D9VK patch uses Windows' process DEP API before creating graphics buffers. The packaged configuration enables it only for `TmForever.exe`, caps presentation at 60 FPS, and limits frame latency to one frame. Explicitly executable allocations remain supported; game executables and system Rosetta files are unchanged. A non-NX mapped-buffer regression probe verifies permanent DEP, 16 copy alignments, and byte correctness with a ten-second watchdog. Prefix setup, migration and repair now use Wineboot's restart option with update, skipping Steam's Windows startup entry.

The TrackMania logo now retains its source colors, as requested; the surrounding interface remains monochrome. An app-owned render was visually inspected at `.cache/trackmania-stall/color-logo-preview.png`. Game artwork is still read from the user's Steam cache, not bundled.


The packaged-policy candidate passed the non-NX regression: 2,048 copies across 16 source/destination alignments completed in 0.038 ms, with permanent DEP and exact bytes verified. Evidence: `.cache/trackmania-stall/dep-probe.log`. The initial parallel recovery-test runs exposed one-second process-exit deadline failures under build/import load. Recovery fixtures now run serially and the stopped-environment precondition allows three seconds; all 24 release tests then passed (`dep-final-tests-serialized.log`). Packaging now verifies runtime contents and every manifest hash both before and after copying the runtime, preventing a partially rebuilt runtime from being bundled.


Final runtime `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-4aef9c4cf2` passed 32/64-bit execution, both D3D9 clear/readback probes, all 36 textured-readback checks, the non-NX mapped-buffer regression (0.036 ms), and both x87 precision probes. Evidence: `.cache/trackmania-stall/dep-final-graphics.log`. The app's signature and disk-image checksum passed; the bundle contains the final runtime and its hashed regression executable. These checks do not certify sustained races or explain the whole-host hang.


The first two bounded real-game observations saw the game process but no on-disk diagnostics. Source inspection showed that the D9VK logger buffered messages without flushing warning records; zero file size therefore did not establish that the process policy was missing or that no frames were presented. A follow-up patch flushes warning/error output so policy confirmation and five-second frame samples can be observed during a bounded run. Exact full-string scans are also unsuitable for optimized C++ literals, which this compiler may split into constants and immediate stores. No game-performance conclusion is drawn from those two observations.


The final live-logging runtime is `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-6e49701432`. It passed the full graphics/precision checks in the user's managed prefix (`live-user-graphics.log`), package hash verification, app signature validation, and DMG checksum verification. The bounded menu run confirmed process DEP in the real game and repeatedly logged 59.9–60 FPS. The user explicitly confirmed that the menu stayed smooth. Evidence: `.cache/trackmania-stall/live-menu-results.json` and `live-game-d3d9.log`. The monitor stopped the managed environment at the end of the bounded observation. Sustained race performance remains a separate check.


### Window controls and race follow-up

The user confirmed a smooth menu but reported significant race drops, a vertical click offset, and inability to leave exclusive fullscreen. The first race log sampled approximately 4–25 FPS during its slower portion (`race-check-observation.json`). Menu rates do not qualify racing.

Build 7 prepares TrackMania's own windowed display mode before launch, preserves unrelated GBX chunks byte for byte, disables its keyboard capture flag, and backs up the original settings. An original bounded LZO1X decoder handles compressed settings; malformed/truncated inputs fail without rewriting the original. A per-game Wine Mac Driver policy releases pointer confinement, keeps Command keys native, allows moving/minimizing, and avoids display capture. Other executables retain Wine defaults. The user reported that window/pointer behavior looked better, but racing remained around 5–10 FPS. MSync was restored to Automatic; its startup messages also exposed and prompted correction of observer JSON parsing.

All 28 release tests passed, including compressed settings preservation/idempotency, malformed input bounds, overlapping/long-distance LZO matches, and observer output with runtime diagnostics. The first window runtime `3012a84ccf` passed the complete graphics/precision checks and package/signature/DMG verification. Runtime logs confirmed windowed presentation with a 1280×720 drawable. CPU samples during the slower session are saved as `race-windowed-cpu-1.txt`.

The user additionally reported a centered image filling neither fullscreen dimension. Wine's native-fullscreen delegate clamps its proposed size to the game's content maximum. A second opt-in patch bypasses that maximum only during native fullscreen and restores normal window constraints on exit. A separate reversible shader-quality trial changes the existing custom shader word from 0 to 2; no race improvement is claimed until observed. The command-line replay benchmark still opened a menu and produced no fresh result, so its samples are not a race benchmark.


The fullscreen candidate runtime is `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-097d800106`. It passed all graphics/precision probes (`fullscreen-graphics.log`), package runtime-hash checks, strict app signature verification, and DMG checksum verification. All 29 release tests passed, including repeated preparation preserving the first backup and releasing only the keyboard-capture field. The active prefix was backed up during migration. The shader-2/fullscreen race check is pending user feedback.


The user confirmed fullscreen now looks correct. The shader-2 trial still produced roughly 1–7 FPS while driving, so its shader word was restored to 0. Its renderer resized to 1512×949 in native fullscreen. The module inventory showed the old Creative `wrap_oal.dll` software audio mixer and Steam's injected `gameoverlayrenderer.dll`. A bounded silent OpenAL device probe with 32 playing sources verified audio progression for both the original mixer and official OpenAL Soft 1.25.2; 32,000 position updates took 7.072 ms and 2.482 ms respectively. These API timings do not establish game performance. The official binary archive SHA-256 matched GitHub's release digest. A reversible local audio-library replacement and per-TrackMania overlay-disable policy are being tested; neither is yet a validated race fix.


The user confirmed the audio/overlay trial was better: about 30 FPS, with occasional drops near 10. A subsequent trial retained OpenAL Soft and disabled overlay injection, raised the D9VK frame latency cap to two, lowered car detail to 1 and background detail to 0, and disabled ghost-car rendering via the maximum-opponents field. The user reported roughly 40 FPS with drops near 20 and requested a steady minimum of 60. That target has not been achieved. Frame samples and CPU observations are under `openal-no-overlay-check*` and `scene-queue-check`.

Build 8 packages the official hash-verified OpenAL Soft 1.25.2 payload and license as an optional runtime component. Launch preparation verifies that component, backs up every distinct original Steam library by content hash, and atomically installs it only for TrackMania. Repeated launch preparation and Steam repair/update preservation are covered by tests. The reduced scene preset applies once per existing settings file, preserving subsequent user graphics choices. A new bounded renderer log reports existing queue wait/counter data without new GPU queries or extra synchronization; queue occupancy is explicitly not hardware GPU utilization.


### Build 9: game management

Added per-game properties, Show game files, Steam file verification and Steam uninstall requests. The application passes only validated numeric App IDs to the managed Windows Steam executable; uninstall uses Steam’s own confirmation instead of deleting installation directories directly. Verification/uninstall require a currently discovered installation and an observer-confirmed absence of game processes. The GUI also disables these operations during a tracked session. Steam owns completion; the regular library refresh then switches the demo between Play and Install. Downloads is accessible from Settings.

Open Steam is now a secondary outlined header control with an external-window icon, separated from the solid Play button under the game title. Original-color TrackMania artwork and the monochrome spacious layout are preserved. App-owned normal and compact renders were inspected under `.cache/trackmania-stall/game-management-*.png`. CLI request forwarding and rejection tests cover management routes, malformed IDs, and a running game; the installed demo was not uninstalled for testing.


Build 9 passed all 33 release tests after an unloaded repeat (`game-management-tests-final.log`), app signature validation and DMG checksum verification. The initial test run overlapped package/runtime startup work and one recovery fixture hit its stopped-server deadline; no assertion in the new management tests failed. CLI properties/downloads requests were acknowledged by the managed Steam worker. Steam dialogs and an actual uninstall were not visually confirmed. Full graphics/audio regression passed for the included audio runtime (`audio-final-graphics.log`), including playback clock progression and the no-NX mapped-buffer probe. The live 60-FPS target remains incomplete; current confirmed race behavior is roughly 40 FPS with drops near 20.


The current workload-instrumented live session logged an initial compilation stall, then a series around 57–60 FPS with roughly 170–460 draws per frame and negligible measured GPU/command-thread wait. The queue occupancy counter was around 11–16%; it is not a hardware utilization measurement. CPU stack sampling was disabled for the continued observation to avoid perturbing interactive performance. These samples are saved under `frame-work-live-*`; the exact gameplay phase and steady 60 FPS responsiveness are still awaiting user confirmation.


**Latest user result:** “it ran smoothly at 55–60 fps” during the requested short race with runtime `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-openal1.25.2-e0a631ed57`. The working audio/overlay policy and reduced scene/two-frame configuration are retained. This confirms a smooth short race near the 60 FPS target, not a strict minimum or long-session stability. The read-only monitor was ended without stopping the game. Build 9 includes the separately validated management interface.

### Build 10: structured monochrome interface

Replaced the floating header/content layout with a fixed navigation rail, shared page gutters and headings, and bordered content groups. Library now has one adaptive TrackMania card with an artwork area, game details, and a separated action footer. Play and Manage share that footer; Windows Steam opens from its own outlined sidebar control. Settings, Advanced, Activity, notices, and Diagnostics follow the same border and control sizing. Existing game-management actions and runtime configuration are retained.

Validation on 2026-10-18:

- Release compilation passed (`.cache/visual-refresh/build.log`). No new core behavior was introduced; the existing 33-test result belongs to Build 9.
- Generated and inspected app-owned SwiftUI renders at 1100 × 760 and 840 × 620. Checked Library, Settings, expanded Advanced, Activity, setup, installation, running, busy, and notice states. Also checked first launch and empty Activity using an isolated data root. Expanded Advanced uses a tall preview to inspect normally scrolling content.
- Native menus and the indeterminate spinner use static equivalents in ImageRenderer. The render checks establish composition and state layout, not native menu interaction, keyboard focus, live scrolling, or window chrome.
- Packaged app build 10, verified its deep/strict code signature, and verified the DMG checksum. Opened the packaged app and confirmed its process remained running. No game was launched, uninstalled, or reconfigured for this visual pass.

Preview images and command output are under `.cache/visual-refresh/`. Design constraints and reproduction commands are in [DESIGN.md](DESIGN.md). The game-performance result above remains the latest user-confirmed gameplay evidence.

### Build 11: all installed Windows Steam games

Removed the GUI's app-11020 filters from discovery, persisted fallback data, and preview rendering. The library now displays every completed game installation from managed Windows Steam libraries, sorted by name, with adaptive cards, cached Steam artwork, storage usage, and per-game Play/Manage controls. Incomplete downloads and Steamworks Common Redistributables are excluded. TrackMania keeps its tested demo configuration; other games are labeled with untested compatibility. The empty library retains the optional TrackMania demo installer.

Session presentation and Activity names now follow the requested game's identity. Generic game tracking and pre-management checks inventory installed executable basenames without following symbolic links, with a 50,000-entry limit and Steam fallback when observation is unavailable. This is conservative process matching, not compatibility certification. TrackMania's settings/audio preparation still applies only to app 11020. Runtime binaries and graphics configuration were not changed.

Validation:

- All **36 release tests passed** (`.cache/all-games/tests.log`). New coverage checks multiple games across two managed Steam libraries, modern cached-artwork paths, exclusion of incomplete downloads and shared redistributables, library replacement after uninstall, generic executable detection without traversing links, and rejection of management requests for an active game without a recipe. The first executable-inventory test caught a directory-enumeration bug; it was corrected before the passing full run.
- Release build and `git diff --check` passed. App-owned renders checked one, two, and three game libraries at 1100 × 760 and 840 × 620, plus tall scrolling-content previews, missing artwork, long names, running and unknown session states, and an empty library. Native menu interaction is not established by static rendering.
- CS2's real manifest was observed in an incomplete download state. The multi-game previews used explicit in-memory fixture metadata; no real Steam manifest was edited to pretend the download had completed. No game was launched or uninstalled for this change.
- Packaged build 11, passed deep/strict app signature validation, and verified the DMG checksum. Reopened the packaged native app. No remote was configured or pushed.

Artifacts: `.cache/all-games/`; preview fixtures contain only local library metadata and are ignored by Git.


## CS2 native fullscreen and clarity — 2026-10-19

The user confirmed CS2 startup/menu and its own in-game fullscreen work, but the native green button still failed and the image looked soft. Source inspection found that Wine requires a resizable native window for fullscreen and rejects Windows-maximized windows. The new opt-in `NativeFullscreen` patch permits eligible fixed-size game main windows, and bypasses resize locking during native fullscreen while restoring desktop constraints afterward. It is enabled only for CS2, preserving the TrackMania policy.

The live saved graphics configuration reported FSR detail 2. The game's settings layout maps 2 to Quality and 0 to Disabled (reference: https://github.com/SteamDatabase/GameTracking-CS2/blob/master/game/csgo/pak01_dir/panorama/layout/settings/settings_video.xml). A separate one-time clarity migration disables that internal upscaler, backs up the original bytes, and preserves other settings and later user choices. The prefix-wide RetinaMode is unchanged; this is not a claim of physical-panel native resolution.

The rebuilt source runtime has content ID `591dba8b13` and was imported and selected through the normal backed-up migration. 32/64-bit Windows execution and DXMT Direct3D 11 pixel readbacks passed (RGBA 64,128,191,255), as did the OpenAL playback-clock smoke check. All 39 Swift tests and the offline patch-series regression passed. The release app and DMG were rebuilt. Native fullscreen transitions, improved clarity, and CS2 match performance remain unconfirmed until the user checks the new run. No Wine UI was inspected or automated.


## Branch application icon — build 13

Replaced the upright arrowheads in the app-icon generator with original outward diagonal arrowheads and a rounded shared stem to match the sidebar branch motif. The generated 512-pixel and 32-pixel assets were visually inspected. Repackaged the existing release binaries and current source runtime without changing game settings or stopping Steam/game processes. This is an icon-only app change; the preceding 39-test result remains the last code validation.


## Responsive library, search, and list mode — build 14

Removed the library's 940-point width cap and its oversized single-game layout. Grid columns now adapt between 250 and 320 points; artwork is 112 points tall and normal card footers have a consistent height. The header and library use the available window width. Added live localized title search, clear/no-results states, Command-F focus, Escape clearing, and a persisted grid/list selector. List rows retain game controls and current-session behavior.

The release build passed. App-owned ImageRenderer previews were inspected at compact (840), default (1100), and wide (1920) widths, using explicit fixture metadata for a larger library. The default grid fits three columns and the wide grid six. Matching and nonmatching searches and compact list rows were checked, including a deliberately long title. These static previews do not establish live keyboard interaction or scrolling. No Steam/game configuration or installation was changed.


## TrackMania overlay disabled — build 15

Normal Performance launches explicitly set `DXVK_HUD=0` and no longer enable the CrossedOver frame-sampling diagnostic flag. The existing environment sanitization removes inherited values for both. The visible FPS/frame-time display was a managed renderer diagnostic, not a change to TrackMania’s own preferences. The change applies after the Windows Steam/game environment restarts; no running game was interrupted.


## CS2 native title-bar retention — build 16

The user reported CS2 had no traffic-light controls, while TrackMania did. The saved CS2 configuration was already windowed and bordered (both fullscreen and nowindowborder zero) but its dimensions were 1512×982, matching the desktop. No custom Steam launch options were present. Wine's Mac driver discards all native decorations when the Windows visible and outer rectangles coincide, even if WS_CAPTION remains set. Added a per-CS2 opt-in exception to preserve captioned native frames in that case; shaped, layered, and truly captionless styles keep their existing policy.

The source runtime was rebuilt as content ID `5fb685fcd2`. A v2 backed-up video migration restores a framed 1280×720 desktop window, including for installations with the v1 marker; older backups remain intact. The recipe now explicitly requests that initial desktop size on every launch. Native fullscreen remains available through the existing fixed-window opt-in. All 39 Swift tests passed, and the revised settings regressions passed separately, including migration from a v1 marker without replacing its backup. The release build and offline patch regression passed. The updated runtime passed the Performance graphics, mapped-copy, x87 precision, and OpenAL smoke checks. The environment was then switched to Metal; both 32- and 64-bit D3D11 pixel-readback checks and the OpenAL playback check passed. The v2 migration was observed to save the previous file and write fullscreen=0, nowindowborder=0, defaultres=1280, defaultresheight=720 before the CS2 relaunch. The native title bar and controls still require user confirmation after relaunch; no Wine window was inspected or automated.


## Lowercase product branding — build 17

Adopted the lowercase wordmark `crossedover` in the sidebar, app metadata, settings/activity copy, diagnostic labels, and app/DMG filenames. Internal bundle identifiers, executables, resources, and the existing data location keep their established names. The release build passed and the compact app-owned library preview was visually inspected. This change does not modify game or runtime settings.


## Search focus dismissal — build 18

Added a search-field-scoped AppKit click observer, active only while search has focus. Clicks outside the search region clear its FocusState while returning the original event so buttons and menus still respond on the first click. Clicks inside the field or its clear button keep normal editing behavior. The observer is removed when focus ends or the view is dismantled. Search text is preserved. The release build passed; live interaction was not automated.


## v1.0.0 release preparation

Unified the app, CLI, diagnostics, package metadata, documentation, and website around v1.0.0 (build 19). The app root extends through the top safe area so the sidebar divider continues behind the hidden title bar in normal windows. This native title-bar behavior remains a visual check; app-owned grid/list previews were generated for the documentation and website.

All 39 Swift tests and the release build passed. Offline website checks passed for release versions, local links, image metadata, and the standalone quickstart. The v1.0.0 DMG passed signature/checksum checks and includes the app, Applications shortcut, offline Start Here guide, GPL license, third-party notices, and GRDB/Sparkle licenses. No account, prefix, game installation, or credentials are packaged. The site deployed through Sites with owner-private access. Browser UI verification was unavailable because the browser service referenced a missing plugin component; no alternate access route was used.

GitHub publication preserves the repository’s private visibility. The v1.0.0 number does not close the signing, notarization, dependency-source, compatibility, or fresh-machine gates listed in RELEASE.md.

## v1.0.0 build 20 — storage controls and native UI work

Full environment backups are now explicit only, including during runtime changes. A failed or interrupted in-place runtime update leaves its files in place, marks the environment as needing repair, and blocks Steam launches until repaired or manually restored. Existing backups were not deleted. Settings adds a confirmed backup-to-Trash action and a complete app/data uninstaller; removal is restricted to the fixed managed data root, validates the packaged app, holds environment locks, and requires all managed Wine environments to stop. Backup cleanup rejects links, including a Backups link to the current Environments directory. The destructive uninstall UI was not executed against the user's library.

All **43 Swift tests in seven suites passed**, including successful/failed upgrades without full backups, repair recovery, launch blocking after failure, managed games-folder routing, and removal target/link rejection. The optimized build passed. The packaged app started successfully against an isolated empty data folder, remained alive for the ten-second startup smoke check, and created no backups. Its idle process snapshot was 0.0% CPU and 105,728 KiB RSS; this is a startup smoke result, not an interactive responsiveness or gameplay benchmark.

Library discovery and SQLite refresh writes now run off the UI actor. Equal snapshots are left alone, automatic refresh only runs while the app is active at eight-second intervals, artwork thumbnails have a bounded memory cache, and unchanged running sessions no longer cause repeated writes and redraws. Finder opens the managed Steam `steamapps/common` folder; Steam Downloads remains a separate action. Settings explains Legacy, Performance, and Metal. App-owned ImageRenderer previews of library, minimum-width settings, and expanded advanced settings were reviewed. The native window divider still extends to the top safe area. Native window interaction and browser QA remain unverified.

The v1.0.0 build 20 DMG passed `hdiutil verify`, mounted read-only, and passed strict recursive app signature verification. Its app version/build, offline quickstart, Applications link, and license notices were checked. Size: **262,253,711 bytes**. SHA-256: `4b4ca78722244ae8f87b73d2b80dd10c8f923a2a25924d981a12240f9628001f`. The release remains locally signed and not notarized. The offline release checker passed after refreshing the library/list images and documenting planned support beyond Steam.

Website edits are prepared in `website/`. The existing Sites project currently returns `project_not_found` for both access lookup and source-credential renewal. Its identity and audience were preserved; no replacement project or deployment was created. Live redeployment of these edits is blocked by project access, while the local static build and link checks pass.

## v1.0.0 build 21 — mods, file access, and Steam naming

The per-game **Mods & files** sheet exposes the discovered installation folder and contained Windows Documents in Finder, with instructions for manual mods and normal Workshop subscriptions. Game-file discovery runs off the interface actor. Mod managers, DLL overrides, and script extenders are not configured automatically. The normal Windows shell folder route remains available for Steam's Browse action.

All **46 Swift tests in eight suites passed**. New coverage checks Documents discovery and link/traversal rejection, and validates the optional Steam loader path, executable requirement, old-manifest fallback, and containment. The optimized build and offline patch-series regression passed. The complete branding patch was verified against the built Wine source. An app-owned ImageRenderer preview of the modding panel was reviewed; no Wine window was inspected or controlled.

A temporary managed prefix exercised `runtime/modding-smoke.c`: a Windows file write/read round trip matched native macOS file contents, and `ShellExecuteExW` accepted opening its containing folder. Separate Steam and web-helper fixtures both reported **crossedover Steam** through macOS process identity metadata. A non-Steam fixture did not acquire the Steam name. These checks do not certify individual mods, mod managers, or Workshop content loading inside a real game. The test prefix was stopped and removed after retaining its results and logs; the user's game files were not used as fixtures.

Runtime `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-openal1.25.2-4c7facecf6` adds an optional named native Steam loader and an opt-in naming patch for direct Steam startup, child Steam/web-helper processes, macOS menus, and generic Steam/Wine window captions. Games and descriptive dialog captions retain their existing naming paths. Performance passed 32/64-bit execution, D3D9 readback/textures, mapped-copy/DEP, x87 precision, and OpenAL checks. Metal passed 32/64-bit D3D11 readback and OpenAL. Legacy passed D3D9 readback/textures and OpenAL. A profile switch was correctly blocked while fixture Windows processes were still active; the isolated fixture was explicitly stopped before switching. These are smoke tests, not new game FPS or long-session measurements.

The installed user environment was stopped before migration, retained its Performance profile, returned to ready, and created no automatic full environment backup. Windows Steam was reopened through the named loader; its real host process reported **crossedover Steam** in macOS application metadata. Existing installs can select **Settings → Advanced → Use included runtime** after quitting Steam and games. The included runtime action reuses an already installed matching runtime and avoids copying it again when current.

The **v1.0.0 build 21** DMG passed checksum verification and read-only mounting. Version/build metadata, strict recursive signatures, the updated offline guide, and the bundled named loader's executable permission and manifest hash were checked. Size: **259,353,757 bytes**. SHA-256: `8ed5a92ccbf7f08f9535b244356182ffa10a6e46722e5046f33294a86c1a4d23`. The short app version remains 1.0.0. This build uses its own source tag, `v1.0.0-build.21`, preserving the original v1.0.0 tag and release. Notarization, public dependency closure, and fresh-machine validation remain unchanged release limits.


## v1.1.0 Windows app runner

The Games and Apps libraries keep imported Windows executables as persistent cards, independently of Steam discovery. 52 core tests pass, including x86/x64 PE validation, unsupported ARM/DLL/truncated image rejection, folder sidecars, executable retargeting, category persistence, symlink/traversal rejection, rollback after failed imports, shell-free arguments, nonzero exit status, missing executables, the 1 MiB log cap, manual backup/card restore, malformed restore metadata, and legacy backup handling.

`scripts/windows-app-integration.py` compiles the owned `runtime/windows-app-smoke.c` for both x86 and x64 and runs imports through the real packaged-runtime supervisor in a fresh isolated prefix without Steam. Both architectures passed: sidecar reads, registry writes, hidden native window creation/message dispatch, persisted running/exited states, duplicate-launch rejection, and launch after the source payload was deleted. The harness stops only its own Wine prefix and removes its test data; no automatic backups are created. This does not certify arbitrary third-party software, rendering correctness, or long-session stability.

App-owned SwiftUI renders check Games, Apps, grid/list, empty states, a compact window, a wide multi-card library, and the import sheet. Native inputs are replaced only in preview rendering. These checks do not claim interactive validation of file panels or third-party app UI. Steam game runtime binaries and game tuning are unchanged from build 21; the new generic runner uses the regular Wine loader without Steam branding.

## v1.2.0 Windows Epic integration and UI work

All **59 Swift tests in ten suites passed**. Epic coverage includes completed/incomplete/DLC/engine manifest handling; executable existence and path containment; unsupported drives and link/traversal rejection; legacy Steam decoding and cross-store identity; independent provider fallback; official MSI host/header checks; shell-free launch arguments; library-only management routes; and active-game management rejection. The release build passed without warnings.

The official Windows Epic MSI 20.3.3 installed successfully in an isolated prefix, then in the existing user environment. The current launcher’s Direct3D 11 UI failed with the saved Performance backend; the integration now selects Metal only for Epic’s process tree. Its startup log identified the Apple M4 D3D11 device. The user confirmed Epic opened and sign-in succeeded. No credentials or account files were read. The saved Performance profile for Steam and imported apps was preserved. The user also reported lag in both the Mac app and Epic; an installed Epic game and live responsiveness follow-up remain pending.

`scripts/epic-integration.py` passed in an isolated Wine environment with an owned launcher stand-in: complete-only discovery, composite launch-URI handoff, child-process launch with valid D3D11 pixel readback under Metal, management routes to Library, and card removal after a simulated completed uninstall. No Steam installation or accounts were present and no automatic full backups were created. This verifies the integration plumbing, not Epic authentication, actual store downloads, real game rendering, or compatibility.

A three-second sample of the running v1.1.0 Mac app showed its main thread waiting for events throughout the sample (51.3 MiB physical footprint); it did not capture an active scrolling stall. Resource snapshots showed Epic web helpers using more CPU while system memory remained available. New v1.2.0 artwork requests perform disk reads, thumbnail generation, and immediate image decompression on a separate actor as lazy cards appear, with bounded caching. Launcher workers throttle bounded-log rewrites to four per second and flush at exit. These remove synchronous artwork work and excess log I/O; they do not establish a measured interactive frame-rate improvement or resolve Epic’s own reported UI lag.

App-owned grid, list, Apps, and compact/settings previews were reviewed. Example Epic cards are labeled illustrative in website captions. No Wine UI was inspected or automated. Runtime binaries and TrackMania tuning remain unchanged from v1.1.0.

The user reported the first artwork/log changes did not resolve scrolling lag. A subsequent 20-second Mac-app sample during scrolling identified repeated SwiftUI layout/display work. Native scrolling for Settings/Activity improved responsiveness according to the user, with some stutter remaining. Follow-up profiling showed intrinsic-size feedback; the scroll document now measures explicitly only on content/width changes, disables automatic intrinsic constraints and viewport safe areas, and keeps the library lazy. An owned hidden-window geometry fixture passed initial sizing, clip scrolling, width/height expansion and contraction. Its synthetic 240-step scroll CPU check measured p95 0.038 ms and maximum 0.181 ms; these are geometry/layout timings, not display FPS or a real user benchmark. The user then confirmed “everything is smooth now.” No displayed 60 FPS measurement was taken; this confirms perceived responsiveness on the current Mac, not a universal minimum FPS guarantee.

The packaged supervisor/runtime also passed the owned Epic handoff/readback fixture and both x86/x64 Windows-app import/launch fixtures, including sidecars, registry I/O, window creation, persisted status, duplicate-launch rejection, and operation after the source payload was removed. All fixtures created no automatic backups and removed their isolated data.

## v1.3.0 partner discovery, graphics, Xbox assessment, and website count

**64 Swift tests in eleven suites passed**, including the actual Epic partner-record shape, correlation with fixed Ubisoft installation registry keys, no duplicate cross-store card, correct Epic handoff URI, removal after files disappear, path/drive/symlink rejection, ignored arbitrary metadata commands, scoped D3D11/D3D9 combination, and exchange-code line redaction. Three website tests verify published/uploaded-DMG-only counting, excluded drafts and non-DMG assets, a real zero, rejection of malformed counts, and the aggregate output boundary. A real authenticated GitHub API read succeeded; no credentials were emitted to the website.

Local metadata confirmed Brawlhalla was installed by Ubisoft Connect through Epic. Epic stored its AppName/Namespace/CatalogID/GameID in `ThirPartyManagedApps`, while Ubisoft stored its install directory in the fixed registry install roots. The new merged discovery returns one Epic Brawlhalla card with local artwork. The user confirmed the card appeared, then clarified that Play still opened the launcher without a game window. The user subsequently confirmed Brawlhalla works when opened from Epic’s own Library, while crossedover’s Play request still needs verification. The game’s native window controls and a short match/audio check remain pending. No universal FPS or game compatibility guarantee is made.

The installed x64 AIR executable was statically inventoried with REA’s PE resource parser (SHA-256 `525f7a595edf10509bf5d574f1f874bf0c9b20d97de11c3bd6df54e4dd7d7282`). Its application descriptor declares a visible resizable standard window and direct rendering. Prior game overlay metadata identified Direct3D 9 initialization; Epic’s current launcher needs D3D11. This motivated the combined rendering environment. No runtime/game executable bytes or account state were patched.

Xbox/Bedrock research is recorded in XBOX_AND_BEDROCK.md. Local Xbox/PC Game Pass/Bedrock installation is not implemented by this runtime. Settings provides an explicit official Xbox Cloud browser shortcut, with streaming and eligibility limits. The existing experimental WineGDK/Bedrock project is evidence of a separate possible implementation, not tested crossedover support. It is not bundled.

Further launch investigation found that normal Epic startup followed by the official in-client launch produced a real Brawlhalla process with native `d3d9.dll`, Wine Vulkan, and the runtime’s MoltenVK loaded. This establishes the rendering path and process startup, not visible gameplay. Launcher D3D9 choices are now scoped in AppDefaults, with the environment leaving D3D9 unspecified so its executable-specific setting can take effect. Wine’s source explicitly prioritizes environment overrides over per-app overrides. An isolated owned child passed both D3D11 and D3D9 readback under this policy. Cold Epic card launches prime the normal client UI before submitting the game URI; real card-launch and match confirmation remain pending.

The cold-client owned fixture exposed a Foundation Pipe reuse exception between normal launcher startup and URI submission. Giving the primer separate null output handles fixed that failure; a dedicated regression and the owned cold-client D3D11/D3D9 handoff fixture passed. Brawlhalla now receives executable-specific Mac Driver settings for native fullscreen, movable windows, and uncaptured desktop shortcuts. These settings do not force a caption onto a game’s own borderless fullscreen window; its saved Windowed display mode and native controls still require user confirmation. No live game preference file was rewritten.

The user confirmed Windowed mode still showed no traffic lights. The new runtime adds a default-off `ForceWindowControls` Mac Driver option, enabled only for Brawlhalla, that gives eligible main windows native title/close/minimize/fullscreen controls while excluding helpers, dialogs, shaped/layered surfaces, and inactive tools. It is a candidate until the rebuilt runtime is selected and the user checks the window. Inspection of the installed URL registration also found that `uplay:` uses `UbisoftConnect.exe`, rather than the internal `upc.exe`. Completed Ubisoft partner cards now retain Epic identity but launch through that validated bootstrapper/game ID. Initial account linking stays in Epic. The actual card route still requires a fresh user check of the updated build.

The candidate source runtime is `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-openal1.25.2-365546fb94`. The v1.3.0 packaged supervisor/runtime passed the expanded owned fixture: a 640×480 captionless D3D9 probe under Brawlhalla’s window policy, D3D11 Metal readback, cold Epic URI submission, Epic partner discovery and dispatch through a stand-in `UbisoftConnect.exe`, management routes, and completed-uninstall discovery. No accounts or real game binaries were used, and the isolated fixture created no automatic backups. The app’s strict signature and DMG checksum checks passed. Actual card launch and native control behavior remain pending a live environment switch and user confirmation.

The candidate also passed the full isolated runtime integration: 32/64-bit execution, Legacy and Performance Direct3D 9 readbacks/texture checks, Metal Direct3D 11 readbacks, x87 checks, OpenAL playback clock, process observation, and an explicit manual backup/restore round trip. All 18 integration checks passed. Results were retained under `.cache/v1.3/graphics-checks`, and the owned test prefix/backups were removed afterward. The candidate was imported without changing the live environment selection.


## v1.3.0 launch status and Stop

All **66 Swift tests in 11 suites passed**. New coverage checks stopping while a preparation lock is held, invalidating queued Steam/imported-app workers, preserving stopped runs against late replies, keeping other environments' sessions unchanged, and allowing a fresh launch after a stop. The release build passed.

The packaged supervisor/runtime passed `scripts/windows-app-integration.py --app dist/crossedover.app` in a fresh owned prefix. Both x86/x64 import probes passed sidecar reads, registry writes, hidden window creation, running/exited persistence, duplicate rejection, and launch after source removal. The extended check stopped a real Wine run, confirmed its stopped state survived the worker's final reply, and successfully relaunched afterward. No Steam installation or account was used; no automatic backups were created, and the test prefix was removed. Results are retained locally in `.cache/v1.3/launch-stop-integration.log`. This does not replace interactive verification of a real game's launch/window behavior.

App-owned previews checked the bottom launch bar at 1100×760 and the minimum 840×620 window size, including preparing, waiting, and closing states and visibility on Settings. The bar uses an indeterminate indicator, not an estimated percentage. The native Stop click was not automated against the user's live environment; that environment and its selected runtime were left unchanged.
