# Validation record

## CS2 sharper resolution and presentation timing confirmed — October 19, 2026

The owner later reports recurring frame drops **throughout matches**, despite
the earlier satisfactory response, and requests higher resolution while keeping
VAC working. Stable 60 FPS is therefore not established. While CS2 was closed,
allowlisted video fields confirmed 1280×720, low scene detail, no MSAA/FSR/VSync.
The old recipe also forced `-w 1280 -h 720` on every launch, contradicting the
promise to preserve later in-game resolution choices. Both connected displays
report 120 Hz. Memory/thermal snapshots obtained while the game was closed do
not diagnose its match-time bottleneck.

The candidate removes those resolution arguments and upgrades the old 720p preset
once to 1600×900, preserving higher/custom dimensions and later choices. A small
settings recovery copy is retained. The game keeps its 60 FPS work cap. Metal
profiles pass an owned DXMT configuration file whose `[cs2.exe]` section requests
`d3d11.preferredMaxFrameRate = 60`, following the pinned upstream implementation.
This schedules presentation; it does not prove that frames finish within budget.
Other executables do not receive that section's configuration. Normal Steam
launch/overlay policy, runtime binaries, official game files, mouse/window
controls and the restored library remain unchanged.

**92 tests in 16 suites passed**, followed by four focused CS2 checks. Coverage
checks scoped configuration, preserved later resolution choices, unchanged Steam
registry bytes during video preparation, no insecure/third-party launch flags,
and removal of the old overlay-disable entries. Release compilation and strict
deep signature verification of the new local preview passed.

An owned, bounded D3D11 fixture ran in a disposable prefix with an APFS runtime
clone, then removed its prefix/runtime. An observable adapter-description label
in that fixture verifies that executable-specific DXMT sections apply only to
the matching process. The label is never written into the real CS2 policy.
An initial assumption that CPU-side `Present` return intervals measure scanout
was rejected: presentation is asynchronous. Fixture loop timings are retained
as **CPU-loop statistics only**, not game or displayed FPS. The game work cap
remains 60 instead of raising it to spend more render work.

With no Steam/game process active and Minecraft's idle lock acquired, only the
old native GUI was replaced. CS2 was requested through Windows Steam; observation
confirms both CS2 and the normal Steam overlay helper. Saved dimensions now read
1600×900, with a framed window and MSAA/FSR/VSync still disabled. The production
presentation file contains only the scoped frame-rate option. No diagnostic HUD
was enabled in this security check. The owner then joined the requested online
test and confirmed **“Matchmaking works; sharper and smooth.”** This confirms
working matchmaking, improved perceived clarity and smooth play in the tested
configuration. No numerical FPS range or automated sustained frame-time trace
was supplied; a guaranteed 60 FPS minimum across matches, displays and hardware
is not established. The working configuration is retained without further
runtime, overlay or game-file changes.

Preview: `.cache/previews/crossedover-1.4.0-cs2-pacing-900p.app`.
Evidence: `.cache/cs2-frame-pacing/` and
`.cache/d3d11-pacing-0b3a8211-6f4d-41c2-bf80-1ecdd17e27d9/results.json`.
The owned runtime fixture is reproducible with
`scripts/d3d11-pacing-integration.py`; it is not a CS2 benchmark. No public push
or release has been performed.

After recording the owner result, release consistency checks, website generation,
all three website tests, the release resource rebuild and whitespace checks
passed. Public download links remain on v1.3.1; this working v1.4.0 configuration
is retained locally without interrupting the running game.

## Confirmed CS2 correction and retained library recovery — October 19, 2026

After restoring normal Steam overlay handling, the owner reports **“everything
is working good now”** in response to the online-matchmaking repeat test. Window
buttons were explicitly confirmed in the preceding run; the latest response
confirms the corrected configuration is satisfactory, including online play.
This is owner testing, not an automated sustained minimum-FPS measurement.
The working CS2 environment remains
`E6AAFFD1-27B6-4323-85E8-05E08B9BA60C`, with the tuned preset and native window
policy intact. No game binaries or anti-cheat components were modified.

The owner then noticed Brawlhalla and TrackMania were missing. Promotion had
switched the whole default environment and excluded its retained predecessor
from discovery. The files were preserved, but the library should have kept
them accessible. The old environment was reconnected with an explicit default
selection for the new CS2 environment, without moving or copying any game files.

The GUI now discovers registered environments in preferred order, hides duplicate
store/game IDs in favor of that environment, and preserves each card's owning
environment. Launch, management, files/Documents, renderer recommendations,
runtime selection and process observation use the card's owner. Imported app
cards retain their environments. Steam opens in the default environment;
Epic/Ubisoft reuse the environment containing their launcher. Stop targets all
registered Windows environments, while uninstall checks each before removing
managed data. Manual backup and general Settings remain scoped to the default
environment and now describe that scope explicitly.

