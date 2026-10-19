"""Prepare the static GitHub Pages deployment; no dependencies required."""
from pathlib import Path
import argparse
import html
import json
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--download-stats", type=Path)
options = parser.parse_args()

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

if options.download_stats:
    stats = json.loads(options.download_stats.read_text())
    assert stats["schemaVersion"] == 1
    count = stats["dmgDownloads"]
    assert type(count) is int and count >= 0
    label = f'{count:,} DMG download' + ('' if count == 1 else 's')
    markup = (f'<p class="download-stats" data-download-stats>{label}'
              f'<span>GitHub release downloads · repeat downloads count · updated {html.escape(stats["updatedAt"][:10])}</span></p>')
    page = output / "index.html"
    page.write_text(page.read_text().replace('<p class="download-stats" data-download-stats>Download count unavailable</p>', markup))
    (output / "downloads.json").write_text(json.dumps(stats, indent=2) + "\n")
