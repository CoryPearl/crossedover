"""Publish aggregate GitHub DMG download counts, with no browser credentials."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

REPOSITORY = "CoryPearl/crossedover"


def summarize(releases, now=None):
    total = 0
    published = 0
    for release in releases:
        if release.get("draft") or not release.get("published_at"):
            continue
        downloads = [asset for asset in release.get("assets", [])
                     if asset.get("name", "").lower().endswith(".dmg")
                     and asset.get("state") == "uploaded"]
        if downloads:
            published += 1
        for asset in downloads:
            count = asset.get("download_count")
            if type(count) is not int or count < 0:
                raise ValueError("GitHub returned an invalid download count")
            total += count
    return {"schemaVersion": 1, "dmgDownloads": total,
            "publishedReleases": published,
            "updatedAt": (now or datetime.now(timezone.utc)).isoformat(timespec="seconds"),
            "metric": "GitHub release DMG downloads; repeat downloads count"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    # gh authenticates on the build machine. No token or full API response is
    # copied into the public site, and visitors never call the private API.
    result = subprocess.run(["gh", "api", "--paginate", "--slurp",
                             f"repos/{REPOSITORY}/releases?per_page=100"],
                            check=True, capture_output=True, text=True, timeout=60)
    pages = json.loads(result.stdout)
    stats = summarize([release for page in pages for release in page])
    options.output.parent.mkdir(parents=True, exist_ok=True)
    options.output.write_text(json.dumps(stats, indent=2) + "\n")
    print(f"Published aggregate count: {stats['dmgDownloads']:,} DMG downloads")


if __name__ == "__main__":
    main()