**91 tests in 16 suites passed.** Expanded retained-library coverage also passed
after adding a colliding Epic/Steam ID: the new CS2 copy wins, TrackMania/Epic
stay in the old environment, and uninstalling the preferred copy exposes the
retained copy without changing the default. Release compilation passed. Actual
discovery reports Brawlhalla and TrackMania in the preserved environment, one CS2
card in the new environment, and existing files for all three. The new local
preview passed strict deep signature verification; its owned SwiftUI render
was reviewed and shows all three cards with artwork, sizes and Play buttons.
No real game window was captured, and no Windows game/launcher was stopped for
this metadata/library correction. Minecraft's separate data was not moved.

Evidence: `.cache/cs2-performance/restored-library.json` and
`restored-library.png`. This validates restored discovery and routing; the two
older games have not been replayed after this GUI change. No push or public
release was performed.

The final local preview is
`.cache/previews/crossedover-1.4.0-library-verified.app`. Its release build and
strict deep signature check passed, along with version/link/offline-guide checks,
Pages generation and all three website tests. The final GUI was reopened without
stopping any Windows process. A metadata check confirms the new CS2 environment
is still preferred and Minecraft's installed game folder is intact.

## CS2 requested cache/signature repair trial — October 19, 2026

The owner requested a Proton prefix/shader-cache reset, Proton Experimental,
cleared preloads and forced reacquisition of game signature manifests. This
installation runs Windows Steam through Wine on macOS, not Linux Steam/Proton.
There is no `steamapps/compatdata/730` directory; the shared crossedover prefix
was preserved. Steam's `shadercache/730` has four empty subdirectories and no
files (zero cached bytes).
Neither `LD_PRELOAD` nor `DYLD_INSERT_LIBRARIES` is set in the launcher's parent
environment; `WineConfiguration` already removes the macOS injection variable
from its child environment. Linux shell launch syntax and Proton Experimental
were not applied to Windows Steam. Native DXMT shader caches were preserved.

With CS2 and Windows Steam both closed (observer reports only system services),
the environment lock protected a reversible move of exactly four files from
the game's `bin/win64`: `csgo.signatures`, `foreign.signatures`,
`system.signatures`, and `vpk.signatures`, totaling **23,134 bytes**. Steam was
opened and its normal verification requested. It downloaded fresh replacements
for all four; the new jobs ended at 22:12:47 local time with `No Error`, and the
game returned to Fully Installed. All four replacement SHA-256 hashes match
the original files exactly. This establishes their original bytes matched
Steam's replacements; it does not prove the game's signature-validation path
works under the runtime. Redundant temporary recovery copies were then removed,
retaining only the inventory/result metadata.

CS2 was requested again through the normal launch route, preserving the tested
60 FPS settings, audio, runtime and window/input policy. The owner retried and
confirmed **“VAC warning still appears.”** No shared-prefix reset, game binary
patch, preload hook, app rebuild, push or release was performed for this trial.

To test the underlying prefix-reset hypothesis safely, a separate disposable
root was prepared at `.cache/cs2-clean-prefix-a6fe12b20ca3`, with environment
`E6AAFFD1-27B6-4323-85E8-05E08B9BA60C`. It imports and verifies the same runtime
and selects the same dedicated Metal profile. The bootstrap stop operation was
scoped only to that new test prefix. A fresh official Windows Steam installer
was run; no original Steam credentials, account/config folders, registry state,
or per-user video settings were copied. The original shared environment and
Minecraft backend were not reset or replaced.

The installed game payload was cloned using APFS `clonefile`, with no full-copy
fallback: **3,194 files / 73,919,379,180 logical bytes**. Preflight rejects
symlinks/non-regular files. Cloned files have distinct identities and share disk
blocks until written; they are not hard links to the original game. Game
discovery/validation in fresh Steam and any resulting downloads still need to
complete. The new client was requested, and the owner reports **“steam is
updating.”** Microsoft/Steam authentication is not automated. Manual Steam
sign-in and the clean-prefix matchmaking comparison remain pending.

Follow-up: Steam's updater completed and the clean client's installation route
was requested explicitly. The clean prefix now has its own CS2 manifest with
`StateFlags=4`, build `25966348`, no pending download bytes, and an observed
`cs2.exe` process. This confirms installation and execution in the isolated
environment; an earlier warning report made before that manifest existed was
not sufficient to establish which installation ran. The owner now reports
**“new install is working lets use this from now on.”** VAC-secured matchmaking
success has been asked separately and is not yet confirmed.

The owner also reports missing macOS window controls in that fresh run. Its
allowlisted video settings show a framed window at 2560×1440, with no crossedover
native-window migration marker. The prior tested window/input policy has not
yet been applied through crossedover's normal launch route in this environment.
No settings were rewritten while the game was active.

A read-only promotion preflight passed: the permanent destination is unused,
source and destination are on the same filesystem, runtime manifests match,
and the prefix has no absolute symbolic links to repair. The prepared move uses
a rename rather than a game copy and retains the previous environment's files
and metadata. The move waited while process observation still found CS2 and
Windows Steam running; neither was terminated.

