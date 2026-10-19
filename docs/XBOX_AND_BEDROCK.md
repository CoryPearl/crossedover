# Xbox and Minecraft Bedrock assessment

## v1.4.0 investigation — October 19, 2026

The requested v1.4.0 feature is local **Minecraft for Windows (Bedrock)** support, with a Minecraft entry in Game Launchers. A native launcher panel, separate backend/session service, verified build pipeline and cancellation controls are now implemented in development. Owned-account download and gameplay are not verified or released. The existing Steam/Epic environment is independent. Public version numbers/downloads remain v1.3.1 until the new flow has been tested.

### Current implementation

The Minecraft panel is available from **Game Launchers → Minecraft Bedrock…** and Settings. An absent or invalid backend leaves Install & Play disabled with an explanation. With a verified backend, the native app runs its worker, renders bounded reviewed status messages, and allows cancelling setup or stopping the dedicated Minecraft session. The worker retains one account helper through download, prefix preparation and gameplay. A process check precedes Running status; a successful command exit alone is insufficient.

The backend is built from the pinned source below plus crossedover's tracked integration patch. Game transport is **HTTPS only**, including redirects; foreground and background catalog candidates are checked without changing their hosts. Microsoft sign-in succeeded in the local test and its saved account was reused. The licensed package download failed: the catalog's HTTP origins did not yield a usable verified HTTPS route, and attempted Microsoft HTTPS mirror routes returned 404/503. Those mirror experiments were removed. Minecraft has **not** installed or launched in crossedover. The missing secure download path remains a release blocker.

The Keychain service is **crossedover Minecraft**; the data root is `CrossedOver/Bedrock`, including its game and separate Wine prefix/worlds. Steam/Epic do not share this server, account, renderer or Stop action. App uninstall checks the Bedrock session lock, and the app stays alive when its window closes during a session. See [build instructions, file paths and outstanding release checks](../runtime/bedrock/README.md). No game or Microsoft account is included in the source or backend.

### What was checked

