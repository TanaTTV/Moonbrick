"""Optional native Blender pipeline: validate an art manifest, export locally, keep source and reports."""
from __future__ import annotations
import argparse
import sys
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PBR_MAPS = {"ColorMap": "sRGB", "NormalMap": "Non-Color", "RoughnessMap": "Non-Color", "MetalnessMap": "Non-Color"}


def validate_texture(role: str, size, colorspace: str, budget: int):
    """Validate image metadata without Blender; PBR maps use a local 1024px ceiling."""
    if len(size) != 2 or any(type(n) != int or n < 1 for n in size):
        raise ValueError(f"texture must have positive integer dimensions: {role} ({size})")
    if role in PBR_MAPS and any(n & (n - 1) for n in size):
        raise ValueError(f"texture must have power-of-two dimensions: {role} ({size})")
    limit = min(budget, 1024) if role in PBR_MAPS else budget
    if max(size) > limit:
        raise ValueError(f"texture budget exceeded: {role} ({size}, limit {limit}px)")
    if role in PBR_MAPS and colorspace != PBR_MAPS[role]:
        raise ValueError(f"{role} colorspace must be {PBR_MAPS[role]}, got {colorspace}")


def validate_skin_budget(bone_count: int, influences, max_bones: int = 128, max_influences: int = 4):
    """Count positive deform-bone weights only; reject invalid weights before FBX export."""
    if not 1 <= bone_count <= max_bones:
        raise ValueError(f"bone budget exceeded or empty armature: {bone_count}, limit {max_bones}")
    maximum = 0
    for index, weights in enumerate(influences):
        weights = list(weights)
        if any(not math.isfinite(w) or w < 0 for w in weights):
            raise ValueError(f"invalid skin weight at vertex {index}")
        count = sum(w > 0 for w in weights)
        if count == 0:
            raise ValueError(f"skinned mesh has unweighted vertex {index}")
        if count > min(max_influences, 4):
            raise ValueError(f"influence budget exceeded at vertex {index}: {count}, limit {min(max_influences, 4)}")
        maximum = max(maximum, count)
    return maximum


def material_node_tree(material, blender_version: tuple[int, ...], *, enable: bool = False):
    """Use automatic material nodes on Blender 5+, preserving the pre-5 toggle semantics."""
    if blender_version < (5, 0, 0):
        if enable:
            material.use_nodes = True
        elif not material.use_nodes:
            return None
    # Blender 5 creates the tree by default; use_nodes is deprecated and removed in 6.
    return material.node_tree


ROBLOX_FONT = re.compile(r"[A-Z][A-Za-z0-9]{1,40}")
UI_KEYS = {"font", "displayFont", "corner", "stroke", "buttonFill"}


# Mirrors Scene.Schema in luau/lib/shared/Scene.luau (a test keeps them equal): { min, max }, or a value kind.
SCENE_SCHEMA = {
    "lighting": {
        "Ambient": "color", "OutdoorAmbient": "color", "ColorShift_Top": "color", "ColorShift_Bottom": "color", "FogColor": "color",
        "ClockTime": (0, 24), "Brightness": (0, 10), "ExposureCompensation": (-5, 5), "ShadowSoftness": (0, 1),
        "EnvironmentDiffuseScale": (0, 1), "EnvironmentSpecularScale": (0, 1), "GeographicLatitude": (-90, 90),
        "FogStart": (0, 100000), "FogEnd": (0, 100000), "GlobalShadows": "boolean",
    },
    "atmosphere": {"Density": (0, 1), "Offset": (0, 1), "Glare": (0, 10), "Haze": (0, 10), "Color": "color", "Decay": "color"},
    "sky": {
        "CelestialBodiesShown": "boolean", "StarCount": (0, 5000), "SunAngularSize": (0, 60), "MoonAngularSize": (0, 60),
        "SkyboxBk": "asset", "SkyboxDn": "asset", "SkyboxFt": "asset", "SkyboxLf": "asset", "SkyboxRt": "asset", "SkyboxUp": "asset",
        "SunTextureId": "asset", "MoonTextureId": "asset",
    },
    "colorCorrection": {"Brightness": (-1, 1), "Contrast": (-1, 1), "Saturation": (-1, 1), "TintColor": "color"},
    "bloom": {"Intensity": (0, 10), "Size": (0, 56), "Threshold": (0, 4)},
    "sunRays": {"Intensity": (0, 1), "Spread": (0, 1)},
}
HEX_COLOR = re.compile(r"#[0-9a-fA-F]{6}")
ASSET_ID = re.compile(r"rbxasset(id)?://[^\s\"\\]+")


