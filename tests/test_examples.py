import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import brawl_map  # noqa: E402


def parts(model):
    for child in model.get("children", []):
        if child["className"] in ("Part", "WedgePart"):
            yield child
        yield from parts(child)


class ElementBrawlMapTest(unittest.TestCase):
    def test_stage_is_deterministic(self):
        self.assertEqual(json.dumps(brawl_map.stage()), json.dumps(brawl_map.stage()))
        self.assertEqual(json.dumps(brawl_map.backdrop()), json.dumps(brawl_map.backdrop()))

    def test_every_part_is_anchored_and_scenery_never_collides(self):
        solid = {"Stage", "Grass", "FirePlatform", "IcePlatform", "StormPlatform"}
        for model in (brawl_map.stage(), brawl_map.backdrop()):
            for part in parts(model):
                props = part["properties"]
                self.assertTrue(props["Anchored"], part["name"])
                if part["name"] in solid or part["name"].startswith(("Pillar", "PillarCap")):
                    self.assertNotIn("CanCollide", props, part["name"])
                else:
                    self.assertFalse(props.get("CanCollide", True), part["name"])

    def test_rock_underside_stays_below_the_fighting_surface(self):
        for part in parts(brawl_map.stage()):
            if part["name"].startswith("Underside"):
                cframe, size = part["properties"]["CFrame"], part["properties"]["Size"]
                # Vertical half-extent of a rotated box: |row Y of the rotation| . half size.
                half_height = sum(abs(r) * s / 2 for r, s in zip(cframe[6:9], size))
                self.assertLess(cframe[1] + half_height, -0.5, part["name"])

    def test_generated_project_has_stage_backdrop_and_no_streaming(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "brawl"
            subprocess.run([sys.executable, str(ROOT / "scripts/create-example.py"), str(target), "--example", "element-brawl"],
                           check=True, capture_output=True, text=True, timeout=120)
            project = json.loads((target / "default.project.json").read_text(encoding="utf-8"))
            self.assertEqual(project["tree"]["Workspace"]["$properties"], {"StreamingEnabled": False})
            self.assertIn("ShrineAtmosphere", project["tree"]["Lighting"])
            for name in ("SkyShrine", "Backdrop"):
                self.assertTrue((target / f"src/world/{name}.model.json").is_file())
            for path in ("src/server/Brawl.server.luau", "src/server/Rules.luau", "src/shared/Elements.luau", "src/client/Brawl.client.luau", "tests/Rules.spec.luau", "EXAMPLE.md"):
                self.assertTrue((target / path).is_file(), path)


if __name__ == "__main__":
    unittest.main()
