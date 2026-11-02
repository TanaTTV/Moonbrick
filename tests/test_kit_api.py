"""The Kit API card stays in sync with the Kit sources and ships into every project."""
import contextlib
import importlib.util
import io
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


kit_api = load("kit_api", "scripts/kit-api.py")
test_studio = load("test_studio", "scripts/test-studio.py")
project = load("project", "scripts/project.py")


class KitApiTests(unittest.TestCase):
    def test_card_is_up_to_date(self):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(kit_api.main(["--check"]), 0, "run python scripts/kit-api.py")

    def test_every_public_function_is_on_a_card(self):
        for card_path, (_, modules) in kit_api.CARDS.items():
            card = (ROOT / card_path).read_text(encoding="utf-8")
            for rel, _, _ in modules:
                name = Path(rel).stem
                internal = kit_api.INTERNAL.get(name, set())
                for line in (ROOT / rel).read_text(encoding="utf-8").splitlines():
                    match = re.match(rf"^function {name}[.:](\w+)(?:<[^>]*>)?\(", line)
                    if match and match.group(1) not in internal:
                        self.assertRegex(card, rf"`{name}\.{match.group(1)}[(<]", card_path)

    def test_cards_carry_what_the_source_comments_say(self):
        card = (ROOT / "luau/API-CREATIVE.md").read_text(encoding="utf-8")
        for needed in (
            "`Motion.keys<T>(", "`Motion.sample<T>(", "`Motion.length<T>(",  # generics
            "elasticOut", "sineInOut",  # the ease names above `export type Ease`
            "ball, block, cylinder, ring, torus, shard, wedge",  # Fx shapes
            "Adds a shape",  # the Geo.register explanation
            "`Pose.R15 = { Root, Waist,",  # list values, not an empty table
            'export type Name = "glow" | "core"',  # multi-line unions
        ):
            self.assertIn(needed, card)

    def test_cards_are_much_smaller_than_the_source(self):
        for card_path, (_, modules) in kit_api.CARDS.items():
            source = sum((ROOT / rel).stat().st_size for rel, _, _ in modules)
            self.assertLess((ROOT / card_path).stat().st_size * 2.5, source, card_path)

    def test_core_card_stays_small(self):
        # The core card is read in every session; the creative modules live on their own card.
        self.assertLess((ROOT / "luau/API.md").stat().st_size, 19 * 1024)

    def test_studio_bundle_inlines_every_module_a_spec_needs(self):
        bundle = test_studio.bundle()
        for name in sorted({*test_studio.SHARED, "PlayerData", "Round", "MCPKit"}):
            self.assertIn(f"modules.{name} = (function()", bundle)
        self.assertNotIn("require(script.Parent", bundle)
        self.assertEqual(re.findall(r"t\.require\([^)]*\)", bundle), [], "a spec would load a real module")
        order = [bundle.index(f"modules.{name} = (function()") for name in test_studio.SHARED]
        self.assertEqual(order, sorted(order))

    def test_new_projects_get_the_card(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "game"
            with contextlib.redirect_stdout(io.StringIO()):
                project.new_project(root, "card")
            self.assertEqual((root / "tools/KIT_API.md").read_bytes(), (ROOT / "luau/API.md").read_bytes())
            for module in ("Scene", "GeoShapes", "Scatter", "Camera"):
                self.assertTrue((root / f"src/kit/shared/{module}.luau").is_file(), module)
            self.assertEqual((root / "tools/KIT_CREATIVE.md").read_bytes(), (ROOT / "luau/API-CREATIVE.md").read_bytes())
            for recipe in ("Data", "Pickups", "Ability", "Shop", "Checkpoints", "Zones", "Round", "Obby"):
                self.assertTrue(any((root / "tools/recipes" / recipe).rglob("*.luau")), recipe)


if __name__ == "__main__":
    unittest.main()