- Microsoft lists Windows 10/11 as the Xbox PC app's supported operating systems. Its packaged games use Gaming Runtime Services and the PC Bootstrapper. Installing a conventional launcher `.exe` in the existing Wine prefix does not implement those services. [Xbox PC app requirements](https://www.xbox.com/en-us/apps/xbox-app-on-pc), [PC Bootstrapper](https://learn.microsoft.com/en-us/gaming/gdk/docs/gdk-dev/pc-dev/overviews/gr-pc-bootstrapper).
- Reviewed Bedrock for Mac at commit `99fc9aa7d79b34aaee25a447b964e5d8235a2cec`. Its local Bedrock route combines WineGDK, DXMT, Xodus, an owning Microsoft account, and a separate prefix. Upstream reports local gameplay; that is not a crossedover test. It does not run the Windows Xbox app or establish compatibility with its other games. [Pinned source](https://github.com/1JRobertson/bedrock-mac/tree/99fc9aa7d79b34aaee25a447b964e5d8235a2cec), [upstream release evidence](https://github.com/1JRobertson/bedrock-mac/blob/99fc9aa7d79b34aaee25a447b964e5d8235a2cec/docs/RELEASE.md).
- The pinned downloader permits HTTP from `assets1.xboxlive.com` and `assets2.xboxlive.com`. Upstream explicitly records incomplete integrity authentication for some unencrypted package sections as a binary-release blocker. Independent HTTPS HEAD requests to both hosts' public `/Z/routing/up.txt` endpoint failed certificate hostname verification. Merely replacing `http` with `https` does not fix this path. No certificate checks were disabled. These initial account-free checks preceded the owned-account test recorded above. [Pinned security notes](https://github.com/1JRobertson/bedrock-mac/blob/99fc9aa7d79b34aaee25a447b964e5d8235a2cec/SECURITY.md).
- Its current assembled runtime requires macOS 26 and Rosetta, despite a lower Swift deployment target. It has no public notarized binary. The portable dependency redistribution inventory and clean-machine tests also remain open upstream. Reusing it therefore requires a separate, reviewed build rather than copying binaries into crossedover's existing runtime.

### Proposed local Bedrock implementation

The user selected this Bedrock-specific route and a Minecraft launcher entry. It cannot be presented as general Xbox app support.

1. Pin the runtime, helper, source patches, licenses, and matching build inputs. Resolve package integrity for every downloaded section, or use an authenticated transport with normal certificate verification. Fail closed when neither is available; do not publish the current HTTP downloader as a working installer.
2. Keep a dedicated Bedrock runtime and prefix under crossedover's managed data root. Preserve the existing Steam/Epic prefix, installations, and saved graphics profile. Establish dedicated world-storage/export paths before exposing uninstall.
3. Add an **Xbox / Minecraft** entry to Game Launchers with clear local availability. Use a Microsoft sign-in window and a stable Keychain-backed helper, preserve server-issued ownership checks, and avoid credentials in crossedover's database, logs, backups, or diagnostics. Do not label a browser/cloud shortcut as a local installation.
4. Own one helper through setup and play. Forward only reviewed structured status, support cancellation and retry, and stop only the processes belonging to this backend. Keep Steam/Epic sessions independent. Do not show Running solely because a request was sent.
5. Discover a Minecraft card only after a validated installation. Wire Play, observed lifecycle, files/world export, sign-out, and confirmed uninstall. Keep world removal explicit and preserve saves on repair/update.
6. Test offline boundaries first: damaged/incomplete installation, containment, account-free status checks, download rejection, cancellation, retry, and terminal launch states. Then use the owner's account to test download, actual game window, controls/audio, world save/reopen, fullscreen/window controls, and normal quit. Multiplayer and updates require their own evidence.

The alternative for the real Xbox client is a Windows environment rather than the current Wine runtime. Microsoft now supports its client on Windows 11 Arm, but this does not establish VM compatibility for every title, driver, or anti-cheat system. [Microsoft's Windows Arm announcement](https://blogs.windows.com/windowsexperience/2026/01/21/play-more-xbox-app-is-now-available-on-arm-based-windows-11-pcs/).

Runtime source and build output stay in ignored development directories. Version numbers and public download links have not been changed to advertise unfinished v1.4.0 support. The initial feasibility checks did not acquire a game or account; any later live test is recorded separately in the validation log.

## Included runtime and existing cloud shortcut

The included Wine 11.0-cx26.3.0 runtime does not implement a supported Windows Xbox client, Microsoft Store installation/licensing, or the additional Bedrock GDK account bridge. Local Xbox/PC Game Pass downloads and Bedrock are therefore not exposed as working installers. We do not promise all games from any store.

Microsoft documents that packaged PC games invoke the PC Bootstrapper through Gaming Runtime Services, which has its own Windows runtime dependency. This differs from downloading Steam or Epic's conventional Windows launchers. [Microsoft PC Bootstrapper documentation](https://learn.microsoft.com/en-us/gaming/gdk/docs/gdk-dev/pc-dev/overviews/gr-pc-bootstrapper)

A specific Bedrock path is plausible: WineGDK implements selected GDK/WinRT components, and Bedrock for Mac publishes an experimental Apple silicon implementation using WineGDK, DXMT, and Xodus. Its current source describes owned-account download, a separate credential helper, runtime patches, and isolated game/world storage. The project's evidence and open issues belong to its tested build, not crossedover. This is not equivalent to running the Xbox app or every Game Pass game. [WineGDK source](https://github.com/Weather-OS/WineGDK), [Bedrock for Mac](https://github.com/1JRobertson/bedrock-mac), [its release evidence](https://github.com/1JRobertson/bedrock-mac/blob/main/docs/RELEASE.md)

A future local Bedrock integration needs a separate pinned runtime and prefix, a reviewed Microsoft sign-in/licensed download flow, protected account storage, cancellation and recovery, contained world saves, and actual launch/input/audio/multiplayer validation on supported Macs. It must preserve the existing Steam/Epic environment and never treat copied game files as account ownership. No components of this experimental port are bundled in v1.3.1.

Settings offers an explicit browser link to Xbox Cloud Gaming. Microsoft supports browser streaming on macOS for eligible cloud games, accounts, regions, and plans. This is streaming, creates no local crossedover installation/card, and does not establish Minecraft's availability. [Microsoft cloud gaming guide](https://news.xbox.com/en-us/2025/12/19/getting-started-with-xbox-cloud-gaming/), [current supported catalog](https://www.xbox.com/play)