def validate_scene(scene):
    """style.scene: real values for Scene.apply. `false` on a section other than lighting removes that object."""
    if not isinstance(scene, dict): raise ValueError("style.scene must be an object")
    for section, values in scene.items():
        schema = SCENE_SCHEMA.get(section)
        if schema is None: raise ValueError(f"style.scene sections: {', '.join(SCENE_SCHEMA)}")
        if values is False and section != "lighting": continue
        if not isinstance(values, dict): raise ValueError(f"style.scene.{section} must be an object")
        for key, value in values.items():
            label = f"style.scene.{section}.{key}"
            if key == "Technology": raise ValueError(f"{label} can't be set from scripts; choose it in Studio")
            rule = schema.get(key)
            if rule is None: raise ValueError(f"{label} is not a scene property")
            if rule == "color":
                if not (isinstance(value, str) and HEX_COLOR.fullmatch(value)): raise ValueError(f"{label} must be #RRGGBB")
            elif rule == "boolean":
                if type(value) != bool: raise ValueError(f"{label} must be true or false")
            elif rule == "asset":
                if not (isinstance(value, str) and ASSET_ID.fullmatch(value)): raise ValueError(f"{label} must be an rbxassetid:// or rbxasset:// id")
            elif type(value) not in (int, float) or not math.isfinite(value) or not rule[0] <= value <= rule[1]:
                raise ValueError(f"{label} must be a number in {rule[0]}..{rule[1]}")


def scene_table(scene: dict) -> list[str]:
    """Luau table lines for a validated style.scene, sections and keys in a stable order."""
    def literal(rule, value):
        if rule == "color": return f'Color3.fromHex("{value}")'
        if rule == "boolean": return "true" if value else "false"
        if rule == "asset": return f'"{value}"'
        return repr(value)
    lines = ["{"]
    for section, schema in SCENE_SCHEMA.items():
        if section not in scene: continue
        if scene[section] is False:
            lines.append(f"\t{section} = false,")
            continue
        lines.append(f"\t{section} = {{")
        lines += [f"\t\t{key} = {literal(rule, scene[section][key])}," for key, rule in schema.items() if key in scene[section]]
        lines.append("\t},")
    return lines + ["}"]


def validate_direction(style: dict):
    """Optional art-direction fields (design brief -> code): genres, references, ui, motion."""
    genres = style.get("genres", [])
    if not isinstance(genres, list) or len(genres) > 3 or any(not isinstance(g, str) or not g.strip() for g in genres):
        raise ValueError("style.genres must list up to 3 genre names (base genre first)")
    references = style.get("references", [])
    if not isinstance(references, list) or len(references) > 6: raise ValueError("style.references must list up to 6 references")
    for ref in references:
        if not isinstance(ref, dict) or not all(isinstance(ref.get(k), str) and ref[k].strip() for k in ("source", "take")):
            raise ValueError("each style.references entry needs source and take (what to borrow), optionally avoid")
        if "avoid" in ref and not isinstance(ref["avoid"], str): raise ValueError("style.references avoid must be text")
    ui = style.get("ui", {})
    if not isinstance(ui, dict) or set(ui) - UI_KEYS: raise ValueError(f"style.ui keys: {', '.join(sorted(UI_KEYS))}")
    for key in ("font", "displayFont"):
        if key in ui and not (isinstance(ui[key], str) and ROBLOX_FONT.fullmatch(ui[key])): raise ValueError(f"style.ui.{key} must be an Enum.Font name")
    for key, limit in (("corner", 40), ("stroke", 8)):
        if key in ui and (type(ui[key]) != int or not 0 <= ui[key] <= limit): raise ValueError(f"style.ui.{key} must be 0..{limit}")
    if ui.get("buttonFill", "gradient") not in ("gradient", "flat", "outline"): raise ValueError("style.ui.buttonFill must be gradient, flat or outline")
    motion = style.get("motion", {})
    if not isinstance(motion, dict) or any(not isinstance(v, str) for v in motion.values()): raise ValueError("style.motion values must be text")
    if "scene" in style: validate_scene(style["scene"])


