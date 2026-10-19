"""Offline release checks: version consistency, local site links and image sizes."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text().strip()
assert re.fullmatch(r"\d+\.\d+\.\d+", VERSION), "Invalid release version"
assert f'"{VERSION}"' in (ROOT / "Sources/CrossedOverCore/AppVersion.swift").read_text()


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.links = []
        self.ids = set()
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if "id" in attributes:
            self.ids.add(attributes["id"])
        for key in ("href", "src"):
            if key in attributes:
                self.links.append(attributes[key])
        if tag == "img":
            assert "alt" in attributes, "Missing image alt text"


site = ROOT / "website"
pages = {path.resolve(): Page(path.read_text()) for path in site.glob("*.html")}
for path, page in pages.items():
    assert VERSION in path.read_text(), f"Missing release version: {path.name}"
    for link in page.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        target = (path.parent / unquote(url.path)).resolve() if url.path else path
        if target.is_dir():
            target /= "index.html"
        assert target.is_relative_to(site.resolve()), f"Link escapes website: {link}"
        assert target.is_file(), f"Broken local link: {path.name}: {link}"
        if url.fragment and target.suffix == ".html":
            assert unquote(url.fragment) in pages[target].ids, f"Missing fragment: {link}"

for name in ("library.png", "list.png"):
    data = (site / "assets" / name).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG: {name}"
    assert struct.unpack(">II", data[16:24]) == (2200, 1520), f"Unexpected image size: {name}"

for name in ("README.md", "QUICKSTART.md", "docs/QUICKSTART.html"):
    assert VERSION in (ROOT / name).read_text(), f"Missing version: {name}"
assert 'href="styles.css"' not in (ROOT / "docs/QUICKSTART.html").read_text(), "DMG guide must work offline"
print(f"v{VERSION}: versions, website links, image metadata, and offline guide passed")
