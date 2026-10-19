# crossedover v1.1.0

Windows apps join the library, with Steam games remaining our focus.

- Separate **Games** and **Apps** libraries, each with search and grid/list views.
- **Add .exe** imports local x86/x64 Windows programs as persistent cards. Include the containing folder for portable apps and installers with sidecar files.
- **Play** or **Run** directly from a card without installing Steam. The first import prepares the included runtime and Windows environment.
- Rename cards, move between libraries, choose an installed executable after setup, browse files, and inspect bounded launch logs. Removing a card keeps its files.
- Detached launches persist status and exit details across Mac app restarts; failed launches show an explanation on the card.
- Updated README, quickstart, offline DMG guide, and GitHub Pages website for the broader Windows app runner.

More launcher and platform support is coming soon. Apps share one Windows environment and graphics profile. Compatibility varies: extra frameworks, drivers, anti-cheat, and some launchers may be unsupported. No accounts, apps, or games are bundled. Imported files run locally with your Mac user permissions.

This is a private evaluation release, locally signed and not notarized. Existing v1.0.0 releases remain available. TrackMania’s previously verified short race result is not a guarantee of performance or long-session stability. See the quickstart and validation notes for limitations.
