# crossedover website

The download site lives at **https://corypearl.github.io/crossedover/**.

~~~sh
python3 -m http.server 8765 --directory website
~~~

Open http://localhost:8765. The site uses plain HTML, CSS, and local images, with no dependencies. Relative asset links support GitHub Pages' `/crossedover/` path.

Changes to this folder on `main` automatically deploy through [the Pages workflow](../.github/workflows/pages.yml). It checks the release links, runs `python3 website/build.py`, and uploads only the generated `website/dist` folder. You can also run the workflow manually from GitHub Actions. The app source, runtime, caches, and local data are excluded from the published website.

GitHub Pages serves the website publicly. The app repository remains private, so v1.4.3 release downloads require repository access. The site makes that requirement explicit. Former Sites hosting is no longer used by this build or workflow.

Images are app-owned interface previews with no account details. They are not gameplay benchmarks. The branch mark is original vector artwork.

The historical list preview shows an example installed library, including Minecraft, without account details. Minecraft’s card reads its artwork from the owner’s installed package; screenshots identify the game, and no game asset is bundled with the app. Games and Apps previews show fresh, empty libraries; no games or apps are included. Interface previews are not gameplay benchmarks.

The download count is the sum of uploaded `.dmg` asset `download_count` values on published GitHub releases (including published prereleases). Repeat downloads count; it is not unique users or installs. The Pages build reads the private API through its read-only Actions token, emits only aggregate values, and renders static HTML plus `downloads.json`. No browser API token, analytics script, cookie, or visitor tracking is used. It refreshes on publication and roughly every six hours; scheduling can be delayed. An API failure displays “Download count unavailable” instead of a false zero. Local builds stay offline unless you explicitly run `python3 website/download_stats.py --output PATH` and pass that file to `website/build.py --download-stats PATH`.

The current version is **v1.4.3**, starting new installations with an empty library, without demo-install prompts. Pages links to its DMG, which includes both the Windows runtime and the separate Minecraft backend. The main library preview shows a fresh, empty v1.4.3 installation. The list preview remains an example v1.4.0 installed library, including Minecraft’s artwork; those games are not included. The Apps preview also shows an empty v1.4.3 library. The launch-state example retains its historical label.

The Settings search preview shows the v1.4.1 Diagnostics results at the minimum window width, rendered by the app without account details.
