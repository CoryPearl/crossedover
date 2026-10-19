"""Prepare the static GitHub Pages deployment; no dependencies required."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent
output = root / "dist"
if output.exists():
    shutil.rmtree(output)
output.mkdir()
for name in ["index.html", "styles.css", "quickstart.html", "assets"]:
    source = root / name
    if source.is_dir():
        shutil.copytree(source, output / name)
    else:
        shutil.copy2(source, output / name)

# Also support ordinary static serving without Jekyll processing.
(output / ".nojekyll").touch()