def theme(cfg: dict) -> str:
    """Luau for the game's look: UI.useTheme, an Fx palette and any style.scene, from the manifest's style."""
    style = cfg["style"]
    scene = style.get("scene")
    palette, ui = style["palette"], style.get("ui", {})
    color = lambda key: f'Color3.fromHex("{palette[key]}")'
    lines = [
        f'-- Generated from assets/art.json ("{style["name"]}"): python KIT/scripts/assets.py theme assets/art.json',
        "-- Edit the manifest, not this file, so the art direction stays in one place.",
        'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
        *(["local Scene = require(ReplicatedStorage.Kit.Scene)"] if scene is not None else []),
        "local UI = require(ReplicatedStorage.Kit.UI)",
        "",
        "local ArtStyle = {}",
        "",
        "-- Fx palette roles for Fx.play(def, at, { palette = ArtStyle.palette }).",
        "ArtStyle.palette = {",
        f'\tcore = {color("text")},',
        f'\tglow = {color("primary")},',
        f'\taccent = {color("accent")},',
        f'\tspark = {color("accent")},',
        f'\tdark = {color("surface")},',
        f'\tsmoke = {color("secondary")},',
        "}",
        "",
        "function ArtStyle.apply()",
        "\tUI.useTheme({",
        f'\t\tprimary = {color("primary")},',
        f'\t\tsecondary = {color("secondary")},',
        f'\t\tsurface = {color("surface")},',
        f'\t\ttext = {color("text")},',
    ]
    for key in ("font", "displayFont"):
        if key in ui: lines.append(f"\t\t{key} = Enum.Font.{ui[key]},")
    for key in ("corner", "stroke"):
        if key in ui: lines.append(f"\t\t{key} = {ui[key]},")
    if "buttonFill" in ui: lines.append(f'\t\tbuttonFill = "{ui["buttonFill"]}",')
    lines += ["\t})", "end", ""]
    if scene is not None:
        table = scene_table(scene)
        lines += ["-- The look for Scene.apply: lighting, atmosphere, sky and post effects.", "ArtStyle.scene = " + table[0], *table[1:], ""]
        lines += ["-- Never automatic: call this from one startup script (the server, so everyone gets the look).", "function ArtStyle.applyScene()", "\tScene.apply(ArtStyle.scene)", "end", ""]
    lines += ["return ArtStyle", ""]
    return "\n".join(lines)


def validate(path: Path) -> dict:
    cfg = json.loads(path.read_text(encoding="utf-8"))
    if cfg.get("schemaVersion") != 1: raise ValueError("art manifest schemaVersion must be 1")
    if cfg.get("units") != "meters": raise ValueError("author in meters (Blender metric, unit scale 1); set Studio Scale Unit to Meters")
    style = cfg.get("style", {})
    for key in ("name", "shapeLanguage", "materials", "lighting"):
        if not isinstance(style.get(key), str) or not style[key].strip(): raise ValueError(f"style.{key} required")
    palette = style.get("palette", {})
    for key in ("primary", "secondary", "accent", "surface", "text"):
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(palette.get(key, ""))): raise ValueError(f"style.palette.{key} must be #RRGGBB")
    validate_direction(style)
    assets = cfg.get("assets")
    if not isinstance(assets, list) or len(assets) > 128: raise ValueError("assets must be a list of 0..128 entries")
    if not assets and "source" not in cfg:
        return cfg  # art direction only: no Blender source yet
    source = cfg.get("source")
    if not isinstance(source, str) or not source or source.startswith("/") or ":" in source or Path(source).is_absolute() or ".." in Path(source).parts or "\\" in source:
        raise ValueError("source must be a relative path inside the manifest folder")
    if Path(source).suffix.lower() != ".blend": raise ValueError("source must be .blend")
    ids = set()
    for asset in assets:
        identifier = asset.get("id")
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,63}", identifier) or identifier in ids:
            raise ValueError("asset ids must be unique lowercase filename-safe identifiers")
        ids.add(identifier)
        if asset.get("kind") not in ("static", "rig"): raise ValueError("asset.kind must be static or rig")
        objects = asset.get("objects")
        if not isinstance(objects, list) or not objects or any(not isinstance(name, str) or not name for name in objects): raise ValueError("asset.objects must name Blender objects")
        for key, limit in (("maxTriangles", 100000), ("maxMaterials", 32), ("maxTextureSize", 4096)):
            value = asset.get(key)
            if type(value) != int or not 1 <= value <= limit: raise ValueError(f"asset.{key} must be 1..{limit}")
        if type(asset.get("animation", False)) != bool: raise ValueError("asset.animation must be boolean")
        if asset.get("animation") and asset["kind"] != "rig": raise ValueError("animation requires a rig")
        if type(asset.get("pbr", False)) != bool: raise ValueError("asset.pbr must be boolean")
        if asset.get("pbr") and asset["maxTextureSize"] > 1024: raise ValueError("PBR maxTextureSize must be <=1024")
        for key, default, limit in (("maxBones", 128, 128), ("maxInfluences", 4, 4)):
            value = asset.get(key, default)
            if type(value) != int or not 1 <= value <= limit: raise ValueError(f"asset.{key} must be 1..{limit}")
            if key in asset and asset["kind"] != "rig": raise ValueError(f"asset.{key} requires a rig")
    return cfg


