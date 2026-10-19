"""Offline regression for repeat builds with overlapping source patches."""
import difflib
from pathlib import Path
import subprocess
import tempfile
import unittest
from build import apply_patch_series


class PatchSeriesTests(unittest.TestCase):
    def test_fresh_partial_repeated_and_unknown_states(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            subprocess.run(["git", "init", "-q", source], check=True)
            file = source / "sample.txt"
            versions = ["before\nold\nafter\n", "before\nfirst\nafter\n", "before\nsecond\nafter\n"]
            file.write_text(versions[0])
            subprocess.run(["git", "add", "sample.txt"], cwd=source, check=True)
            subprocess.run(["git", "-c", "user.name=CrossedOver Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture"], cwd=source, check=True)
            patches = []
            for i in range(2):
                patch = root / f"{i}.patch"
                patch.write_text("".join(difflib.unified_diff(versions[i].splitlines(True), versions[i + 1].splitlines(True), fromfile="a/sample.txt", tofile="b/sample.txt")))
                patches.append(patch)
            apply_patch_series(source, patches[:1])
            self.assertEqual(file.read_text(), versions[1])
            apply_patch_series(source, patches)
            self.assertEqual(file.read_text(), versions[2])
            apply_patch_series(source, patches)
            self.assertEqual(file.read_text(), versions[2])
            file.write_text("unrecognized local edit\n")
            with self.assertRaises(RuntimeError):
                apply_patch_series(source, patches)
            self.assertEqual(file.read_text(), "unrecognized local edit\n")


if __name__ == "__main__":
    unittest.main()
