from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def pins(path):
    text = (ROOT / path).read_text(encoding="utf-8")
    return re.search(r"^DEFS_URL=(\S+)$", text, re.M).group(1), re.search(r"^DEFS_SHA256=([0-9a-f]{64})$", text, re.M).group(1)


class DefinitionPinTests(unittest.TestCase):
    def test_checker_and_setup_pin_the_same_definitions(self):
        url, digest = pins("template/tools/check.sh")
        self.assertEqual((url, digest), pins("scripts/setup-tools.sh"))
        self.assertRegex(url, r"^https://raw\.githubusercontent\.com/JohnnyMorganz/luau-lsp/[0-9a-f]{40}/")
        ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn(url, ci)
        self.assertIn(digest, ci)


if __name__ == "__main__": unittest.main()
