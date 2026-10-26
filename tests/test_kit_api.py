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
                for line in (ROOT / rel).read_text(encoding="utf-8").splitlines():
                    match = re.match(rf"^function {name}[.:](\w+)\(", line)
                    if match:
                        self.assertIn(f"`{name}.{match.group(1)}(", card, card_path)

    def test_cards_are_much_smaller_than_the_source(self):
        for card_path, (_, modules) in kit_api.CARDS.items():
            source = sum((ROOT / rel).stat().st_size for rel, _, _ in modules)
            self.assertLess((ROOT / card_path).stat().st_size * 2.5, source, card_path)

    def test_core_card_stays_small(self):
        # The core card is read in every session; the creative modules live on their own card.
        self.assertLess((ROOT / "luau/API.md").stat().st_size, 16 * 1024)

    def test_new_projects_get_the_card(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "game"
            with contextlib.redirect_stdout(io.StringIO()):
                project.new_project(root, "card")
            self.assertEqual((root / "tools/KIT_API.md").read_bytes(), (ROOT / "luau/API.md").read_bytes())
            self.assertEqual((root / "tools/KIT_CREATIVE.md").read_bytes(), (ROOT / "luau/API-CREATIVE.md").read_bytes())
            for recipe in ("Data", "Pickups", "Ability", "Shop"):
                self.assertTrue(any((root / "tools/recipes" / recipe).rglob("*.luau")), recipe)


if __name__ == "__main__":
    unittest.main()