After the owner confirmed both apps closed, a second observation found only
Wine system services. The new prefix was renamed into permanent Application
Support storage at `Environments/E6AAFFD1-27B6-4323-85E8-05E08B9BA60C`. An explicit
SQLite transaction made it the sole active environment, retaining the prior
environment's metadata as `retiredEnvironment` and leaving its prefix and all
game/app records in place. No game files were copied or deleted, and no full
backup was created. The old environment's games are preserved but are not
installed in the newly selected environment; Minecraft's separate backend is
unchanged.

The owner reported lower FPS and missing traffic-light controls in the fresh
run. An allowlisted comparison found 2560×1440, 2× MSAA and higher shadows,
textures and particles, versus the previous 1280×720/low preset. Neither window
nor performance migration marker was present. The first normal crossedover
launch in permanent storage successfully applied both migrations and imported
the existing per-CS2 Mac Driver policy. Numeric settings and migration markers
now confirm framed 1280×720, MSAA/AO/FSR/VSync off, low scene detail and retained
dynamic shadows. The generated policy enables native fullscreen and cursor
tracking across window changes. A separate live `reg.exe query` exited 1 without
output, so it did not independently confirm the in-memory registry values.
The game process was subsequently observed from the new permanent environment.
The owner confirmed **the window buttons work**, with FPS reaching **60 but
dropping periodically**, and the VAC warning appearing again. They also
clarified that the clean environment had **successfully joined an online match
before** promotion and launch preparation. This is a regression comparison,
not evidence that all VAC matchmaking is incompatible with this runtime.

The first focused correction leaves Steam's official overlay handling at its
defaults for CS2. `GameWindowingPolicy` now deletes the two per-CS2 forced-disable
DLL entries while retaining every Mac Driver window/input setting; TrackMania's
separate optimization is unchanged. The three GameLibrary tests passed, including
the regression assertions, and release compilation succeeded. After the owner
quit all Windows apps, observation confirmed no game or Steam process before the
new launch applied the correction. A public-registry query using the same full
Wine environment as the launcher confirms native fullscreen/cursor tracking are
enabled and both overlay-disable entries are absent. The earlier empty query
result came from an incomplete diagnostic environment; the later query succeeded.

CS2 and Steam's overlay helper were observed after relaunch. A new local v1.4.0
preview passed strict deep code-signature verification and replaced only the
previous idle native GUI, so subsequent card launches use the corrected policy.
Preview: `.cache/previews/crossedover-1.4.0-cs2-steam-overlay-default.app`.
**Repeat online matchmaking and stable frame pacing remain unconfirmed.**
The forced overlay-disable setting is a hypothesis under test, not an established
cause or verified VAC repair. No game binaries or anti-cheat components changed.

Promotion/settings evidence is in `.cache/cs2-performance/promoted-settings.json`
and `new-vs-previous-settings.json`; the test root retains `promotion.json` and
updated status metadata. No push or public release was performed.

Evidence: `.cache/cs2-performance/signature-refresh-*.json`,
`cache-reset-inventory.json`, and the inventory directory referenced by
`signature-refresh-stash.txt`; the clean-root pointer is `clean-prefix-root.txt`.

## CS2 scene-cost preset and game renderer recommendations — October 19, 2026

The owner reports acceptable CS2 menu performance but poor match performance,
and requests a 60 FPS minimum on any monitor. No numeric match baseline was
provided. A universal minimum cannot be established from menu FPS or the
monitor's dimensions. The selected DXMT profile, 1280×720 saved dimensions,
disabled FSR/VSync and enabled MSync were confirmed before changing anything.

`CS2WindowSettings` now applies a separate one-time performance migration only
after the supervisor's existing stopped-game check: MSAA/CMAA and ambient
occlusion off; low textures, particles, shaders and shadow quality; performance
HDR. All dynamic shadows remain enabled. Only existing numeric settings are
changed; window/input/audio settings and subsequent user choices are retained.
Settings values follow the installed game's `settings_video.xml`. The normal
launch route applied the preset; the original settings copy is **1,033 bytes**,
not a full environment backup. The existing cursor-following runtime is kept.

Every discovered store game receives a renderer recommendation. Known Steam
recipes and Brawlhalla's existing Ubisoft executable policy take precedence;
other games use bounded normal/delay PE import hints. Unknown titles receive
a labeled starting point. Minecraft shows its separate DXMT configuration.
Recommendations appear in grid/list views with details; Steam application uses
the existing stopped-environment and supported-runtime guards. Discovery and
caching run outside the UI actor; no game code runs during API inspection.

- **90 Swift tests in 16 suites passed**, including 32/64-bit normal and delay
  imports, malformed/truncated images, resource-string false positives,
  unsupported DirectX 12, store ID collisions, declared executable precedence,
  cache refresh and escaping manifest paths. Performance migration tests check
  original settings recovery and preservation of later resolution/quality choices.
