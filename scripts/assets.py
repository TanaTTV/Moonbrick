"""Optional native Blender pipeline: validate an art manifest, export locally, keep source and reports."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


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
    source = cfg.get("source")
    if not isinstance(source, str) or not source or source.startswith("/") or ":" in source or Path(source).is_absolute() or ".." in Path(source).parts or "\\" in source:
        raise ValueError("source must be a relative path inside the manifest folder")
    if Path(source).suffix.lower() != ".blend": raise ValueError("source must be .blend")
    assets = cfg.get("assets")
    if not isinstance(assets, list) or not 1 <= len(assets) <= 128: raise ValueError("assets must have 1..128 entries")
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
    return cfg


def export(manifest: Path, output: Path, blender: str):
    manifest = manifest.resolve(strict=True)
    cfg = validate(manifest)
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
        shutil.copyfile(manifest, stage / "art.json")
        # Move every output together after successful native-tool validation.
        if output.exists(): raise ValueError("output appeared during export; refusing overwrite")
        os.rename(stage, output)
    print(f"Exported {len(cfg['assets'])} FBX assets to {output}; source preserved. Studio import/render review still required.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "export"))
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--blender", default=os.environ.get("BLENDER_PATH", "blender"))
    args = parser.parse_args()
    try:
        cfg = validate(args.manifest)
        if args.command == "validate": print(f"Art manifest OK: {cfg['style']['name']}, {len(cfg['assets'])} assets, meters, local FBX export")
        elif not args.output: parser.error("export requires --output <new-directory>")
        else: export(args.manifest, args.output, args.blender)
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error: parser.exit(1, f"error: {error}\n")


if __name__ == "__main__": main()
