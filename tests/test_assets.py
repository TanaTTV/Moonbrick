import importlib.util
import ast
from types import SimpleNamespace
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


    def test_pbr_and_rig_manifest_budgets(self):
        cfg = self.fixture()
        cfg["assets"][0]["pbr"] = True
        rig = cfg["assets"][1]
        rig.update(kind="rig", maxBones=8, maxInfluences=4, animation=True)
        self.assertTrue(self.check(cfg)["assets"][0]["pbr"])
        for key, values in (("maxBones", (0, 129, True, 2.5)), ("maxInfluences", (0, 5, True, 2.5))):
            for value in values:
                invalid = json.loads(json.dumps(cfg)); invalid["assets"][1][key] = value
                with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, key): self.check(invalid)
        for change in ({"pbr": "true"}, {"pbr": True, "maxTextureSize": 2048}, {"maxBones": 3}, {"animation": True}):
            invalid = self.fixture(); invalid["assets"][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError): self.check(invalid)

    def test_texture_map_dimensions_and_colorspaces(self):
        for role, colorspace in assets.PBR_MAPS.items():
            assets.validate_texture(role, [1024, 512], colorspace, 1024)
            for size in ([30, 16], [0, 16], [2048, 16], [True, 16]):
                with self.subTest(role=role, size=size), self.assertRaises(ValueError):
                    assets.validate_texture(role, size, colorspace, 1024)
            with self.subTest(role=role), self.assertRaisesRegex(ValueError, "colorspace"):
                assets.validate_texture(role, [16, 16], "sRGB" if colorspace == "Non-Color" else "Non-Color", 1024)
        with self.assertRaisesRegex(ValueError, "limit 1024"):
            assets.validate_texture("ColorMap", [2048, 16], "sRGB", 4096)
        with self.assertRaisesRegex(ValueError, "limit 8"):
            assets.validate_texture("NormalMap", [16, 16], "Non-Color", 8)

    def test_non_pbr_texture_keeps_arbitrary_dimensions_and_size_budget(self):
        assets.validate_texture("image legacy", [300, 200], "sRGB", 1024)
        with self.assertRaisesRegex(ValueError, "texture budget exceeded"):
            assets.validate_texture("image legacy", [300, 200], "sRGB", 256)
        for size in ([0, 200], [True, 200], [300.5, 200]):
            with self.subTest(size=size), self.assertRaisesRegex(ValueError, "positive integer"):
                assets.validate_texture("image legacy", size, "sRGB", 1024)

    def test_modern_animation_without_action_slot_has_clear_error(self):
        # Load only the real functions; export.py's top level requires Blender
        # and performs exports. This regression needs no native bpy process.
        tree = ast.parse((ROOT / "assets/blender/export.py").read_text())
        functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)
                     and node.name in ("animation_evidence", "fcurves")]
        for version in ((4, 4, 0), (5, 2, 0)):
            namespace = {"bpy": SimpleNamespace(app=SimpleNamespace(version=version))}
            exec(compile(ast.Module(body=functions, type_ignores=[]), "export.py", "exec"), namespace)
            rig = SimpleNamespace(name="FixtureRig", animation_data=SimpleNamespace(
                action=SimpleNamespace(layers=[SimpleNamespace(strips=[SimpleNamespace(
                    channelbags=[SimpleNamespace(slot_handle=1, fcurves=[])])])]), action_slot=None, nla_tracks=[]))
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "assigned action slot: FixtureRig"):
                namespace["animation_evidence"]([rig], {"animation": True}, None)

    def test_skin_budgets_count_positive_deform_weights(self):
        self.assertEqual(assets.validate_skin_budget(3, [[1, 0], [.5, .5], [.25] * 4]), 4)
        with self.assertRaisesRegex(ValueError, "influence budget exceeded at vertex 1: 5, limit 4"):
            assets.validate_skin_budget(5, [[1], [.2] * 5])
        with self.assertRaisesRegex(ValueError, "influence budget"):
            assets.validate_skin_budget(3, [[.5, .5]], max_influences=1)
        with self.assertRaisesRegex(ValueError, "unweighted"):
            assets.validate_skin_budget(3, [[0, 0]])
        with self.assertRaisesRegex(ValueError, "bone budget"):
            assets.validate_skin_budget(3, [], max_bones=2)
        for weight in (-1, float("nan"), float("inf")):
            with self.subTest(weight=weight), self.assertRaisesRegex(ValueError, "invalid skin weight"):
                assets.validate_skin_budget(3, [[weight]])


if __name__ == "__main__": unittest.main()
