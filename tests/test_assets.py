import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("asset_tools", ROOT / "scripts/assets.py")
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


class AssetTests(unittest.TestCase):
    def check(self, cfg):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "art.json"
            path.write_text(json.dumps(cfg))
            return assets.validate(path)

    def fixture(self): return json.loads((ROOT / "assets/art.example.json").read_text())

    def test_valid_art_manifest(self): self.assertEqual(len(self.check(self.fixture())["assets"]), 2)

    def test_unsafe_names_duplicate_ids_and_source_escape(self):
        for value in ("../escape", "a/b", "A", "bad\\path"):
            cfg = self.fixture(); cfg["assets"][0]["id"] = value
            with self.subTest(value=value), self.assertRaises(ValueError): self.check(cfg)
        cfg = self.fixture(); cfg["assets"][1]["id"] = cfg["assets"][0]["id"]
        with self.assertRaises(ValueError): self.check(cfg)
        for source in ("../source.blend", "/source.blend", "..\\source.blend"):
            cfg = self.fixture(); cfg["source"] = source
            with self.subTest(source=source), self.assertRaises(ValueError): self.check(cfg)

    def test_invalid_budgets_palette_and_units(self):
        for value in (-1, 0, 100001, True, 1.5):
            cfg = self.fixture(); cfg["assets"][0]["maxTriangles"] = value
            with self.subTest(value=value), self.assertRaises(ValueError): self.check(cfg)
        cfg = self.fixture(); cfg["style"]["palette"]["accent"] = "gold"
        with self.assertRaises(ValueError): self.check(cfg)
        cfg = self.fixture(); cfg["units"] = "unknown"
        with self.assertRaises(ValueError): self.check(cfg)


if __name__ == "__main__": unittest.main()
