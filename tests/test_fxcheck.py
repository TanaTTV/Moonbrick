import contextlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fxcheck", ROOT / "scripts/fxcheck.py")
fx = importlib.util.module_from_spec(spec)
sys.modules["fxcheck"] = fx  # dataclasses resolve annotations through sys.modules
spec.loader.exec_module(fx)
fxtex_spec = importlib.util.spec_from_file_location("fxtex", ROOT / "scripts/fxtex.py")
fxtex = importlib.util.module_from_spec(fxtex_spec)
fxtex_spec.loader.exec_module(fxtex)


def png(width, height, pixel, color=6, filters=(0,)):
    """pixel(x, y) -> RGBA; encoded with the given per-row filter cycle so the decoder gets exercised."""
    channels = {6: 4, 2: 3, 0: 1, 4: 2}[color]
    rows, previous = [], bytes(width * channels)
    for y in range(height):
        row = bytearray()
        for x in range(width):
            r, g, b, a = pixel(x, y)
            row += bytes({6: (r, g, b, a), 2: (r, g, b), 0: (r,), 4: (r, a)}[color])
        kind = filters[y % len(filters)]
        out = bytearray(row)
        for i in range(len(row)):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            corner = previous[i - channels] if i >= channels else 0
            if kind == 1:
                out[i] = (row[i] - left) & 255
            elif kind == 2:
                out[i] = (row[i] - up) & 255
            elif kind == 3:
                out[i] = (row[i] - ((left + up) >> 1)) & 255
            elif kind == 4:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                out[i] = (row[i] - (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 255
        rows.append(bytes([kind]) + bytes(out))
        previous = bytes(row)
    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))
    header = struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)
    return fx.SIGNATURE + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")


def dot(width, height):
    """A white dot well inside the image."""
    def pixel(x, y):
        inside = width // 3 <= x < width * 2 // 3 and height // 3 <= y < height * 2 // 3
        return (255, 255, 255, 255 if inside else 0)
    return pixel


def sheet(width, grid, drawn=None, margin=3, value=lambda col, row: 255):
    """A grid of cells, each with an inset block; `drawn` limits which cells have one."""
    cell = width // grid
    def pixel(x, y):
        col, row = x // cell, y // cell
        index = row * grid + col
        if (drawn is None or index in drawn) and margin <= x % cell < cell - margin and margin <= y % cell < cell - margin:
            return (255, 255, 255, value(col, row))
        return (255, 255, 255, 0)
    return pixel


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def write(self, name, data):
        path = self.dir / name
        path.write_bytes(data)
        return path

    def check(self, name, data, grid=None, auto=False):
        return fx.check_file(self.write(name, data), grid, auto)

    def assertHas(self, items, text):
        self.assertTrue(any(text in item for item in items), f"{text!r} not in {items}")


class Decoder(Case):
    def test_all_filters_round_trip(self):
        pixel = lambda x, y: ((x * 7) & 255, (y * 11) & 255, (x + y) & 255, (x * y) & 255)
        image = fx.decode(png(16, 16, pixel, filters=(0, 1, 2, 3, 4)))
        self.assertEqual(image.rgba(5, 9), pixel(5, 9))
        self.assertEqual(image.rgba(15, 15), pixel(15, 15))

    def test_rgb_grey_and_grey_alpha(self):
        self.assertEqual(fx.decode(png(4, 4, lambda x, y: (10, 20, 30, 0), color=2)).rgba(1, 1), (10, 20, 30, 255))
        self.assertEqual(fx.decode(png(4, 4, lambda x, y: (40, 0, 0, 0), color=0)).rgba(1, 1), (40, 40, 40, 255))
        self.assertEqual(fx.decode(png(4, 4, lambda x, y: (40, 0, 0, 90), color=4)).rgba(1, 1), (40, 40, 40, 90))

    def test_unsupported_and_broken_files_are_problems_not_crashes(self):
        palette = png(4, 4, dot(4, 4)).replace(struct.pack(">BBBBB", 8, 6, 0, 0, 0), struct.pack(">BBBBB", 8, 3, 0, 0, 0))
        for name, data in (("text.png", b"hello"), ("cut.png", png(8, 8, dot(8, 8))[:40]), ("palette.png", palette)):
            with self.subTest(name=name):
                report = self.check(name, data)
                self.assertHas(report.problems, "unreadable")

    def test_oversized_image_is_refused_before_decoding(self):
        header = fx.SIGNATURE + struct.pack(">I", 13) + b"IHDR" + struct.pack(">IIBBBBB", 8000, 8000, 8, 6, 0, 0, 0)
        report = self.check("huge.png", header + b"\0" * 8)
        self.assertHas(report.problems, "not decoded")


