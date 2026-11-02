import base64
import importlib.util
from pathlib import Path
import struct
import unittest

SPEC = importlib.util.spec_from_file_location("geo_export", Path(__file__).resolve().parents[1] / "scripts/blender/geo_export.py")
geo_export = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(geo_export)


class Pack(unittest.TestCase):
    def groups(self):
        corners = [((0, 0, 0), (0, 1, 0), (255, 0, 0)), ((10, 0, 0), (0, 1, 0), (255, 0, 0)), ((0, 0, 10), (0, 1, 0), (255, 0, 0))]
        return {"Stone": {"material": "Slate", "corners": corners + corners[::-1]}}

    def test_shared_corners_are_welded(self):
        part = geo_export.pack(self.groups())["parts"][0]
        self.assertEqual((part["verts"], part["tris"]), (3, 2))
        self.assertEqual(struct.unpack("<6H", base64.b64decode(part["idx"])), (0, 1, 2, 2, 1, 0))

    def test_positions_round_trip_through_the_unit(self):
        data = geo_export.pack(self.groups())
        raw = base64.b64decode(data["parts"][0]["pos"])
        self.assertAlmostEqual(struct.unpack_from("<h", raw, 6)[0] * data["unit"], 10, places=3)

    def test_a_different_colour_splits_the_vertex(self):
        groups = self.groups()
        groups["Stone"]["corners"][3] = (groups["Stone"]["corners"][3][0], (0, 1, 0), (0, 255, 0))
        self.assertEqual(geo_export.pack(groups)["parts"][0]["verts"], 4)

    def test_module_text_is_a_returned_table(self):
        text = geo_export.to_luau("Gate", geo_export.pack(self.groups()))
        self.assertIn('return { format = 1, name = "Gate"', text)
        self.assertIn('material = "Slate"', text)
        self.assertTrue(text.startswith("--!nocheck"))


if __name__ == "__main__":
    unittest.main()
