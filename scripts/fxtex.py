"""Render Moonbrick's effect textures (the same shapes `Kit.Tex` draws at runtime) as PNG files.

ParticleEmitter, Beam and Trail textures can't use runtime EditableImages (verified in Studio
0.743: accepted, not rendered), so they need files:

    python scripts/fxtex.py list
    python scripts/fxtex.py render <out-dir> [name ...]      # PNGs, white with alpha
    python scripts/fxtex.py preview <out-dir>                 # copy into Studio's local content folder

After `preview`, `Tex.usePreview()` in your client points particles at
`rbxasset://textures/moonbrick/<name>.png` — Studio on THIS computer only. To ship, upload the PNGs
yourself (Creator Hub → Decals/Images) and pass the ids to `Tex.useFiles({ spark = "rbxassetid://…" })`.
Standard library only (zlib + struct PNG writer).
"""
from __future__ import annotations

import argparse
import glob
import math
import os
from pathlib import Path
import shutil
import struct
import zlib

# name -> (options, flipbook grid)
TEXTURES = {
    "glow": ({}, 1),
    "core": ({}, 1),
    "ring": ({}, 1),
    "spark": ({}, 1),
    "star": ({}, 1),
    "streak": ({}, 1),
    "smoke": ({}, 4),
    "dust": ({}, 1),
    "shard": ({}, 1),
    "crack": ({}, 1),
    "wisp": ({}, 4),
}


def _hash(x, y, seed):
    n = math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453
    return n - math.floor(n)


def _smooth(t):
    return t * t * (3 - 2 * t)


def _noise1(x, y, seed):
    xi, yi = math.floor(x), math.floor(y)
    xf, yf = x - xi, y - yi
    a, b = _hash(xi, yi, seed), _hash(xi + 1, yi, seed)
    c, d = _hash(xi, yi + 1, seed), _hash(xi + 1, yi + 1, seed)
    u, v = _smooth(xf), _smooth(yf)
    return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v


def noise(x, y, seed=0, octaves=4):
    total, amplitude, frequency, norm = 0.0, 1.0, 1.0, 0.0
    for _ in range(octaves):
        total += _noise1(x * frequency, y * frequency, seed) * amplitude
        norm += amplitude
        amplitude *= 0.5
        frequency *= 2
    return total / norm


def _falloff(d, softness):
    if d >= 1:
        return 0.0
    return max(0.0, min(1.0, (1 - d) / max(softness, 1e-3)))


def _clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def alpha(name, u, v, opts=None, frame=0.0):
    """Same maths as `Tex.alpha` in luau/lib/shared/Tex.luau (kept in sync by tests)."""
    o = opts or {}
    seed = o.get("seed", 1)
    t = frame
    r = math.sqrt(u * u + v * v)
    angle = math.atan2(v, u)
    if name == "glow":
        return (1 - _clamp(r)) ** 2.2
    if name == "core":
        return _falloff(r, o.get("softness", 0.35)) ** 0.8
    if name == "ring":
        width = o.get("thickness", 0.14)
        d = abs(r - (0.86 - width)) / width
        return _falloff(d, o.get("softness", 0.8)) * (1 if r < 1 else 0)
    if name in ("spark", "star"):
        points = o.get("points", 4 if name == "spark" else 6)
        spikes = abs(math.cos(angle * points / 2)) ** (18 if name == "spark" else 8)
        arm = _falloff(r, 1) ** 1.5 * spikes
        centre = (1 - _clamp(r * 3.2)) ** 2
        return _clamp(arm + centre)
    if name == "streak":
        width = o.get("thickness", 0.12)
        along = 1 - _clamp(abs(u))
        across = _falloff(abs(v) / width, 0.9)
        return across * along ** 0.6
    if name == "smoke":
        grow = 0.55 + 0.4 * t
        n = noise(u * 2.2 + seed, v * 2.2 - t * 1.5, seed, 4)
        shape = _falloff(r / grow, 0.6) * (0.45 + 0.75 * n)
        return _clamp(shape * (1 - t * 0.85))
    if name == "dust":
        n = noise(u * 6 + seed, v * 6, seed, 3)
        return _clamp(_falloff(r, 0.9) * (n - 0.35) * 2.2)
    if name == "shard":
        d = abs(u) / 0.32 + abs(v) / 0.98
        return _falloff(d, 0.12)
    if name == "crack":
        branches = 7
        wobble = (noise(r * 4, angle * 2, seed, 2) - 0.5) * 0.5
        line = abs(math.sin((angle + wobble) * branches / 2))
        thin = 1 - _clamp(line / (0.06 + 0.08 * (1 - r)))
        return thin * _falloff(r, 0.5)
    if name == "wisp":
        swirl = math.sin(angle * 2 + r * 7 - t * 6.28 + seed)
        band = 1 - _clamp(abs(swirl) / 0.35)
        return band * _falloff(r, 0.7) * (0.6 + 0.4 * noise(u * 3, v * 3, seed, 2))
    return _falloff(r, 0.5)


