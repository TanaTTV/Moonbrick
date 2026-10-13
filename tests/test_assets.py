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
    def test_modern_material_nodes_never_access_removed_toggle(self):
        class ModernMaterial:
            node_tree = object()

            @property
            def use_nodes(self):
                raise AssertionError("deprecated use_nodes read")

            @use_nodes.setter
            def use_nodes(self, value):
                raise AssertionError("deprecated use_nodes write")

        material = ModernMaterial()
        for version in ((5, 0, 0), (5, 2, 2), (6, 0, 0)):
            for enable in (False, True):
                with self.subTest(version=version, enable=enable):
                    self.assertIs(assets.material_node_tree(material, version, enable=enable), material.node_tree)

    def test_legacy_material_toggle_is_preserved(self):
        class LegacyMaterial:
            use_nodes = False
            node_tree = object()

        material = LegacyMaterial()
        self.assertIsNone(assets.material_node_tree(material, (4, 5, 0)))
        self.assertIs(assets.material_node_tree(material, (4, 5, 0), enable=True), material.node_tree)
        self.assertTrue(material.use_nodes)
        self.assertIs(assets.material_node_tree(material, (4, 5, 0)), material.node_tree)

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