def export(manifest: Path, output: Path, blender: str):
    manifest = manifest.resolve(strict=True)
    cfg = validate(manifest)
    if not cfg["assets"]: raise ValueError("the manifest lists no assets to export (art direction only)")
    source = (manifest.parent / cfg["source"]).resolve(strict=True)
    if not source.is_relative_to(manifest.parent): raise ValueError("source escapes the manifest folder through a symlink")
    if output.exists() or output.is_symlink(): raise ValueError("output must be a new directory; exports never overwrite approved assets")
    executable = shutil.which(blender) or (str(Path(blender).resolve()) if Path(blender).is_file() else None)
    if not executable: raise ValueError("Blender unavailable; pass --blender <path>. This integration is optional.")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="moonbrick-assets-", dir=output.parent) as tmp:
        stage = Path(tmp) / "export"
        stage.mkdir()
        # Arguments are separate values, never a shell command. Disable embedded .blend script execution.
        command = [executable, "--background", "--factory-startup", "--disable-autoexec", str(source), "--python-exit-code", "1", "--python", str(ROOT / "assets/blender/export.py"), "--", str(manifest), str(stage)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=300, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        if result.returncode: raise RuntimeError("Blender export failed:\n" + (result.stdout + result.stderr)[-5000:])
        report_path = stage / "report.json"
        if not report_path.exists(): raise RuntimeError("Blender produced no validation report")
        report = json.loads(report_path.read_text(encoding="utf-8"))
        if len(report["assets"]) != len(cfg["assets"]): raise RuntimeError("incomplete export")
        for asset in cfg["assets"]:
            file = stage / (asset["id"] + ".fbx")
            if not file.is_file() or file.stat().st_size == 0: raise RuntimeError("missing FBX: " + asset["id"])
        if hashlib.sha256(source.read_bytes()).hexdigest() != digest: raise RuntimeError("source changed during export; refusing promotion")
        report.update(sourceSha256=digest, manifestSha256=hashlib.sha256(manifest.read_bytes()).hexdigest())
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
        # The exported art manifest preserves authoring settings and adds native-tool evidence.
        for asset, evidence in zip(cfg["assets"], report["assets"]):
            if asset["id"] != evidence["id"]: raise RuntimeError("export report asset order mismatch")
            asset["export"] = evidence
        (stage / "art.json").write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8", newline="\n")
        # Move every output together after successful native-tool validation.
        if output.exists(): raise ValueError("output appeared during export; refusing overwrite")
        os.rename(stage, output)
    print(f"Exported {len(cfg['assets'])} FBX assets to {output}; source preserved. Studio import/render review still required.")


def main():
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "export", "theme"))
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--blender", default=os.environ.get("BLENDER_PATH", "blender"))
    args = parser.parse_args()
    try:
        cfg = validate(args.manifest)
        if args.command == "validate": print(f"Art manifest OK: {cfg['style']['name']}, {len(cfg['assets'])} assets, meters, local FBX export")
        elif args.command == "theme":
            text = theme(cfg)
            if args.output:
                args.output.write_text(text, encoding="utf-8", newline="\n")
                print(f"Wrote {args.output}")
            else:
                print(text, end="")
        elif not args.output: parser.error("export requires --output <new-directory>")
        else: export(args.manifest, args.output, args.blender)
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error: parser.exit(1, f"error: {error}\n")


if __name__ == "__main__": main()
