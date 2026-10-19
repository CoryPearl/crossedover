# Reference research

Reference artifact observed locally: CrossOver 26.0.0.39794, executable SHA-256 `3b58a0a94aa8275302fe0843af2f3150f95c040d7dad1864f19d4060f46bd4ec`.

Read-only bundle observations: Wine and wineserver tools, bottle-management scripts, DXMT, DXVK, MoltenVK, and Apple graphics components are present. Package contents establish inventory only; they do not establish execution, redistribution rights, or compatibility.

REA opened the target and established its executable identity. Subsequent Mach-O inspection and session-close calls were rejected by client approval policy during planning. No proprietary decompilation was performed. Computer Use later denied access to the newly built CrossedOver app, so interactive UI and login checks remain pending.

Primary implementation references:

- https://www.codeweavers.com/crossover/source
- https://www.codeweavers.com/crossover/eula
- https://github.com/wine-mirror/wine
- https://github.com/3Shain/dxmt
- https://github.com/3Shain/dxmt/wiki/Device-System-Runtime-Specifications
- https://github.com/3Shain/dxmt/wiki/DXMT-Installation-Guide-for-Geeks
- https://github.com/Gcenx/macOS_Wine_builds
- https://support.apple.com/en-us/102527
- https://sparkle-project.org/documentation/

Workflow mapping: environment initialization → Wine prefix; Steam installation and update → official Windows client; game launching → Windows Steam; profile configuration → Wine module selection and DXMT; recovery → independently implemented prefix backups and metadata transactions. CrossOver's proprietary compatibility database, UI, assets, and binaries are not copied.

## Steam black-window investigation

The community Wine 11.18 runtime installed and updated Steam, but the user observed a black client window. Local CEF logs reported ANGLE/DXGI device-capability and GLES-context failures. Steam accepted -cef-disable-gpu but did not forward a single-process launch option to the browser helper. No login success was claimed from process presence.

A narrowly scoped, opt-in patch in the independently built Wine kernelbase process launcher appends --disable-gpu --single-process only to the main steamwebhelper.exe process. It does not alter Steam binaries, bypass authentication, or affect game rendering. This compatibility strategy is also documented by the upstream DXMT issue tracker and the author-maintained steam-on-m1-wine troubleshooting guide:

- https://github.com/3Shain/dxmt/issues/141
- https://github.com/notpop/steam-on-m1-wine/blob/main/docs/troubleshooting.md

The targeted source patch, rather than a replacement Steam executable or an injected debugger, keeps the fix reproducible across Steam self-updates.
