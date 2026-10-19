# crossedover website

The download site lives at **https://corypearl.github.io/crossedover/**.

~~~sh
python3 -m http.server 8765 --directory website
~~~

Open http://localhost:8765. The site uses plain HTML, CSS, and local images, with no dependencies. Relative asset links support GitHub Pages' `/crossedover/` path.

Changes to this folder on `main` automatically deploy through [the Pages workflow](../.github/workflows/pages.yml). It checks the release links, runs `python3 website/build.py`, and uploads only the generated `website/dist` folder. You can also run the workflow manually from GitHub Actions. The app source, runtime, caches, and local data are excluded from the published website.

GitHub Pages serves the website publicly. The app repository remains private, so v1.1.0 release downloads require repository access. The site makes that requirement explicit. Former Sites hosting is no longer used by this build or workflow.

Images are app-owned interface previews with no account details. They are not gameplay benchmarks. The branch mark is original vector artwork.
