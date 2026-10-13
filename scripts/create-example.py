"""Create a playable Crystal Rush project without installing tools, uploading assets or starting Studio."""
import argparse
import json
from pathlib import Path
import shutil

from project import new_project

ROOT = Path(__file__).resolve().parents[1]


def part(name, position, size, color, material="SmoothPlastic", class_name="Part"):
    return {"name": name, "className": class_name, "properties": {"Anchored": True, "Size": size, "CFrame": [*position, 1, 0, 0, 0, 1, 0, 0, 0, 1], "Color": color, "Material": material}}


def create(target):
    new_project(target, "Crystal Rush")
    example = ROOT / "examples/crystal-rush"
    for folder in ("src", "tests"):
        shutil.copytree(example / folder, target / folder, dirs_exist_ok=True)
    children = [part("Floor", [0, 0, 0], [80, 1, 80], [0.14, 0.18, 0.28]), part("Spawn", [0, 2, -25], [8, 1, 8], [0.5, 0.71, 0.78], class_name="SpawnLocation")]
    crystals = []
    for index, (x, z) in enumerate(((-18, -15), (0, -12), (18, -15), (-24, 4), (0, 0), (24, 4), (-16, 20), (0, 24), (16, 20))):
        crystal = part(f"Crystal{index + 1}", [x, 3, z], [3, 5, 3], [0.65, 0.54, 0.91], "Neon")
        crystal["properties"]["CanCollide"] = False
        crystal["children"] = [{"name": "Collect", "className": "ProximityPrompt", "properties": {"ActionText": "Collect", "ObjectText": "Moon crystal", "HoldDuration": 0, "MaxActivationDistance": 8, "RequiresLineOfSight": True}}, {"name": "Glow", "className": "PointLight", "properties": {"Color": [1, 0.84, 0.52], "Brightness": 0.8, "Range": 10}}]
        crystals.append(crystal)
    children.append({"name": "Crystals", "className": "Folder", "children": crystals})
    for index, (x, z) in enumerate(((-28, -20), (28, -20), (-30, 25), (30, 25))):
        children.append(part(f"Landmark{index}", [x, 4, z], [7, 7, 7], [0.5, 0.71, 0.78]))
    world = {"className": "Model", "children": children}
    (target / "src/world/Arena.model.json").write_text(json.dumps(world, indent=2) + "\n", encoding="utf-8", newline="\n")
    shutil.copyfile(example / "README.md", target / "EXAMPLE.md")
    (target / "assets").mkdir()
    shutil.copyfile(ROOT / "assets/art.example.json", target / "assets/art.json")
    print(f"Crystal Rush created at {target}. Run tools/check.sh, build/connect Rojo, then test in a dedicated place.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=Path)
    create(parser.parse_args().target)
