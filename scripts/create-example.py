"""Create a playable example project (Crystal Rush or Element Brawl) without installing tools, uploading assets or starting Studio."""
import argparse
import json
from pathlib import Path
import shutil

from project import new_project
import brawl_map
import frontier_map
import showcase_maps

ROOT = Path(__file__).resolve().parents[1]


def part(name, position, size, color, material="SmoothPlastic", class_name="Part"):
    return {"name": name, "className": class_name, "properties": {"Anchored": True, "Size": size, "CFrame": [*position, 1, 0, 0, 0, 1, 0, 0, 0, 1], "Color": color, "Material": material}}


def create(target):
    new_project(target, "Crystal Rush")
    example = ROOT / "examples/crystal-rush"
    for folder in ("src", "tests"):
        shutil.copytree(example / folder, target / folder, dirs_exist_ok=True)
    project_path = target / "default.project.json"
    project = json.loads(project_path.read_text(encoding="utf-8"))
    # The arena is 80 studs wide: retain nearby pickups, target the whole small map.
    project["tree"]["Workspace"]["$properties"] = {
        "StreamingEnabled": True, "StreamingMinRadius": 64, "StreamingTargetRadius": 128,
    }
    project["tree"]["Lighting"] = {
        "$className": "Lighting", "$ignoreUnknownInstances": True,
        "CrystalBloom": {"$className": "BloomEffect", "$properties": {
            "Intensity": 0.08, "Size": 12, "Threshold": 1.5,
        }},
    }
    project_path.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8", newline="\n")
    children = [part("Floor", [0, 0, 0], [80, 1, 80], [0.14, 0.18, 0.28]), part("Spawn", [0, 2, -25], [8, 1, 8], [0.5, 0.71, 0.78], class_name="SpawnLocation")]
    crystals = []
    for index, (x, z) in enumerate(((-18, -15), (0, -12), (18, -15), (-24, 4), (0, 0), (24, 4), (-16, 20), (0, 24), (16, 20))):
        crystal = part(f"Crystal{index + 1}", [x, 3, z], [3, 5, 3], [0.48, 0.24, 0.76], "Glass", "WedgePart")
        crystal["properties"]["CanCollide"] = False
        crystal["properties"].update({"Transparency": 0.08, "CanTouch": False, "CastShadow": False})
        crystal["children"] = [{"name": "Collect", "className": "ProximityPrompt", "properties": {
            "ActionText": "Collect", "ObjectText": "Amethyst", "HoldDuration": 0,
            "MaxActivationDistance": 8, "RequiresLineOfSight": True,
            "KeyboardKeyCode": "E", "GamepadKeyCode": "ButtonX", "ClickablePrompt": True,
            "Exclusivity": "OneGlobally",
        }}, {"name": "Glow", "className": "PointLight", "properties": {
            "Color": [0.63, 0.36, 0.9], "Brightness": 0.35, "Range": 7, "Shadows": False,
        }}]
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


def create_brawl(target):
    new_project(target, "Element Brawl")
    example = ROOT / "examples/element-brawl"
    for folder in ("src", "tests"):
        shutil.copytree(example / folder, target / folder, dirs_exist_ok=True)
    project_path = target / "default.project.json"
    project = json.loads(project_path.read_text(encoding="utf-8"))
    # Every fighter must stay visible to every client, so this one-screen arena does not stream.
    project["tree"]["Workspace"]["$properties"] = {"StreamingEnabled": False}
    project["tree"]["Lighting"] = brawl_map.lighting()
    project_path.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8", newline="\n")
    for name, model in (("SkyShrine", brawl_map.stage()), ("Backdrop", brawl_map.backdrop())):
        (target / f"src/world/{name}.model.json").write_text(json.dumps(model, indent=2) + "\n", encoding="utf-8", newline="\n")
    shutil.copyfile(example / "README.md", target / "EXAMPLE.md")
    print(f"Element Brawl created at {target}. Run tools/check.sh, build/connect Rojo, then test in a dedicated place.")


def create_showcase(target, title, folder, world, lighting):
    """A V1.1 showcase: example sources + a generated world and lighting (no streaming, one scene)."""
    new_project(target, title)
    example = ROOT / "examples" / folder
    for sub in ("src", "tests"):
        if (example / sub).exists():
            shutil.copytree(example / sub, target / sub, dirs_exist_ok=True)
    project_path = target / "default.project.json"
    project = json.loads(project_path.read_text(encoding="utf-8"))
    project["tree"]["Workspace"]["$properties"] = {"StreamingEnabled": False}
    project["tree"]["Lighting"] = lighting()
    project_path.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8", newline="\n")
    scene, backdrop = world()
    for name, model in (("Scene", scene), ("Backdrop", backdrop)):
        (target / f"src/world/{name}.model.json").write_text(json.dumps(model, indent=2) + "\n", encoding="utf-8", newline="\n")
    shutil.copyfile(example / "README.md", target / "EXAMPLE.md")
    print(f"{title} created at {target}. Run tools/check.sh, rojo build, then open the new place in Studio.")


def create_collapse(target):
    create_showcase(target, "Celestial Collapse", "celestial-collapse", showcase_maps.collapse_world, showcase_maps.collapse_lighting)


def create_hatch(target):
    create_showcase(target, "Mythic Hatch", "mythic-hatch", showcase_maps.hatch_world, showcase_maps.hatch_lighting)


def create_frontier(target):
    create_showcase(target, "Neon Frontier", "neon-frontier", frontier_map.frontier_world, frontier_map.frontier_lighting)


EXAMPLES = {
    "crystal-rush": create,
    "element-brawl": create_brawl,
    "celestial-collapse": create_collapse,
    "mythic-hatch": create_hatch,
    "neon-frontier": create_frontier,
}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=Path)
    parser.add_argument("--example", choices=sorted(EXAMPLES), default="crystal-rush")
    args = parser.parse_args()
    EXAMPLES[args.example](args.target)