class Single(Case):
    def test_clean_texture(self):
        report = self.check("a.png", png(32, 32, dot(32, 32)))
        self.assertEqual(report.problems, [])
        self.assertIn("transparent", report.summary)
        self.assertIn("crisp", report.summary)

    def test_nothing_drawn(self):
        self.assertHas(self.check("a.png", png(16, 16, lambda x, y: (255, 255, 255, 0))).problems, "nothing is drawn")
        self.assertHas(self.check("b.png", png(16, 16, lambda x, y: (0, 0, 0, 255))).problems, "nothing is drawn")

    def test_solid_square(self):
        self.assertHas(self.check("a.png", png(16, 16, lambda x, y: (200, 40, 40, 255))).problems, "solid square")

    def test_black_background_is_additive(self):
        pixel = lambda x, y: (255, 255, 255, 255) if 6 <= x < 10 and 6 <= y < 10 else (0, 0, 0, 255)
        report = self.check("a.png", png(16, 16, pixel))
        self.assertEqual(report.problems, [])
        self.assertIn("black", report.summary)
        self.assertHas(report.notes, "LightEmission = 1")

    def test_shape_on_black_has_corners_black_not_opaque_only(self):
        pixel = lambda x, y: (255, 0, 0, 255) if x == 0 and y == 8 else (0, 0, 0, 255)
        self.assertHas(self.check("a.png", png(16, 16, pixel)).problems, "edge")

    def test_edge_contact(self):
        pixel = lambda x, y: (255, 255, 255, 255 if y == 8 else 0)
        self.assertHas(self.check("a.png", png(16, 16, pixel)).problems, "image edge")

    def test_tint_is_a_note(self):
        pixel = lambda x, y: (255, 80, 0, 255) if 6 <= x < 10 and 6 <= y < 10 else (0, 0, 0, 0)
        report = self.check("a.png", png(16, 16, pixel))
        self.assertEqual(report.problems, [])
        self.assertHas(report.notes, "rgb(255,80,0)")

    def test_soft_label(self):
        pixel = lambda x, y: (255, 255, 255, 100) if 6 <= x < 10 and 6 <= y < 10 else (0, 0, 0, 0)
        self.assertIn("soft", self.check("a.png", png(16, 16, pixel)).summary)

    def test_size_is_a_note_and_never_a_failure(self):
        report = self.check("a.png", png(1100, 4, lambda x, y: (0, 0, 0, 0)))
        self.assertHas(report.notes, "unresolved")
        self.assertFalse(any("1024" in problem for problem in report.problems))


