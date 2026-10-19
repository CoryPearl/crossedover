# crossedover website

A responsive, buildless download site for v1.0.0.

~~~sh
python3 -m http.server 8765 --directory website
~~~

Open http://localhost:8765. The site is index.html, styles.css, quickstart.html, and assets/. No dependencies or build step are needed.

The app repository owns this folder; Sites hosts a copy. The identity in .openai/hosting.json contains no credentials. Download links point to the v1.0.0 GitHub release. A private GitHub repository requires repository access for downloads; preserve that distinction before a public launch.

Images are app-owned interface previews with no account details. They are not gameplay benchmarks. The branch mark is original vector artwork.
