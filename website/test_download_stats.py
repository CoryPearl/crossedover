import unittest
from datetime import datetime, timezone
from download_stats import summarize


class DownloadStatsTests(unittest.TestCase):
    def test_counts_only_uploaded_dmgs_from_published_releases(self):
        asset = lambda name, count, state="uploaded": dict(name=name, download_count=count, state=state)
        releases = [dict(draft=False, published_at="2026-01-01", assets=[
            asset("crossedover.dmg", 9), asset("SHA256SUMS", 50), asset("old.DMG", 4), asset("partial.dmg", 99, "new")]),
            dict(draft=True, published_at="2026-01-01", assets=[asset("draft.dmg", 100)]),
            dict(draft=False, published_at=None, assets=[asset("unpublished.dmg", 100)])]
        result = summarize(releases, datetime(2026, 10, 19, tzinfo=timezone.utc))
        self.assertEqual(result["dmgDownloads"], 13)
        self.assertEqual(result["publishedReleases"], 1)
        self.assertEqual(set(result), {"schemaVersion", "dmgDownloads", "publishedReleases", "updatedAt", "metric"})
        self.assertNotIn("assets", result)

    def test_zero_is_a_real_count(self):
        self.assertEqual(summarize([])["dmgDownloads"], 0)

    def test_invalid_counts_fail_instead_of_publishing_a_wrong_number(self):
        for count in [-1, "12", True, None]:
            with self.assertRaises(ValueError):
                summarize([dict(draft=False, published_at="now", assets=[dict(name="app.dmg", state="uploaded", download_count=count)])])


if __name__ == "__main__":
    unittest.main()
