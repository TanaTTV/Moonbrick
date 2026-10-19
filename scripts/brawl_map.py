"""Deterministic Sky Shrine stage for the Element Brawl example: parts only, no uploaded assets."""
import math
import random

FIRE = [1.0, 0.41, 0.18]
ICE = [0.43, 0.84, 1.0]
STORM = [0.69, 0.47, 1.0]
WIND = [0.47, 0.94, 0.67]
STONE = [0.42, 0.38, 0.47]
ROCK = [0.24, 0.21, 0.31]
ROCK_DARK = [0.17, 0.15, 0.24]
GRASS = [0.27, 0.47, 0.43]
MARBLE = [0.9, 0.88, 0.95]


def cframe(position, yaw=0.0, pitch=0.0, roll=0.0):
    """Rojo CFrame list from a position and Y/X/Z rotations in degrees (applied yaw, then pitch, then roll)."""
    y, x, z = (math.radians(a) for a in (yaw, pitch, roll))
    cy, sy, cx, sx, cz, sz = math.cos(y), math.sin(y), math.cos(x), math.sin(x), math.cos(z), math.sin(z)
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    m = mul(mul(ry, rx), rz)
    return [*position, *(round(v, 6) for row in m for v in row)]


def part(name, position, size, color, material="SmoothPlastic", class_name="Part", rotation=(0, 0, 0), **props):
    properties = {"Anchored": True, "Size": size, "CFrame": cframe(position, *rotation), "Color": color, "Material": material}
    properties.update(props)
    return {"name": name, "className": class_name, "properties": properties}


def light(color, brightness=1.0, range_=12):
    return {"name": "Glow", "className": "PointLight", "properties": {"Color": color, "Brightness": brightness, "Range": range_, "Shadows": False}}


def decor(name, position, size, color, material="SmoothPlastic", class_name="Part", rotation=(0, 0, 0), **props):
    # Scenery never collides with fighters or blocks their launches.
    return part(name, position, size, color, material, class_name, rotation, CanCollide=False, CanQuery=False, CanTouch=False, **props)


def stage():
    children = [
        part("Stage", [0, -2.5, 0], [92, 5, 26], STONE, "Slate"),
        part("Grass", [0, -0.3, 0], [93, 0.6, 27], GRASS, "Grass"),
    ]
    # The island tapers underneath into a rocky point: tilted chunks narrowing toward the tip, with hanging crystals.
    rng = random.Random(11)
    children.append(decor("UndersideRim", [0, -6.5, 0], [88, 5, 24], ROCK, "Rock"))
    for i in range(26):
        t = rng.uniform(0, 1)
        spread, width = (1 - t) * 40 + 4, (1 - t) * 26 + 6
        position = [rng.uniform(-spread, spread), -11 - t * 30, rng.uniform(-8, 8) * (1 - t)]  # tops stay under the stage
        size = [width * rng.uniform(0.6, 1.1), rng.uniform(6, 12), width * rng.uniform(0.4, 0.8)]
        rotation = (rng.uniform(0, 90), rng.uniform(-25, 25), rng.uniform(-20, 20))
        children.append(decor(f"Underside{i}", position, size, ROCK_DARK if i % 3 == 0 else ROCK, "Rock", rotation=rotation))
    for i in range(8):
        x = rng.uniform(-34, 34)
        position = [x, -24 - rng.uniform(0, 10), rng.uniform(-6, 6)]
        size = [2, rng.uniform(5, 9), 2]
        color = (FIRE, ICE, STORM, WIND)[i % 4]
        children.append(decor(f"UnderCrystal{i}", position, size, color, "Neon", rotation=(rng.uniform(0, 90), 180 + rng.uniform(-15, 15), 0), Transparency=0.05))
    # Back rim and a moon emblem in the centre of the stage.
    children.append(decor("RimBack", [0, 0.2, -13.2], [93, 1.2, 1.2], MARBLE, "Marble"))
    children.append(decor("Emblem", [0, 0.05, 0], [0.2, 16, 16], [1.0, 0.94, 0.84], "Neon", rotation=(0, 0, 90), Shape="Cylinder", Transparency=0.55))
    children.append(decor("EmblemInner", [0, 0.08, 0], [0.2, 12, 12], [0.24, 0.2, 0.35], "Slate", rotation=(0, 0, 90), Shape="Cylinder"))
    crystal = decor("CoreCrystal", [0, -46, 0], [5, 14, 5], STORM, "Neon", "WedgePart", rotation=(45, 180, 0), Transparency=0.1)
    crystal["children"] = [light(STORM, 1.5, 30)]
    children.append(crystal)
    # Ledge trims glow in the four element colours.
    for name, x, color in (("TrimFire", -45.6, FIRE), ("TrimIce", 45.6, ICE)):
        trim = decor(name, [x, -0.5, 0], [0.8, 1.2, 27], color, "Neon")
        children.append(trim)
    children.append(decor("TrimWindFront", [0, -0.6, 13.6], [92, 0.8, 0.6], WIND, "Neon"))
    # Floating platforms: Fire left, Ice right, Storm on top.
    for name, position, color in (("FirePlatform", [-26, 16, 0], FIRE), ("IcePlatform", [26, 16, 0], ICE), ("StormPlatform", [0, 32, 0], STORM)):
        children.append(part(name, position, [22, 1.6, 12], MARBLE, "Marble"))
        glow = decor(name + "Glow", [position[0], position[1] - 1.1, 0], [20, 0.5, 10], color, "Neon")
        glow["children"] = [light(color, 0.7, 16)]
        children.append(glow)
    # Element shrines along the back edge, behind the fighting plane.
    for i, (x, color, shape) in enumerate(((-36, FIRE, "Ball"), (-12, ICE, "Block"), (12, STORM, "Wedge"), (36, WIND, "Ball"))):
        children.append(part(f"Pillar{i}", [x, 5, -9.5], [3.4, 10, 3.4], MARBLE, "Marble"))
        children.append(part(f"PillarCap{i}", [x, 10.4, -9.5], [5, 0.8, 5], STONE, "Slate"))
        if shape == "Ball":
            gem = decor(f"Gem{i}", [x, 13.2, -9.5], [3.6, 3.6, 3.6], color, "Neon", Shape="Ball")
        elif shape == "Wedge":
            gem = decor(f"Gem{i}", [x, 13.4, -9.5], [3, 4.4, 3], color, "Neon", "WedgePart", rotation=(45, 0, 0))
        else:
            gem = decor(f"Gem{i}", [x, 13.2, -9.5], [3, 3, 3], color, "Neon", rotation=(45, 35, 0))
        gem["children"] = [light(color, 1.0, 18)]
        children.append(gem)
    return {"className": "Model", "children": children}


