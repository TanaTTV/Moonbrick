"""Deterministic worlds for the V1.1 showcases (parts only; no uploaded assets)."""
import math
import random

from brawl_map import cframe, decor, light, part

SAND = [0.86, 0.71, 0.52]
SANDSTONE = [0.78, 0.6, 0.42]
SANDSTONE_DARK = [0.6, 0.43, 0.3]
PALE = [0.93, 0.86, 0.74]
GOLD = [0.85, 0.66, 0.3]
MESA = [0.72, 0.42, 0.26]


def _column(name, x, z, height, rng, fallen=False):
    pieces = []
    if fallen:
        angle = rng.uniform(0, 360)
        pieces.append(part(f"{name}Drum", [x, 2.6, z], [height, 3.2, 3.2], SANDSTONE, "Sandstone", "Part", rotation=(angle, 0, 90), Shape="Cylinder"))
        return pieces
    pieces.append(part(f"{name}Base", [x, 1.5, z], [4.6, 1, 4.6], SANDSTONE_DARK, "Sandstone"))
    pieces.append(part(f"{name}Shaft", [x, 2 + height / 2, z], [height, 3.2, 3.2], SANDSTONE, "Sandstone", "Part", rotation=(0, 0, 90), Shape="Cylinder"))
    if height > 9:
        pieces.append(part(f"{name}Cap", [x, 2.5 + height, z], [4.4, 1, 4.4], SANDSTONE_DARK, "Sandstone"))
    else:
        # A broken top: a tilted chunk.
        pieces.append(part(f"{name}Break", [x + 0.3, 2.3 + height, z], [3, 1.2, 2.6], SANDSTONE, "Sandstone", rotation=(rng.uniform(0, 90), rng.uniform(-14, 14), rng.uniform(-10, 10))))
    return pieces


def _ring(name, centre, radius, tilt, yaw, count, size, color, material):
    pieces = []
    for i in range(count):
        a = i / count * 2 * math.pi
        local = [math.cos(a) * radius, math.sin(a) * radius, 0.0]
        # Tilt about X, then yaw about Y.
        ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
        x, y, z = local[0], local[1] * ct, local[1] * st
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        x, z = x * cy + z * sy, -x * sy + z * cy
        pieces.append(decor(f"{name}{i}", [centre[0] + x, centre[1] + y, centre[2] + z], size, color, material,
                            rotation=(yaw, tilt, math.degrees(a))))
    return pieces


def collapse_world():
    rng = random.Random(21)
    children = [
        part("Desert", [0, -1, 0], [600, 2, 600], SAND, "Sand"),
        part("Terrace", [0, 0.5, 0], [1, 72, 72], SANDSTONE, "Sandstone", "Part", rotation=(0, 0, 90), Shape="Cylinder"),
        part("Inlay", [0, 0.56, 0], [1, 46, 46], PALE, "Limestone", "Part", rotation=(0, 0, 90), Shape="Cylinder"),
        # A thin gold ring: just wider than the inlay and just below its surface, so only the rim shows.
        decor("InlayTrim", [0, 0.53, 0], [1, 47.4, 47.4], GOLD, "Metal", "Part", rotation=(0, 0, 90), Shape="Cylinder"),
    ]
    # Steps down from the terrace toward the targets.
    for i in range(3):
        children.append(part(f"Step{i}", [0, 0.5 - i * 0.33, -37 - i * 2.4], [26 - i * 2, 1, 3], SANDSTONE_DARK, "Sandstone"))
    # Broken colonnade around the rim.
    for i in range(12):
        a = i / 12 * 2 * math.pi + 0.13
        x, z = math.cos(a) * 31, math.sin(a) * 31
        if z < -18 and abs(x) < 14:
            continue  # keep the view to the targets open
        fallen = i in (3, 8)
        children += _column(f"Column{i}", x, z, rng.uniform(7, 14), rng, fallen)
    # Armillary sculpture: the focal point behind the caster.
    centre = [0, 13, 25]
    children.append(part("Pedestal", [0, 3.5, 25], [6, 6, 6], SANDSTONE_DARK, "Sandstone"))
    children.append(decor("Globe", centre, [3.4, 3.4, 3.4], [0.98, 0.9, 0.7], "Neon", Shape="Ball", Transparency=0.05))
    children[-1]["children"] = [light([1.0, 0.86, 0.6], 1.2, 26)]
    for k, (tilt, yaw) in enumerate(((90, 0), (90, 60), (25, 0))):
        children += _ring(f"Ring{k}_", centre, 6.5 - k * 0.6, tilt, yaw, 28, [1.2, 0.4, 0.4], GOLD, "Metal")
    # Scattered rubble and a wind-worn obelisk.
    for i in range(16):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(38, 70)
        s = rng.uniform(1.2, 3.5)
        children.append(part(f"Rubble{i}", [math.cos(a) * r, s * 0.35, math.sin(a) * r], [s, s * 0.7, s * 1.2], SANDSTONE, "Sandstone",
                             rotation=(rng.uniform(0, 360), rng.uniform(-20, 20), rng.uniform(-15, 15))))
    children.append(part("Obelisk", [-46, 11, 18], [3.5, 22, 3.5], SANDSTONE_DARK, "Sandstone", rotation=(12, 0, 4)))
    world = {"className": "Model", "children": children}

    backdrop = []
    for i in range(9):
        a = i / 9 * 2 * math.pi + 0.4
        r = rng.uniform(190, 280)
        x, z = math.cos(a) * r, math.sin(a) * r
        w, h = rng.uniform(50, 100), rng.uniform(26, 52)
        yaw = rng.uniform(0, 90)
        # Stacked, tapering strata read as eroded mesas rather than boxes.
        y = -2
        for layer in range(4):
            lh = h * (0.34, 0.28, 0.22, 0.16)[layer]
            lw = w * (1.0, 0.86, 0.74, 0.66)[layer]
            color = MESA if layer % 2 == 0 else SANDSTONE_DARK
            backdrop.append(decor(f"Mesa{i}_{layer}", [x, y + lh / 2, z], [lw, lh, lw * 0.62], color, "Sandstone",
                                  rotation=(yaw + layer * 3, 0, 0)))
            y += lh
        backdrop.append(decor(f"Talus{i}", [x + w * 0.35, 3, z], [w * 0.4, 10, w * 0.3], SANDSTONE, "Sandstone",
                              rotation=(yaw, 0, 18)))
    return world, {"className": "Model", "children": backdrop}


def collapse_lighting():
    return {
        "$className": "Lighting",
        "$ignoreUnknownInstances": True,
        "$properties": {
            "ClockTime": 17.75,
            "GeographicLatitude": 30,
            "Brightness": 2.6,
            "Ambient": [0.36, 0.3, 0.28],
            "OutdoorAmbient": [0.56, 0.48, 0.42],
            "EnvironmentDiffuseScale": 0.7,
            "EnvironmentSpecularScale": 0.6,
        },
        "TerraceAtmosphere": {"$className": "Atmosphere", "$properties": {
            "Density": 0.34, "Offset": 0.05, "Color": [1.0, 0.82, 0.62], "Decay": [0.86, 0.56, 0.4], "Glare": 0.4, "Haze": 1.8,
        }},
        "TerraceBloom": {"$className": "BloomEffect", "$properties": {"Intensity": 0.2, "Size": 24, "Threshold": 1.4}},
        "TerraceGrade": {"$className": "ColorCorrectionEffect", "$properties": {"Saturation": 0.08, "Contrast": 0.06, "TintColor": [1, 0.97, 0.93]}},
    }
