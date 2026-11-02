"""Check effect textures before upload: is it readable as an effect, and is a flipbook sheet sound?

    python scripts/fxcheck.py <file.png|dir> [...] [--grid auto|2|4|8] [--sheet out.png] [--json]

A file is treated as a flipbook sheet when it is named *.flipbook.png, has a <name>.flipbook.json
note beside it, or --grid is given. The note is optional; all of its keys are optional too:
{"grid": 4, "padding": 3, "loop": false, "fps": 24}.

Exit 0 when clean, 1 when any file has a problem, 2 on bad usage. Notes never fail a file.
Standard library only (zlib + struct PNG reader and writer).
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import json
import math
import os
from pathlib import Path
import struct
import sys
import zlib

MAX_FILE_BYTES = 32 * 1024 * 1024
MAX_SIDE = 4096  # checked before decoding, so a huge file can't stall the check
LOW = 8  # alpha or brightness at or below this counts as nothing drawn
GRIDS = (8, 4, 2)
MIN_CELL = 4
EDGE_BAND = 2
SOFT_WEIGHT = 230
NOTE_LIMIT = 16 * 1024
SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


class BadImage(ValueError):
    pass


@dataclass
class Image:
    width: int
    height: int
    pixels: bytes  # straight RGBA, 8 bits a channel

    def rgba(self, x: int, y: int) -> tuple[int, int, int, int]:
        start = (y * self.width + x) * 4
        return tuple(self.pixels[start:start + 4])


def png_size(data: bytes) -> tuple[int, int]:
    if not data.startswith(SIGNATURE) or data[12:16] != b"IHDR":
        raise BadImage("not a PNG file")
    return struct.unpack(">II", data[16:24])


def unfilter(raw: bytes, width: int, height: int, channels: int) -> bytes:
    stride = width * channels
    if len(raw) < (stride + 1) * height:
        raise BadImage("truncated image data")
    rows, previous = [], bytes(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(channels, stride):
                row[i] = (row[i] + row[i - channels]) & 255
        elif kind == 2:
            row = bytearray((a + b) & 255 for a, b in zip(row, previous))
        elif kind == 3:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                row[i] = (row[i] + ((left + previous[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = row[i - channels] if i >= channels else 0
                b = previous[i]
                c = previous[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        elif kind != 0:
            raise BadImage(f"unknown PNG filter {kind}")
        rows.append(bytes(row))
        previous = rows[-1]
    return b"".join(rows)


def to_rgba(data: bytes, width: int, height: int, color: int) -> bytes:
    count = width * height
    if color == 6:
        return data
    out = bytearray(b"\xff" * (count * 4))
    if color == 2:
        for channel in range(3):
            out[channel::4] = data[channel::3]
    elif color == 0:
        for channel in range(3):
            out[channel::4] = data
    else:  # grey + alpha
        for channel in range(3):
            out[channel::4] = data[0::2]
        out[3::4] = data[1::2]
    return bytes(out)


def decode(data: bytes) -> Image:
    width, height = png_size(data)
    if not width or not height:
        raise BadImage("the image has no pixels")
    offset, chunks, header = 8, [], None
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            header = body
        elif kind == b"IDAT":
            chunks.append(body)
        elif kind == b"IEND":
            break
        offset += length + 12
    if not header or len(header) != 13 or not chunks:
        raise BadImage("missing PNG chunks")
    depth, color, _, _, interlace = struct.unpack(">BBBBB", header[8:13])
    if depth != 8 or color not in CHANNELS or interlace:
        raise BadImage(f"unsupported PNG (bit depth {depth}, color type {color}, interlace {interlace}); export 8-bit RGBA")
    try:
        raw = zlib.decompress(b"".join(chunks))
    except zlib.error as error:
        raise BadImage(f"corrupt image data ({error})") from None
    return Image(width, height, to_rgba(unfilter(raw, width, height, CHANNELS[color]), width, height, color))


def encode(width: int, height: int, rgb: bytes) -> bytes:
    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    stride = width * 3
    raw = b"".join(b"\0" + rgb[y * stride:(y + 1) * stride] for y in range(height))
    return SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")


def background(image: Image) -> str:
    """Effects are drawn on transparency, or on black for additive use. Anything else shows as a square."""
    corners = [image.rgba(x, y) for x in (0, image.width - 1) for y in (0, image.height - 1)]
    if all(pixel[3] <= LOW for pixel in corners):
        return "transparent"
    if all(max(pixel[:3]) <= LOW for pixel in corners):
        return "black"
    return "other"


@dataclass
class Measure:
    background: str
    mask: bytearray
    coverage: float = 0.0
    soft: float = 0.0
    opaque: bool = True
    touches_edge: bool = False
    average: tuple[float, float, float] = (0.0, 0.0, 0.0)


def measure(image: Image) -> Measure:
    width, height, pixels = image.width, image.height, image.pixels
    kind = background(image)
    keeps_dark = kind == "transparent"  # on black, a dark pixel is just background
    result = Measure(kind, bytearray(width * height))
    drawn = soft = 0
    weight_total = red = green = blue = 0.0
    index = 0
    for r, g, b, a in zip(pixels[0::4], pixels[1::4], pixels[2::4], pixels[3::4]):
        if a != 255:
            result.opaque = False
        top = max(r, g, b)
        if a > LOW and (keeps_dark or top > LOW):
            result.mask[index] = 1
            drawn += 1
            weight = float(a) if keeps_dark else a * top / 255
            soft += weight < SOFT_WEIGHT
            weight_total += weight
            red += r * weight
            green += g * weight
            blue += b * weight
        index += 1
    result.coverage = drawn / (width * height)
    if drawn:
        result.soft = soft / drawn
    if weight_total:
        result.average = (red / weight_total, green / weight_total, blue / weight_total)
    band = EDGE_BAND
    rows = [*range(min(band, height)), *range(max(band, height - band), height)]
    columns = [*range(min(band, width)), *range(max(band, width - band), width)]
    result.touches_edge = any(any(result.mask[y * width:(y + 1) * width]) for y in rows) or any(result.mask[y * width + x] for y in range(height) for x in columns)
    return result


def fits(image: Image, grid: int) -> bool:
    return image.width // grid >= MIN_CELL and image.height // grid >= MIN_CELL


def gutters_clear(mask: bytearray, width: int, height: int, grid: int) -> bool:
    """Bleeding across a cell boundary flashes in play, so every boundary must be empty, 1 px each side."""
    for step in range(1, grid):
        for y in (step * height // grid - 1, step * height // grid):
            if any(mask[y * width:(y + 1) * width]):
                return False
        for x in (step * width // grid - 1, step * width // grid):
            if any(mask[x::width]):
                return False
    return True


@dataclass
class Note:
    grid: float = 0
    padding: float = 0
    loop: bool | None = None
    fps: float = 0
    warning: str = ""


def note_path(path: Path) -> Path:
    stem = path.name[:-4] if path.name.lower().endswith(".png") else path.name
    if stem.lower().endswith(".flipbook"):
        stem = stem[:-9]
    return path.with_name(stem + ".flipbook.json")


def read_note(path: Path) -> Note | None:
    target = note_path(path)
    if not target.is_file():
        return None
    try:
        if target.stat().st_size > NOTE_LIMIT:
            return Note(warning=f"{target.name} is over {NOTE_LIMIT // 1024} KB and was ignored")
        data = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return Note(warning=f"{target.name} could not be read ({error})")
    if not isinstance(data, dict):
        return Note(warning=f"{target.name} is not a JSON object and was ignored")
    number = lambda key: data[key] if isinstance(data.get(key), (int, float)) and not isinstance(data.get(key), bool) else 0
    return Note(number("grid"), number("padding"), data["loop"] if isinstance(data.get("loop"), bool) else None, max(number("fps"), 0))


@dataclass
class Report:
    path: Path
    image: Image | None = None
    summary: str = ""
    grid: int = 0
    problems: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    settings: str = ""


def indices(items: list[int]) -> str:
    shown = ", ".join(f"#{item + 1}" for item in items[:8])
    return shown + (f" and {len(items) - 8} more" if len(items) > 8 else "")


def edge_label(soft: float) -> str:
    return "soft" if soft > 0.6 else "mixed edges" if soft > 0.2 else "crisp"


def size_note(report: Report, width: int, height: int):
    if max(width, height) > 1024:
        report.notes.append(f"{width}x{height} is over 1024, so Roblox may downscale it on upload. Not failed: the exact sheet-size rule is unresolved.")


def check_single(report: Report, image: Image, result: Measure):
    if result.background == "other":
        report.problems.append("it shows as a solid square: the corners are neither transparent nor black. Remove the background, or draw on pure black for additive use.")
    elif result.coverage == 0:
        report.problems.append("nothing is drawn.")
    elif result.touches_edge:
        report.problems.append("the shape reaches the image edge, so it will show a hard cut-off. Leave a margin or fade out before the edge.")
    if result.background == "black":
        report.notes.append("no transparency: use LightEmission = 1 so black adds nothing.")
    size_note(report, image.width, image.height)


def check_sheet(report: Report, image: Image, result: Measure, note: Note, forced: int | None):
    width, height = image.width, image.height
    report.notes.append(f"sheet size {width}x{height}: 512x512 and 1024x1024 both play in Studio 0.743, even when FlipbookIncompatible complains.")
    size_note(report, width, height)
    inferred = next((grid for grid in GRIDS if fits(image, grid) and gutters_clear(result.mask, width, height, grid)), 0)
    wanted = forced if forced is not None else note.grid
    claimed = 0
    if wanted:
        if wanted in GRIDS:
            claimed = int(wanted)
        else:
            report.problems.append(f"a grid of {wanted:g} was requested, but Roblox flipbooks are 2x2, 4x4 or 8x8.")
    if claimed:
        if not fits(image, claimed):
            report.problems.append(f"at {width}x{height} it is too small for {claimed}x{claimed} cells.")
            return
        if not gutters_clear(result.mask, width, height, claimed):
            report.problems.append(f"drawing crosses the {claimed}x{claimed} cell boundaries, so frames will bleed into each other.")
    if result.background == "other":
        report.problems.append("the corners are neither transparent nor black, so cells show as solid squares.")
    grid = claimed or inferred
    if not grid:
        report.problems.append("no 2x2, 4x4 or 8x8 grid fits: nothing leaves clear gutters between cells.")
        return
    report.grid = grid
    if not claimed:
        report.notes.append(f"grid read from the empty gutters; name it in {note_path(report.path).name} to be sure.")
    check_cells(report, image, result, note, grid)


def check_cells(report: Report, image: Image, result: Measure, note: Note, grid: int):
    width, height = image.width, image.height
    margin = int(max(0, min(min(width // grid, height // grid) // 4, math.floor(note.padding))))
    band = margin + EDGE_BAND
    empty, edge, repeats = [], [], []
    previous = None
    for row in range(grid):
        y0, y1 = row * height // grid, (row + 1) * height // grid
        for column in range(grid):
            x0, x1 = column * width // grid, (column + 1) * width // grid
            index = row * grid + column
            count, touched = 0, False
            raw = bytearray()
            for y in range(y0, y1):
                line = result.mask[y * width + x0:y * width + x1]
                raw += image.pixels[(y * width + x0) * 4:(y * width + x1) * 4]
                drawn = line.count(1)
                if drawn:
                    count += drawn
                    near_edge = y - y0 < band or y1 - y <= band or any(line[:band]) or any(line[-band:])
                    touched = touched or near_edge
            if not count:
                empty.append(index)
            if touched:
                edge.append(index)
            if count and previous == bytes(raw):
                repeats.append(index)
            previous = bytes(raw) if count else None
    cells = grid * grid
    trailing = 0
    while trailing < len(empty) and empty[-1 - trailing] == cells - 1 - trailing:
        trailing += 1
    one_shot = note.loop is False
    counted = empty[:len(empty) - trailing] if one_shot else empty
    plays_once = one_shot
    if len(empty) == cells:
        report.problems.append("every cell is empty.")
    elif counted and note.loop is None and len(counted) == trailing:
        report.notes.append(f"the last {trailing} of {cells} cells are empty, which suits a one-shot; set \"loop\": false to confirm.")
        plays_once = True
    elif counted:
        report.problems.append(f"{len(counted)} of {cells} cells are empty ({indices(counted)}), so the animation blinks out.")
    if edge:
        report.problems.append(f"drawing reaches the edge of {len(edge)} cell(s) ({indices(edge)}), so those frames show a hard cut-off.")
    if repeats:
        report.notes.append(f"{len(repeats)} cell(s) repeat the one before ({indices(repeats)}); that wastes frames unless it is a deliberate hold.")
    settings = [f"FlipbookLayout = Grid{grid}x{grid}", f"FlipbookMode = {'OneShot' if plays_once else 'Loop'}", f"LightEmission = {1 if result.background == 'black' else 0}"]
    if note.fps > 0 and one_shot:
        settings.append(f"Lifetime = {round(cells / note.fps, 2):g}")
    elif note.fps > 0 and note.loop is True:
        settings.append(f"FlipbookFramerate = {min(30, round(note.fps))}")
    report.settings = ", ".join(settings)


def check_file(path: Path, grid: int | None, auto: bool) -> Report:
    report = Report(path)
    try:
        size = path.stat().st_size
        if size > MAX_FILE_BYTES:
            report.problems.append(f"{size // (1024 * 1024)} MB is over the {MAX_FILE_BYTES // (1024 * 1024)} MB limit of this check.")
            return report
        data = path.read_bytes()
        width, height = png_size(data)
        if max(width, height) > MAX_SIDE:
            report.summary = f"{width}x{height}"
            report.problems.append(f"over the {MAX_SIDE} px limit of this check; it was not decoded. Export it smaller.")
            return report
        image = decode(data)
    except (OSError, BadImage, struct.error) as error:
        report.problems.append(f"unreadable: {error}")
        return report
    report.image = image
    result = measure(image)
    note = read_note(path)
    sheet = grid is not None or auto or note is not None or path.name.lower().endswith(".flipbook.png")
    if note and note.warning:
        report.notes.append(note.warning)
    if sheet:
        check_sheet(report, image, result, note or Note(), grid)
    else:
        check_single(report, image, result)
    summary = [f"{image.width}x{image.height}", result.background]
    if report.grid:
        summary.append(f"{report.grid}x{report.grid} grid")
    if result.coverage:
        summary.append(f"{max(result.coverage * 100, 1 if result.coverage < 0.01 else 0):.0f}% drawn")
        summary.append(edge_label(result.soft))
    report.summary = ", ".join(summary)
    if result.coverage and min(result.average) < 200:  # the weakest channel: saturated orange can't turn blue either
        red, green, blue = (round(value) for value in result.average)
        report.notes.append(f"tinted, averaging rgb({red},{green},{blue}). Roblox multiplies Color by the texture, so white gives full control of the colour.")
    return report


TILE_FILL, CANVAS_FILL, GRID_LINE = (24, 24, 30), (12, 12, 15), (96, 96, 120)
GAP, SHEET_WIDTH = 6, 1536
DIGITS = {"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111", "4": "101101111001001",
          "5": "111100111001111", "6": "111100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001111"}


def paste_label(canvas: bytearray, width: int, left: int, top: int, text: str, scale: int):
    columns, rows = 4 * len(text) + 1, 7
    for y in range(rows * scale):
        start = (top + y) * width + left
        canvas[start * 3:(start + columns * scale) * 3] = bytes(columns * scale * 3)
    for place, digit in enumerate(text):
        for index, bit in enumerate(DIGITS[digit]):
            if bit == "1":
                for y in range(scale):
                    start = (top + scale + index // 3 * scale + y) * width + left + scale + (place * 4 + index % 3) * scale
                    canvas[start * 3:(start + scale) * 3] = b"\xff" * (scale * 3)


def draw_tile(canvas: bytearray, width: int, left: int, top: int, tile: int, image: Image, grid: int):
    scale = min(tile / image.width, tile / image.height)
    drawn_w, drawn_h = max(1, round(image.width * scale)), max(1, round(image.height * scale))
    offset_x, offset_y = left + (tile - drawn_w) // 2, top + (tile - drawn_h) // 2
    for y in range(tile):
        start = (top + y) * width + left
        canvas[start * 3:(start + tile) * 3] = bytes(TILE_FILL) * tile
    for y in range(drawn_h):
        source_y = min(image.height - 1, int((y + 0.5) / scale))
        row = bytearray()
        for x in range(drawn_w):
            r, g, b, a = image.rgba(min(image.width - 1, int((x + 0.5) / scale)), source_y)
            row += bytes((c * a + fill * (255 - a)) // 255 for c, fill in zip((r, g, b), TILE_FILL))
        start = (offset_y + y) * width + offset_x
        canvas[start * 3:(start + drawn_w) * 3] = row
    for step in range(1, grid):
        y = offset_y + step * drawn_h // grid
        start = y * width + offset_x
        canvas[start * 3:(start + drawn_w) * 3] = bytes(GRID_LINE) * drawn_w
        x = offset_x + step * drawn_w // grid
        for row_y in range(offset_y, offset_y + drawn_h):
            start = (row_y * width + x) * 3
            canvas[start:start + 3] = bytes(GRID_LINE)


def write_sheet(path: Path, reports: list[Report]):
    """A labelled contact sheet, for looking at many textures in one image."""
    shown = [(index + 1, report) for index, report in enumerate(reports) if report.image]
    if not shown:
        raise ValueError("no readable images for the contact sheet")
    count = len(shown)
    columns = max(1, min(4, math.ceil(math.sqrt(count))))
    rows = (count + columns - 1) // columns
    tile = min(512, (SHEET_WIDTH - GAP * (columns + 1)) // columns)
    step = tile + GAP
    width, height = columns * step + GAP, rows * step + GAP
    canvas = bytearray(bytes(CANVAS_FILL) * (width * height))
    scale = max(2, round(tile / 170))
    for position, (number, report) in enumerate(shown):
        left, top = GAP + position % columns * step, GAP + position // columns * step
        draw_tile(canvas, width, left, top, tile, report.image, report.grid)
        paste_label(canvas, width, left, top, str(number), scale)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encode(width, height, bytes(canvas)))


def collect(inputs: list[Path]) -> list[Path]:
    files = []
    for item in inputs:
        files.extend(sorted(item.glob("*.png"), key=lambda path: path.name.lower()) if item.is_dir() else [item])
    return files


def print_reports(reports: list[Report], numbered: bool):
    for index, report in enumerate(reports):
        label = f"#{index + 1} " if numbered else ""
        print(f"{label}{report.path.name}: {report.summary or 'not checked'}")
        for problem in report.problems:
            print(f"  problem: {problem}")
        for note in report.notes:
            print(f"  note: {note}")
        if report.settings:
            print(f"  ParticleEmitter: {report.settings}")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("inputs", nargs="+", type=Path, help="PNG files or folders of them")
    parser.add_argument("--grid", help="treat inputs as sheets: auto, 2, 4 or 8")
    parser.add_argument("--sheet", type=Path, help="write a labelled contact sheet to this PNG")
    parser.add_argument("--json", action="store_true", help="print one JSON object per file instead of text")
    args = parser.parse_args(argv)
    if args.grid not in (None, "auto", "2", "4", "8"):
        parser.error("--grid must be auto, 2, 4 or 8")
    files = collect(args.inputs)
    if not files:
        parser.error("no PNG files found")
    forced = int(args.grid) if args.grid and args.grid != "auto" else None
    reports = [check_file(path, forced, args.grid == "auto") for path in files]
    if args.sheet:
        try:
            write_sheet(args.sheet, reports)
        except (OSError, ValueError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
    if args.json:
        for report in reports:
            print(json.dumps({"file": str(report.path), "summary": report.summary, "grid": report.grid, "problems": report.problems, "notes": report.notes, "settings": report.settings}, ensure_ascii=False))
    else:
        print_reports(reports, bool(args.sheet))
    return 1 if any(report.problems for report in reports) else 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