class Sheets(Case):
    def test_grid_is_inferred_largest_first(self):
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 4)))
        self.assertEqual(report.grid, 4)
        self.assertEqual(report.problems, [])
        self.assertHas(report.notes, "empty gutters")
        self.assertIn("Grid4x4", report.settings)

    def test_eight_wins_when_the_gutters_allow_it(self):
        self.assertEqual(self.check("a.flipbook.png", png(64, 64, sheet(64, 8, margin=2))).grid, 8)

    def test_sheet_size_is_reported_but_not_enforced(self):
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 4)))
        self.assertHas(report.notes, "not enforced")
        self.assertEqual(report.problems, [])

    def test_no_gutters_fail(self):
        report = self.check("a.flipbook.png", png(64, 64, lambda x, y: (255, 255, 255, 255 if y == 31 else 0)))
        self.assertHas(report.problems, "no 2x2, 4x4 or 8x8 grid")

    def test_claimed_grid_that_bleeds(self):
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 2)), grid=4)
        self.assertHas(report.problems, "crosses the 4x4")

    def test_impossible_claims(self):
        self.write("a.flipbook.json", json.dumps({"grid": 3}).encode())
        self.assertHas(self.check("a.flipbook.png", png(64, 64, sheet(64, 4))).problems, "2x2, 4x4 or 8x8")
        self.assertHas(self.check("b.flipbook.png", png(12, 12, lambda x, y: (0, 0, 0, 0)), grid=8).problems, "too small")

    def test_empty_cell_in_the_middle(self):
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 4, drawn=set(range(16)) - {5})), grid=4)
        self.assertHas(report.problems, "1 of 16 cells are empty (#6)")

    def test_trailing_empties_suggest_a_one_shot(self):
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 4, drawn=set(range(12)))), grid=4)
        self.assertEqual(report.problems, [])
        self.assertHas(report.notes, "last 4 of 16")
        self.assertIn("OneShot", report.settings)

    def test_loop_true_makes_trailing_empties_a_problem(self):
        self.write("a.flipbook.json", json.dumps({"loop": True}).encode())
        self.assertHas(self.check("a.flipbook.png", png(64, 64, sheet(64, 4, drawn=set(range(12)), value=lambda c, r: 200 + c + r * 4))).problems, "4 of 16 cells are empty")

    def test_loop_false_accepts_trailing_empties_and_times_the_run(self):
        self.write("a.flipbook.json", json.dumps({"loop": False, "fps": 8}).encode())
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 4, drawn=set(range(12)), value=lambda c, r: 200 + c + r * 4)))
        self.assertEqual(report.problems, [])
        self.assertIn("FlipbookMode = OneShot", report.settings)
        self.assertIn("Lifetime = 2", report.settings)

    def test_framerate_is_capped_for_loops(self):
        self.write("a.flipbook.json", json.dumps({"loop": True, "fps": 60}).encode())
        self.assertIn("FlipbookFramerate = 30", self.check("a.flipbook.png", png(64, 64, sheet(64, 4))).settings)

    def test_every_cell_empty(self):
        self.assertHas(self.check("a.flipbook.png", png(64, 64, lambda x, y: (0, 0, 0, 0)), grid=4).problems, "every cell")

    def test_repeated_cells_are_a_note(self):
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 4)), grid=4)
        self.assertHas(report.notes, "15 cell(s) repeat")

    def test_different_cells_do_not_repeat(self):
        report = self.check("a.flipbook.png", png(64, 64, sheet(64, 4, value=lambda c, r: 100 + c * 10 + r * 40)), grid=4)
        self.assertFalse(any("repeat" in note for note in report.notes))

    def test_cell_edge_contact_and_padding(self):
        tight = png(64, 64, sheet(64, 4, margin=1))
        self.assertHas(self.check("a.flipbook.png", tight, grid=4).problems, "edge of 16 cell(s)")
        roomy = png(64, 64, sheet(64, 4, margin=3))
        self.assertEqual(self.check("b.flipbook.png", roomy, grid=4).problems, [])
        self.write("c.flipbook.json", json.dumps({"padding": 4}).encode())
        self.assertHas(self.check("c.flipbook.png", roomy).problems, "edge of 16 cell(s)")

    def test_additive_sheet_sets_light_emission(self):
        cell = sheet(64, 4)
        pixel = lambda x, y: (255, 255, 255, 255) if cell(x, y)[3] else (0, 0, 0, 255)
        self.assertIn("LightEmission = 1", self.check("a.flipbook.png", png(64, 64, pixel), grid=4).settings)

    def test_note_beside_a_plain_name_makes_it_a_sheet(self):
        self.write("smoke.flipbook.json", json.dumps({"grid": 4}).encode())
        self.assertEqual(self.check("smoke.png", png(64, 64, sheet(64, 4))).grid, 4)

    def test_bad_note_is_a_note_not_a_crash(self):
        self.write("a.flipbook.json", b"{not json")
        self.assertHas(self.check("a.flipbook.png", png(64, 64, sheet(64, 4))).notes, "could not be read")
        self.write("b.flipbook.json", b"[1]")
        self.assertHas(self.check("b.flipbook.png", png(64, 64, sheet(64, 4))).notes, "not a JSON object")


class Command(Case):
    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = fx.main(list(args))
        return code, out.getvalue()

    def test_exit_codes(self):
        good = self.write("good.png", png(32, 32, dot(32, 32)))
        bad = self.write("bad.png", png(16, 16, lambda x, y: (200, 40, 40, 255)))
        self.assertEqual(self.run_main(str(good))[0], 0)
        self.assertEqual(self.run_main(str(good), str(bad))[0], 1)

    def test_folder_and_json_output(self):
        self.write("good.png", png(32, 32, dot(32, 32)))
        code, out = self.run_main(str(self.dir), "--json")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out.splitlines()[0])["problems"], [])

    def test_contact_sheet_is_a_valid_labelled_png(self):
        self.write("a.png", png(32, 32, dot(32, 32)))
        self.write("b.flipbook.png", png(64, 64, sheet(64, 4)))
        target = self.dir / "out/contact.png"
        code, out = self.run_main(str(self.dir), "--sheet", str(target))
        self.assertEqual(code, 0)
        self.assertIn("#1 a.png", out)
        self.assertIn("#2 b.flipbook.png", out)
        image = fx.decode(target.read_bytes())
        self.assertGreater(image.width, 500)
        self.assertEqual(image.rgba(0, 0)[:3], fx.CANVAS_FILL)
        label = {image.rgba(fx.GAP + x, fx.GAP + y)[:3] for x in range(24) for y in range(24)}
        self.assertIn((255, 255, 255), label)

    def test_bad_grid_is_a_usage_error(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
            self.run_main(str(self.dir), "--grid", "3")
        self.assertEqual(caught.exception.code, 2)

    def test_reads_what_fxtex_writes(self):
        fxtex.render(self.dir, ["glow", "ring"])
        reports = [fx.check_file(self.dir / name, None, False) for name in ("glow.png", "ring.png")]
        self.assertEqual([report.problems for report in reports], [[], []])


if __name__ == "__main__":
    unittest.main()
