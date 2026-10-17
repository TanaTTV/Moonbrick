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

    def test_every_public_function_is_on_the_card(self):
        card = (ROOT / "luau/API.md").read_text(encoding="utf-8")
        for rel, _, _ in kit_api.MODULES:
            name = Path(rel).stem
            for line in (ROOT / rel).read_text(encoding="utf-8").splitlines():
                match = re.match(rf"^function {name}[.:](\w+)\(", line)
                if match:
                    self.assertIn(f"`{name}.{match.group(1)}(", card)

    def test_card_is_much_smaller_than_the_source(self):
        source = sum((ROOT / rel).stat().st_size for rel, _, _ in kit_api.MODULES)
        self.assertLess((ROOT / "luau/API.md").stat().st_size * 3, source)

    def test_new_projects_get_the_card(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "game"
            with contextlib.redirect_stdout(io.StringIO()):
                project.new_project(root, "card")
            self.assertEqual((root / "tools/KIT_API.md").read_bytes(), (ROOT / "luau/API.md").read_bytes())
            for recipe in ("Data", "Pickups", "Ability", "Shop"):
                self.assertTrue(any((root / "tools/recipes" / recipe).rglob("*.luau")), recipe)


if __name__ == "__main__":
    unittest.main()
