"""Neon Frontier: one main street of a desert boomtown that got wired (parts only; no uploaded assets).

Facades are plain parts; props (cacti, water tower, barrels, hoverbike, dish, pylons) are Geo spots the
client dresses; signs are parts with a `Sign` attribute the client turns into flickering neon lettering.
Few distinct shape variants keep the client's mesh count low.
"""
import math
import random

from brawl_map import decor, part
from showcase_maps import _spot

DUST = [0.62, 0.45, 0.36]
ROAD = [0.34, 0.28, 0.3]
BOARD = [0.42, 0.3, 0.22]
TIMBER = [0.32, 0.22, 0.17]
PAINT = ([0.55, 0.36, 0.26], [0.25, 0.38, 0.4], [0.5, 0.44, 0.32], [0.36, 0.26, 0.34])
CYAN = [0.2, 0.95, 1.0]
MAGENTA = [1.0, 0.24, 0.72]
AMBER = [1.0, 0.62, 0.2]
WINDOW = [1.0, 0.72, 0.42]


def _facade(name, side, z, width, height, paint, rng):
    """A false-front building on one side of the street (side -1 left, 1 right), facing the road."""
    x = side * 19
    face_x = side * 14
    pieces = [
        part(f"{name}Body", [x, height / 2, z], [10, height, width], paint, "WoodPlanks"),
        part(f"{name}Front", [face_x + side * 0.3, height + 1.6, z], [0.6, 3.2, width * 0.8], paint, "WoodPlanks"),
        decor(f"{name}Trim", [face_x - side * 0.05, height + 3.25, z], [0.8, 0.3, width * 0.84], TIMBER, "Wood"),
        # Awning over the boardwalk.
        decor(f"{name}Awning", [side * 11.6, 6.2, z], [5.2, 0.3, width], TIMBER, "Wood", rotation=(0, 0, side * -8)),
    ]
    for k, dz in enumerate((-width / 2 + 0.4, width / 2 - 0.4)):
        pieces.append(part(f"{name}Post{k}", [side * 9.4, 3, z + dz], [0.4, 6, 0.4], TIMBER, "Wood"))
    # Glowing windows (street level and upper floor) and a dark door.
    for k, dz in enumerate((-width / 4, width / 4)):
        # Warm lamplight inside; neon is saved for the signs (one cool window in four for variety).
        glow = rng.choice((WINDOW, WINDOW, WINDOW, [0.45, 0.85, 0.95]))
        pieces.append(decor(f"{name}Window{k}", [face_x - side * 0.02, 4.2, z + dz], [0.2, 1.8, 1.6], glow, "Neon", Transparency=0.62))
        pieces.append(decor(f"{name}Upper{k}", [face_x - side * 0.02, height - 2.4, z + dz], [0.2, 1.4, 1.2], glow, "Neon", Transparency=0.7))
    pieces.append(decor(f"{name}Door", [face_x - side * 0.02, 2, z], [0.2, 4, 2.4], [0.12, 0.1, 0.12], "Wood"))
    return pieces


def _sign(name, text, position, size, color, flicker=0.0, vertical=False, yaw=0):
    """A dark backing plate; the client adds the neon lettering on both faces."""
    sign = decor(name, position, size, [0.08, 0.07, 0.1], "Metal", rotation=(yaw, 0, 0))
    sign["attributes"] = {"Sign": text, "SignR": color[0], "SignG": color[1], "SignB": color[2],
                          "Flicker": flicker, "Vertical": vertical}
    return sign