def _png(path: Path, side: int, rows: list[bytes]):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", side, side, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def render_one(name: str, out: Path, cell: int = 128) -> Path:
    opts, grid = TEXTURES[name]
    side = cell * grid
    rows = []
    for py in range(side):
        gy, y = divmod(py, cell)
        row = bytearray()
        v = (y + 0.5) / cell * 2 - 1
        for px in range(side):
            gx, x = divmod(px, cell)
            u = (x + 0.5) / cell * 2 - 1
            frame = (gy * grid + gx) / (grid * grid - 1) if grid > 1 else 0.0
            a = int(_clamp(alpha(name, u, v, opts, frame)) * 255 + 0.5)
            row += bytes((255, 255, 255, a))
        rows.append(bytes(row))
    path = out / f"{name}.png"
    _png(path, side, rows)
    return path


def render(out: Path, names: list[str]) -> list[Path]:
    out.mkdir(parents=True, exist_ok=True)
    written = []
    for name in names or list(TEXTURES):
        if name not in TEXTURES:
            raise SystemExit(f"unknown texture {name!r}; try: {', '.join(TEXTURES)}")
        path = render_one(name, out)
        written.append(path)
        print(f"{path} ({TEXTURES[name][1]}x{TEXTURES[name][1]} grid)")
    return written


def studio_texture_dirs() -> list[str]:
    dirs = []
    local = os.environ.get("LOCALAPPDATA")
    if local:
        dirs += sorted(glob.glob(os.path.join(local, "Roblox", "Versions", "*", "content", "textures")))
    for mac in ("/Applications/RobloxStudio.app/Contents/Resources/content/textures",
                os.path.expanduser("~/Applications/RobloxStudio.app/Contents/Resources/content/textures")):
        if os.path.isdir(mac):
            dirs.append(mac)
    return dirs


def preview(out: Path):
    files = sorted(out.glob("*.png"))
    if not files:
        raise SystemExit(f"no PNGs in {out}; run render first")
    dirs = studio_texture_dirs()
    if not dirs:
        raise SystemExit("Roblox Studio's content/textures folder was not found")
    for root in dirs:
        target = Path(root) / "moonbrick"
        target.mkdir(exist_ok=True)
        for f in files:
            shutil.copyfile(f, target / f.name)
    for f in files:
        print(f"{f.name} -> rbxasset://textures/moonbrick/{f.name}")
    print("Local Studio preview only. Studio updates replace this folder: re-run preview after updating.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    r = sub.add_parser("render")
    r.add_argument("out", type=Path)
    r.add_argument("names", nargs="*")
    p = sub.add_parser("preview")
    p.add_argument("out", type=Path)
    args = parser.parse_args(argv)
    if args.command == "list":
        for name, (_, grid) in TEXTURES.items():
            print(f"{name}{' (flipbook ' + str(grid) + 'x' + str(grid) + ')' if grid > 1 else ''}")
    elif args.command == "render":
        render(args.out, args.names)
    else:
        preview(args.out)


if __name__ == "__main__":
    main()