- Release compilation and fresh v1.4.0/build 26 preview packaging passed. The
  final app passed strict deep code-signature verification and was opened after
  checking no CS2/Bedrock session was active; only the previous idle GUI closed.
- Owned SwiftUI grid/list renders were visually reviewed. The installed
  Brawlhalla/CS2/TrackMania and Minecraft preview cards show recommendations
  without clipping. README/technical/setup/runtime notes and screenshots updated.
  Pages build, release/link/image/offline-guide checks and **3 website tests** pass.
- CS2's process was observed after requesting launch. An allowlisted config
  check confirms the intended low settings, 1280×720 and FSR disabled. The owner
  attempted online matchmaking and supplied a screenshot of a **Valve Anti-Cheat
  missing/invalid file-signature warning**. No match FPS was obtained. The normal
  code path launches through Steam, without `-insecure`, direct executable launch
  or third-party-injection options. No local `d3d11.dll`/`dxgi.dll` replacements
  were found in the two game executable folders. These checks don't establish
  the signature error's cause. After the owner quit CS2, Steam file verification
  was requested through its normal flow. Its installation log recorded verifying
  activity from 21:37:10 to 21:39:14 local time, then returned to Fully Installed
  with no pending update. A fresh normal Steam launch was requested and CS2's
  process observed again. The owner supplied a second screenshot confirming the
  same warning, then confirmed it also occurs using Windows Steam's own Play
  button. This rules out the crossedover handoff alone as a sufficient cause.
  Allowlisted installation-job result parsing finds `No Error` for the two
  jobs ending at 21:39:13/21:39:14; no UI repair count is available. A read-only
  query reports Steam Client Service running (state 4), with both service and
  Win32 exit codes zero. This does not establish VAC compatibility. The owner
  then closed both apps normally; process observation found only Windows system
  services before a fresh Steam client was requested. Following that test, the
  owner reports **“60fps looks great”**, while the VAC warning remains. This
  confirms a good subjective result at the reported frame rate in that local
  run, not a measured minimum across monitors, maps or session lengths. No
  automated frame-time capture or numeric before/after baseline was obtained.
  The working preset, runtime, audio and window/input policy are retained.
  The owner subsequently confirmed Steam's saved Launch Options field is blank;
  crossedover's own recipe contains only window sizing and the frame cap. Saved
  flags therefore do not explain this run's warning. The observed failures are
  consistent with a runtime/VAC compatibility issue, but the exact rejected
  component has not been identified. Similar Windows-build failures under
  Proton are reported in [Valve's tracker](https://github.com/ValveSoftware/csgo-osx-linux/issues/4125);
  that Linux evidence does not establish this Mac's root cause. No verified
  correction for this runtime has been identified. CS2's source renderer-details note
  now distinguishes the confirmed local rendering result from blocked secure
  matchmaking. No launch flags, game binaries or runtime components were changed.
  **Local performance is owner-confirmed around 60 FPS in the tested run;
  VAC-secured matchmaking remains blocked after a fresh Steam session.**
  No game UI capture, input automation, driver replacement,
  remote push or public release was performed.

The follow-up changed only compatibility/help text. Release compilation copied
the updated recipe resource successfully; the CLI still recommends DirectX 10–11
and includes the matchmaking limitation. Pages build, release/link/offline-guide
checks and all three website tests passed. No additional preview bundle was
created or active app replaced for this text update; the note will be included
in the next packaged build. The prior 90-test core result remains applicable to
the unchanged implementation.

Evidence: `.cache/cs2-performance/`. Current preview:
`.cache/previews/crossedover-1.4.0-cs2-performance-verified.app`.

## Minecraft artwork and product scope — October 19, 2026

Minecraft's card and list row now read its official grass-block artwork from the
owner's installed `LargeLogo.png`, with smaller-logo fallbacks. Asset path
resolution and bounded thumbnail decoding run off UI layout. Installation and
playing status load the artwork; uninstall clears its path. No Minecraft art
asset is copied into the source or app bundle.

- Release compilation, fresh v1.4.0 preview packaging and strict deep signature
  verification passed. The updated app was opened after game/helper processes
  ended, preserving their data and the selected Windows runtime/profile.
- App-owned SwiftUI renders were visually reviewed in grid and list modes.
  Minecraft's full-color artwork, title and Play/options controls are visible.
  The website's new library image is 2200×1800 so all four cards fit; list view
  remains 2200×1520. No protected game windows were inspected.
- README, Markdown/HTML quickstarts, technical and hardware guides, and Pages
  copy describe Windows apps/games, Steam, Epic, Ubisoft handoffs and Minecraft.
  They distinguish local v1.4.0 Bedrock testing from the available v1.3.1 binary.
  The offline DMG guide keeps inline styles and no external image dependency.
- Pages built successfully; release checks passed versions, local links,
  fragments and image dimensions. All **3 existing website tests** passed.
  Local index, quickstart and updated images returned HTTP 200.
- Browser preview could not bootstrap because its installed runtime referenced
  a missing browser-service module; one reset/retry reproduced the failure.
  Website rendered-layout QA was not completed. No browser fallback or tool
  configuration change was attempted. The owned preview server was stopped.

Evidence: `.cache/artwork-scope/` and refreshed `website/assets/library.png` /
`list.png`. Changes remain local; the GitHub Pages deployment was not triggered.

## CS2 native move/resize input bounds — October 19, 2026

The owner reports CS2 opened and worked well, but after moving the running game
from the built-in display to a larger monitor, the pointer could move everywhere
while clicks missed buttons in much of the game. This report establishes the
trigger; it does not identify a confirmed graphics/DPI root cause.

An owned native move/resize fixture reproduced stale full-client `ClipCursor`
bounds with the original driver. The new default-off
`CursorClippingFollowsWindow` option is enabled only for CS2 by crossedover's
launch policy. It updates a still-unchanged full-client capture after native
frame handling. It keeps per-monitor coordinate context and preserves explicit
subrectangles, point capture, released/replaced capture and foreground changes.
No display resolution, global DPI or user CS2 video settings are reset.

- Baseline owned 64-bit fixture: move/grow/shrink retain the stale old clip.
- Patched owned 64-bit and 32-bit fixtures: full-client clips follow native
  move/grow/shrink. All five explicit/released/replaced negative cases pass.
- Disabled option: all eight cases preserve the original behavior.
- Native window-controls regression: all eight eligible/negative cases pass.
- Swift: **84 tests in 15 suites passed**, including CS2-only option scoping.
  Repeat patch-build regression passed; release compilation passed.
- The source runtime rebuilt as
  `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-openal1.25.2-8d2b4c4432`.
  The v1.4.0/build 26 preview packaged and passed strict deep code-signature
  verification. The stopped-environment guard allowed runtime selection; the
  existing Metal profile was preserved and no automatic backup was created.
  The new app is open and CS2 was requested through the normal launch route;
  its generated per-game policy enables capture following while retaining
  shooter cursor capture. The CS2 game process was observed. The owner repeated
  the move from the built-in display to the larger monitor and confirmed
  **“Clicks line up across the whole window.”**
- The final driver patch passes reverse checks alongside the earlier window
  controls patch. This is synthetic move/resize evidence, not a test with two
  physical monitors. The subsequent owner confirmation above establishes actual
  CS2 secondary-display menu clicking. Aiming, all display/DPI arrangements and
  other games were not separately revalidated; no public release or push occurred.

Evidence: `.cache/input-bounds/`,
`.cache/input-bounds-a829b5f1-c4e8-411b-a6f0-9a6412ae74cb` (baseline),
`.cache/input-bounds-6aaa8ae4-6cc8-4f7a-9239-b06e05e33ddd` (64-bit),
`.cache/input-bounds-1c482758-f44c-424c-a330-4b6933b3f2c3` (32-bit),
`.cache/input-bounds-bf76a43a-7104-4bdb-a40e-99b5b25457c1` (disabled), and
`.cache/window-controls-e4ec794e-e4c4-438d-a23b-ffc7b057cbef` (controls).
Each fixture removed only its own generated runtime and prefix copies.

## Minecraft signed-package installer — October 19, 2026

Development remains **v1.4.0/build 26**, with no public push/release.

- Added a macOS-native RSA-PSS/SHA-256 verifier with two pinned Microsoft public
  verification keys. Provenance/fingerprints are recorded under
  `runtime/bedrock/verification/`; no private keys or GDK executables are bundled.
- The real owner's catalog package header passed signature verification with a
  4 KiB signed-header envelope. Its fixed layout has a skipped mutable section;
  pinned msixvc source confirms those bytes are not consumed by its parser.
- Complete package verification anchors every parent/leaf hash-tree page to
  the signed root, then checks all metadata/game data pages before parsing or
  extraction. Tests cover encrypted/plaintext entries, multiple levels, mutable
  padding, corrupted headers/tree/metadata/first and last data pages, unexpected
  size and unsupported layouts. The owned fixture key is rejected in production.
- Helper: **18 tests passed**, 2 explicit live/Keychain fixtures ignored.
  Python onboarding: **16 tests passed**, including reviewed byte progress.
  Swift: **84 tests in 15 suites passed**; the subsequent Bedrock-only run
  passed **8 tests**, adding rejection of the obsolete backend policy.
- Release build, fresh v1.4.0 preview packaging, exact backend inventory and
  strict deep code-signature verification passed. The pipeline and app require
  the matching `signed-xvd-v1` policy. The obsolete staging copy was removed.
- The owner approved the packaged helper's Keychain prompt. A live installation
  through the normal Core service downloaded the 2,069,975,040-byte Microsoft
  package. Complete signature/tree/data verification and the Microsoft content
  license succeeded, followed by extraction of all **12,177 files**, prefix
  preparation and observed `playing` status.
- The owner confirmed **Minecraft's menu**, then **playable local-world controls
  and sound, save and normal quit**. The worker exited cleanly with `ready`;
  an independent offline check reports the installed game. There are no leftover
  complete temporary archives. Retained metadata is **14,614,528 bytes**; the
  installed game is approximately **2.13 GiB**. No automatic backup was created.
- The new native v1.4.0 app was opened only after the session/helper ended.
  Card-based repeat launch, saved-world reopen and native window behavior are
  being checked. Only allowlisted private-log status categories were inspected.

Evidence: `.cache/v1.4/verified-download-build.log`,
`.cache/v1.4/signed-download-swift-tests.log`,
`.cache/v1.4/signed-download-policy-tests.log`,
`.cache/v1.4/signed-download-release-build.log`,
`.cache/v1.4/signed-download-package.log`, and
`.cache/v1.4/verified-install-status.log` (reviewed Core status only).

## Brawlhalla native window controls — October 19, 2026

The owner confirms Brawlhalla opens reliably, but still has no traffic-light
buttons. An owned Win32 fixture reproduced two gaps in the old driver: layered
and region-shaped windows received no native frame, and a desktop-sized popup
had buttons above the display work area. This is fixture evidence, not a trace
or inspection of Brawlhalla's actual window styles.

The new default-off, per-game `ForceWindowControls` follow-up keeps controls
around eligible shaped/layered main windows without removing their content
mask or alpha. Disabled main windows retain a title bar with disabled buttons;
small helpers, tools, inactive windows and owned dialogs keep their old styles.
Outside native fullscreen, forced frames fit the screen work area. AppKit
fullscreen and its transitions bypass this desktop constraint.

- The actual AppKit close/minimize/zoom buttons, fullscreen eligibility and
  onscreen caption checks passed for **32-bit and 64-bit** owned fixtures.
  Negative helper/inactive/disabled cases also passed. The opt-in diagnostic
  reads only its receiving owned fixture window, with both an explicit test
  environment flag and fixture title; no game windows were inspected.
- The tracked patch reproduces the compiled source exactly and passes forward
  and reverse application checks. The source runtime rebuilt successfully as
  `wine-11.0-cx26.3.0-dxmt0.80-d9vk-mvk1.4.2-x87-openal1.25.2-ae61c2d959`.
- The owned Epic regression passed queued partner launches/cancellation,
  management and uninstall discovery, plus D3D11 Metal and scoped D3D9 readback.
  The v1.4.0/build 26 preview with this runtime passed strict deep signing checks.
- The actual environment passed its stopped-environment guard and selected
  the new runtime with Performance preserved. No automatic backup was created.
  A fresh Epic launch was requested. The owner then confirmed **“Buttons
  visible and working”**, in response to the check covering the red/yellow/green
  controls, minimize and fullscreen. Pointer alignment was not separately
  checked during this confirmation.

Evidence: `.cache/window-controls/`, `.cache/window-controls-14a89067-c227-46a7-9bc0-3ffc6fcf83f6/`
(baseline), `.cache/window-controls-89738c0f-24cc-476e-b248-ce26d84f228a/`
(64-bit), and `.cache/window-controls-a43922b2-9041-4983-83e9-ebe84df00784/`
(32-bit). Disposable fixture runtime/prefix copies were removed; user games and
accounts were preserved. No release or push occurred.

## v1.4.0 version and installed Minecraft library entry — October 19, 2026

Development metadata now uses **1.4.0/build 26**, the Minecraft release. Existing
public download URLs and historical screenshot labels retain their actual
v1.3.1 version; no v1.4.0 artifact has been published.

Minecraft's grid card/list row, Play and launcher options, search, store filter
and library counts are wired to verified installation status. Library refresh
and session completion now repeat the offline status check, reusing the
verified backend to avoid hashing the full runtime on every refresh. Failed
downloads do not create an installed card. Real package installation/gameplay
remain blocked as recorded below; presentation fixtures are not game tests.

All **84 Swift tests in 15 suites** passed, as did the optimized build and
offline release checks. App-owned renders with an isolated data root verified
the installed Minecraft card and list row, search result/count, Play/options,
and v1.4.0 sidebar label. The packaged preview reports **1.4.0/build 26**, passes
strict deep signature verification, and returns `new` from its offline worker
against the actual data root (Minecraft remains uninstalled). Evidence:
`.cache/v1.4/`. No account prompt or game installation was triggered by these
presentation/status checks.

## Minecraft Bedrock preview and Epic partner queue — October 19, 2026

**Development work for v1.4; not released or gameplay-verified.** The local
Minecraft launcher panel, Games grid/list entry after verified installation,
independent session service, account sign-out, cancellation, game-files access
and world-preserving uninstall are implemented. Bedrock uses its own data root
and WineGDK server, separate from Steam/Epic. Uninstall holds the onboarding
lock; an active worker keeps the native app alive when its window closes.

- All **84 Swift tests in 15 suites** passed, followed by a release build.
  Bedrock coverage includes exact backend file/symlink inventory and digest
  validation, root containment, offline status, reviewed status text, invalid
  messages, progress arriving before process exit, duplicate-session rejection,
  cancellation, terminal-state failures, and held uninstall locks.
- Built the pinned Bedrock for Mac integration, WineGDK and Xodus helper locally
  with two compiler jobs. The account-free helper suite passed **13 tests**
  (two live tests remained ignored). The patched onboarding suite passed
  **16 tests**, including the one-helper setup/play lifecycle and preserved reviewed account error codes.
- The helper rejects HTTP transport and insecure redirects. The explicit
  account-free Rust test successfully fetched the public HTTPS routing file.
  Actual licensed package requests to that server returned **404**; a bounded
  original-virtual-host experiment returned **503**. Those hostname-rewriting
  experiments were removed. The helper now requires a catalog-supplied HTTPS
  origin and considers both foreground and background candidates. Public asset
  origin checks failed TLS verification; no certificate exception was added.
- Staged a 375 MiB backend with 1,048 original regular files and 16 symlinks.
  Packaging preserves third-party notices, signs nested Python/runtime code,
  inventories newly generated signing metadata, and signs the outer app. A
  separate preview app passed `codesign --verify --deep --strict`. The signed
  Wine/DXMT overlay hashes still match; the signed worker returned a valid
  account-free `new` installation status through Core.
- App-owned SwiftUI launcher renders were checked for layout. These are static
  renders, not protected-window inspection or interaction tests.
- A live setup used the same Core service and signed worker with the user's
  normal data root. The owner confirmed **successful Microsoft sign-in** and
  approved the retry's Keychain prompt. The saved account reached the Minecraft
  purchase/package lookup. Installation then failed with reviewed
  `package_connection` status; only allowlisted error/status categories were
  inspected. The sign-in is preserved. **No game installed or launched.**
  Gameplay, audio/input, worlds, fullscreen/window controls, repeat launch and
  clean-Mac validation remain pending.

The included v1.3.1 download/version links remain unchanged. No public Minecraft
runtime or v1.4 release has been pushed. Build/readiness details are in
[the backend guide](../runtime/bedrock/README.md). Local evidence is in
`.cache/v1.3/bedrock-*`; runtime/source output stays ignored.

Epic's bundled online-services installer initially failed because the ordinary
game environment disabled its required .NET bridge. The isolated integration
installed verified Wine Mono 10.4.1 and Epic's real bundled helper 5.8.1, checked
the live 32-bit registry version, and repeated repair without replacing Mono or
creating full-environment backups. The owner quit Windows clients normally;
the same repair then completed in the user's environment. Epic subsequently
reported its minimum helper version satisfied and its previous startup
assertion disappeared. This prerequisite repair alone did not start Brawlhalla.

Static inspection then identified Epic's public pending-link serialization:
Unix seconds, `|`, and the validated game URI in HKCU's `PendingUri` value. A
normal `-forwarduri` launch consumed this value in an owned account-free client.
A corresponding user-environment request subsequently started Ubisoft's
launcher and **Brawlhalla.exe** without reusing or inspecting exchange codes.
The owner subsequently confirmed **Brawlhalla’s game window opened** from this request. Native red/yellow/green buttons and a short match/audio check remain unconfirmed.

Partner cards now queue the validated public link before acknowledging Play,
start Epic through that queued-link mode, and preserve Epic's normal entitlement
and Ubisoft authentication flow. Stop compares the app's receipt and clears
only its unconsumed value before Wine exits. A real Wine fixture caught CRLF
parsing that initially left cancelled values behind; the parser now handles
Windows line endings and has regression coverage. Other sources' newer links
are preserved. The owned integration passed discovery, generic shell handoff,
partner queue, D3D9/D3D11 readback, management routes, uninstall discovery, and
cancelled-queue cleanup. Its stand-in does **not** test official account auth.
Evidence: `.cache/v1.3/epic-queued-handoff.log`,
`.cache/release-preview/epic-results.json`, and the filtered prerequisite/queue
results in `.cache/v1.3/`. The unused 4.1 GiB account-free Epic environment was
stopped and removed; the user's clients and games were preserved.

## Installed-size reporting — October 19, 2026

All 70 tests in 12 suites passed after adding the installed-size fallback. Regression coverage includes Epic/Ubisoft partner discovery, nested and hidden files, symbolic links and loops, cached refreshes, explicit recount, and expiry. The installed Brawlhalla folder measured **1,601,448,683 bytes** across **7,794 regular files**, matching an independent Python metadata walk. An app-owned SwiftUI preview showed **1.6 GB** on its card during the Opening state. This verifies size reporting, not the still-pending Brawlhalla card-launch or native-window-controls behavior. Evidence is local in `.cache/brawlhalla-size-*`.

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


## v1.3.1 Brawlhalla candidate

The user confirmed that Brawlhalla still launched only from Epic itself, not from crossedover’s bare Ubisoft-link route, with Epic either open or closed. Native title-bar controls were also still absent. Inspection of current environment metadata found it was still selecting the earlier `4c7facecf6` runtime. The environment was migrated through the stopped-environment guard to the bundled `365546fb94` candidate, preserving the Performance profile and installed files. No full automatic backup was created.

Epic partner cards now dispatch their composite game URI to Epic, preserving the owning client’s authorization and partner handoff. Cold startup preparation also applies to partner cards; launcher working directories now match their executable directories. All **66 Swift tests in 11 suites passed**, including cold/warm partner dispatch and working-directory checks. The release build passed. Real Brawlhalla launch, window controls, and warm/cold behavior remain pending user confirmation of the v1.3.1 app. No push or release is authorized before that confirmation.

The packaged v1.3.1 supervisor/runtime passed the updated isolated Epic fixture: cold-client preparation, composite launch URI dispatch for normal and Ubisoft-managed Epic cards, D3D11 Metal and scoped D3D9 readbacks, management routes, and completed-uninstall discovery. No accounts or real game binaries were used. The owned prefix was removed; no automatic full backups were created. The app signature, v1.3.1/build 25 metadata, active/bundled runtime match, and DMG checksum verification passed. Evidence is retained locally in `.cache/v1.3/brawlhalla-1.3.1-epic-integration.log`. The actual Brawlhalla card and native controls remain unconfirmed.


## v1.3.1 universal graphics controls

The selector now describes API coverage instead of individual games: DirectX 9–11, DirectX 10–11, DirectX 9, and OpenGL fallback. Old raw values retain their behavior and the live environment’s `performance` selection was preserved (now displayed as DirectX 9). The new `combined` choice is available only when both D9VK/DXVK and DXMT runtime components are advertised. It combines native D3D9 with the DXMT overlay, retains OpenGL for older fallback components, and leaves the optional x87 helper specific to the dedicated DirectX 9 mode. Epic/Ubisoft retain their managed renderer policy. No DirectX 12 mode was added.

All **67 Swift tests in 11 suites passed**. Capability gating, unsupported metadata changes, backend environment composition, old-value decoding, and combined serialization are covered. The release build passed. The expanded owned runtime integration passed **21 checks**, including the existing Legacy/Performance/Metal execution and graphics tests, combined 32/64-bit Direct3D 9 and Direct3D 11 readbacks, texture/mapped-copy checks, audio, observation, and manual backup/restore with the combined profile. A focused follow-up reran combined execution/graphics after preserving the OpenGL fallback and passed. Evidence is retained locally in `.cache/v1.3/universal-graphics-evidence`; the owned test prefix and its manual backup were stopped and removed. The user's environment was not used for these checks.

App-owned renders verified the revised descriptions at standard and compact widths. The full-backend selector was not exercised through UI automation. These synthetic graphics checks do not certify arbitrary games or establish frame rates; Brawlhalla’s real launch/window confirmation remains pending.


## v1.3.1 follow-up: request receipts and protocol activation

The user reported that the candidate still opened Epic and then showed an error without opening Brawlhalla, while Epic’s own Play continued to work in the same run. The latest saved game session timed out without a matching process; its separate Activity operation incorrectly remained Completed because the supervisor had accepted the request. That receipt is now Request sent. New game sessions share the launch operation UUID and update both records in one transaction as requested, running, failed, exited, or stopped. Delayed request receipts cannot overwrite newer session observations, and closed sessions reject late active updates. Old completed launch receipts display as Request sent, without retroactively claiming game success.

The next candidate uses Windows protocol activation (`start.exe` / ShellExecute) and Epic’s registered handler for game/library URIs, rather than passing a URI directly to a second launcher executable. Normal Open Epic still starts its visible client directly. This follows Epic’s published protocol activation guide. A launcher diagnostic also contained a service-version warning, but it appeared in earlier runs too; it has not been established as the cause and no service/account settings were changed. Real Brawlhalla validation remains required; no push or release has occurred.

All **68 Swift tests passed**, including request/observation ordering, failed-launch status, terminal-session protection, historical receipt labels, and cold/warm shell dispatch.

The revised owned Epic fixture registered a real Windows protocol handler for its launcher stand-in. Shell activation delivered normal and partner game URLs, completed D3D11 Metal and scoped D3D9 readbacks, and passed management/uninstall discovery checks. The fixture had no accounts or real games, created no automatic full backups, and removed its test data. Evidence is retained in `.cache/v1.3/epic-shell-integration.log`. App-owned Activity rendering confirmed historical game receipts no longer display Completed; the app signature and rebuilt DMG verified. The real-game warm-start retry remains pending.