def frontier_world():
    rng = random.Random(11)
    children = [
        part("Desert", [0, -1, 0], [500, 2, 500], DUST, "Sand"),
        part("Road", [0, 0.02, 0], [16, 0.1, 130], ROAD, "Asphalt"),
    ]
    for side in (-1, 1):
        children.append(part(f"Boardwalk{side}", [side * 11.5, 0.45, 0], [5, 0.5, 120], BOARD, "WoodPlanks"))
    signs = {
        (-1, 0): ("SALOON", MAGENTA, 0.0), (1, 0): ("BOUNTIES", CYAN, 0.0), (-1, 1): ("NOODLES", AMBER, 0.6),
        (1, 1): ("HOTEL", MAGENTA, 0.2), (-1, 2): ("REPAIRS", CYAN, 0.9), (1, 3): ("SHERIFF", AMBER, 0.0),
    }
    for side in (-1, 1):
        z = 40
        for i in range(6):
            width = rng.choice((10, 12, 14))
            if side == 1 and i == 2:
                z -= 9  # the alley with the bounty board
                continue
            height = rng.uniform(8, 12)
            centre = z - width / 2
            children += _facade(f"House{side}_{i}", side, centre, width, height, PAINT[(i + (side > 0)) % 4], rng)
            if (side, i) in signs:
                text, color, flicker = signs[(side, i)]
                # Mounted on the false front, facing the street.
                children.append(_sign(f"Sign{side}_{i}", text, [side * 13.5, height + 1.6, centre],
                                      [0.25, 2.2, width * 0.72], color, flicker))
            z -= width + 1
    # A blade sign over the left boardwalk, perpendicular to the street so it reads down the road.
    children.append(_sign("BladeSign", "GAS", [-10.4, 7.6, 14], [0.3, 6, 1.8], CYAN, 0.3, vertical=True, yaw=90))
    board = part("BountyBoard", [12.2, 2.8, -10], [0.4, 3.4, 4.6], TIMBER, "Wood")
    board["children"] = [{"name": "Prompt", "className": "ProximityPrompt", "properties": {
        "ActionText": "Read bounties", "ObjectText": "Board", "MaxActivationDistance": 12.0, "HoldDuration": 0.0}}]
    children.append(board)
    children.append(_spot("BoardLamp", "Lamp", [11.8, 5.2, -10], [0.9, 1.1, 0.9], CYAN, "Neon"))
    for i in range(10):
        side = -1 if i % 2 else 1
        children.append(_spot(f"Barrel{i}", "Barrel", [side * rng.uniform(10, 13), 1.8, rng.uniform(-50, 40)],
                              [1.6, 2.2, 1.6], rng.choice(([0.45, 0.28, 0.2], [0.3, 0.32, 0.36])), "CorrodedMetal",
                              rotation=(rng.uniform(0, 360), 0, 0), collide=True))
    children.append(_spot("Hoverbike", "Hoverbike", [4.5, 2.2, 8], [3.2, 2.4, 9], [1, 1, 1], rotation=(-12, 0, 0), collide=True))
    for i in range(6):
        children.append(_spot(f"Pylon{i}", "Pylon", [-17.5, 9, 45 - i * 18], [3, 18, 1.2], [0.2, 0.2, 0.22], "Metal", collide=True))
    children.append(_spot("WaterTower", "WaterTower", [-6, 11, -68], [12, 22, 12], [1, 1, 1], collide=True))
    children.append(_spot("Dish", "Dish", [10, 12, -60], [8, 8, 8], [0.75, 0.75, 0.78], "Metal", rotation=(150, -30, 0)))
    for i in range(16):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(28, 70)
        x, z = math.cos(a) * r, math.sin(a) * r
        if abs(x) < 26:
            x = math.copysign(rng.uniform(26, 40), x or 1)
        h = rng.uniform(4, 9)
        children.append(_spot(f"Cactus{i}", "Cactus", [x, h / 2, z], [h * 0.6, h, h * 0.6], [1, 1, 1],
                              rotation=(rng.uniform(0, 360), 0, 0), collide=True, Seed=i % 3 + 1))
    world = {"className": "Model", "children": children}

    backdrop = []
    for i in range(10):
        a = i / 10 * 2 * math.pi + 0.2
        r = rng.uniform(170, 240)
        x, z = math.cos(a) * r, math.sin(a) * r
        w, h = rng.uniform(40, 90), rng.uniform(20, 45)
        y = -2
        for layer in range(3):
            lh = h * (0.45, 0.33, 0.22)[layer]
            lw = w * (1.0, 0.82, 0.66)[layer]
            backdrop.append(decor(f"Butte{i}_{layer}", [x, y + lh / 2, z], [lw, lh, lw * 0.6],
                                  [0.36, 0.2, 0.22] if layer % 2 == 0 else [0.28, 0.16, 0.2], "Sandstone",
                                  rotation=(rng.uniform(0, 90), 0, 0)))
            y += lh
    # A holo-billboard on the horizon at the end of the street, facing the town.
    backdrop.append(_sign("Billboard", "NEO\nSARSAPARILLA", [0, 38, -125], [40, 16, 0.4], MAGENTA, 0.1, yaw=0))
    return world, {"className": "Model", "children": backdrop}


def frontier_lighting():
    return {
        "$className": "Lighting",
        "$ignoreUnknownInstances": True,
        "$properties": {
            "ClockTime": 17.85,
            "GeographicLatitude": 25,
            "Brightness": 2.4,
            "Ambient": [0.44, 0.32, 0.42],
            "OutdoorAmbient": [0.58, 0.42, 0.5],
            "EnvironmentDiffuseScale": 0.5,
            "EnvironmentSpecularScale": 0.8,
        },
        "FrontierAtmosphere": {"$className": "Atmosphere", "$properties": {
            "Density": 0.36, "Offset": 0.12, "Color": [0.84, 0.5, 0.54], "Decay": [0.42, 0.22, 0.46], "Glare": 0.6, "Haze": 2.4,
        }},
        "FrontierBloom": {"$className": "BloomEffect", "$properties": {"Intensity": 0.7, "Size": 30, "Threshold": 1.0}},
        "FrontierGrade": {"$className": "ColorCorrectionEffect", "$properties": {"Saturation": 0.18, "Contrast": 0.12, "TintColor": [1, 0.94, 0.98]}},
    }