def backdrop():
    children = [decor("Moon", [-420, 380, -1100], [200, 200, 200], [1.0, 0.94, 0.84], "Neon", Shape="Ball", Transparency=0.12)]
    # Distant floating islands at different depths give the side camera parallax.
    islands = ((-160, 30, -220, 1.0), (190, -10, -260, 1.3), (-60, 80, -340, 0.8), (110, 60, -180, 0.6), (-230, -40, -300, 1.1))
    for i, (x, y, z, s) in enumerate(islands):
        children.append(decor(f"Island{i}", [x, y, z], [46 * s, 9 * s, 30 * s], STONE, "Slate"))
        children.append(decor(f"IslandGrass{i}", [x, y + 4.6 * s, z], [47 * s, 1.2 * s, 31 * s], GRASS, "Grass"))
        children.append(decor(f"IslandRock{i}", [x, y - 12 * s, z], [26 * s, 16 * s, 18 * s], ROCK, "Rock", rotation=(i * 30, 0, 8)))
        children.append(decor(f"IslandSpire{i}", [x + 9 * s, y + 13 * s, z], [5 * s, 16 * s, 5 * s], MARBLE, "Marble"))
    # A moonlit cloud sea far below: clusters of puffs rather than single stretched balls.
    rng = random.Random(7)
    for i in range(22):
        center = [-320 + i * 30 + rng.uniform(-10, 10), -160 + rng.uniform(-8, 8), -180 - rng.uniform(0, 220)]
        for j in range(4):
            size = rng.uniform(40, 75) * 0.75
            position = [center[0] + rng.uniform(-35, 35), center[1] + rng.uniform(-6, 10), center[2] + rng.uniform(-25, 25)]
            children.append(decor(f"Cloud{i}_{j}", position, [size, size, size], [1.0, 0.89, 0.93], Shape="Ball", Transparency=0.1, CastShadow=False))
    return {"className": "Model", "children": children}


def lighting():
    return {
        "$className": "Lighting",
        "$ignoreUnknownInstances": True,
        "$properties": {
            "ClockTime": 18.35,
            "Brightness": 2,
            "Ambient": [0.27, 0.22, 0.34],
            "OutdoorAmbient": [0.5, 0.42, 0.55],
            "EnvironmentDiffuseScale": 0.6,
            "EnvironmentSpecularScale": 0.8,
        },
        "ShrineAtmosphere": {"$className": "Atmosphere", "$properties": {
            "Density": 0.3, "Offset": 0.2, "Color": [1.0, 0.67, 0.63], "Decay": [0.43, 0.27, 0.59], "Glare": 0.6, "Haze": 1.6,
        }},
        "ShrineBloom": {"$className": "BloomEffect", "$properties": {"Intensity": 0.35, "Size": 26, "Threshold": 1.15}},
        "ShrineGrade": {"$className": "ColorCorrectionEffect", "$properties": {"Saturation": 0.18, "Contrast": 0.08, "TintColor": [1, 0.97, 0.98]}},
        "ShrineSunRays": {"$className": "SunRaysEffect", "$properties": {"Intensity": 0.06, "Spread": 0.6}},
    }
