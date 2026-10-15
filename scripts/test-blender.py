"""Actual native Blender static/PBR/rig/animation regression. Optional; never installs or uploads."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run_blender(executable, script, *arguments):
    command = [executable, "--background", "--factory-startup", "--disable-autoexec",
               "--python-exit-code", "1", "--python", str(script), "--", *map(str, arguments)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError("headless Blender regression failed:\n" + result.stdout + result.stderr)
    if "DeprecationWarning" in result.stderr + result.stdout:
        raise AssertionError("Blender emitted deprecated API access:\n" + result.stderr + result.stdout)
    for line in result.stdout.splitlines():
        if line.startswith("PASS:"): print(line, flush=True)


def hashes(directory):
    return {path.relative_to(directory).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in directory.rglob("*") if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("asset_tools", ROOT / "scripts/assets.py")
    assets = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(assets)
    with tempfile.TemporaryDirectory(prefix="regression-", dir=ROOT / "assets/blender") as tmp:
        root = Path(tmp)
        template = json.loads((ROOT / "assets/art.example.json").read_text())

        def fixture(name, variant="valid"):
            directory = root / name
            source = directory / "source/props.blend"
            script = "example_scene.py" if name == "static" else "rig_pbr_scene.py"
            run_blender(args.blender, ROOT / "assets/blender" / script, source, variant)
            cfg = json.loads(json.dumps(template))
            if name != "static":
                cfg["assets"] = [
                    {"id": "pbr", "kind": "static", "objects": ["PBRProp"], "pbr": True,
                     "maxTriangles": 500, "maxMaterials": 1, "maxTextureSize": 1024},
                    {"id": "rig", "kind": "rig", "objects": ["FixtureRig"], "animation": True,
                     "maxTriangles": 500, "maxMaterials": 1, "maxTextureSize": 1024,
                     "maxBones": 8, "maxInfluences": 4},
                ]
            manifest = directory / "art.json"
            manifest.write_text(json.dumps(cfg))
            return directory, manifest, cfg

        for name in ("static", "advanced"):
            directory, manifest, cfg = fixture(name)
            before = hashes(directory / "source")
            assets.export(manifest, directory / "export", args.blender)
            report = json.loads((directory / "export/report.json").read_text())
            assert report["sourceSha256"] == before["props.blend"]
            assert report["manifestSha256"] == hashlib.sha256(manifest.read_bytes()).hexdigest()
            assert [asset["id"] for asset in report["assets"]] == [asset["id"] for asset in cfg["assets"]]
            assert all(0 < asset["triangles"] <= 500 for asset in report["assets"])
            assert hashes(directory / "source") == before
            run_blender(args.blender, ROOT / "assets/blender/check_roundtrip.py", directory / "export")
            exported = hashes(directory / "export")
            try: assets.export(manifest, directory / "export", args.blender)
            except ValueError as error:
                assert "output must be a new directory" in str(error), str(error)
            else: raise AssertionError("export overwrote an existing output")
            assert hashes(directory / "export") == exported
            print(f"PASS: {name} geometry budgets, source/texture hashes and existing-output refusal", flush=True)

        cases = [("triangles", "valid", "triangle budget exceeded"),
                 ("influences", "influences", "influence budget exceeded at vertex 0: 5, limit 4"),
                 ("npot", "npot", "texture must have power-of-two dimensions"),
                 ("oversize", "oversize", "texture budget exceeded"),
                 ("normal_colorspace", "normal_colorspace", "NormalMap colorspace must be Non-Color"),
                 ("bones", "valid", "bone budget exceeded")]
        for name, variant, message in cases:
            directory, manifest, cfg = fixture(name, variant)
            if name == "triangles": cfg["assets"][1]["maxTriangles"] = 1
            if name == "bones": cfg["assets"][1]["maxBones"] = 2
            if name == "influences": cfg["assets"].reverse()
            manifest.write_text(json.dumps(cfg))
            before = hashes(directory)
            try: assets.export(manifest, directory / "rejected", args.blender)
            except RuntimeError as error:
                assert message in str(error), str(error)
            else: raise AssertionError(f"{name} invalid fixture was accepted")
            assert not (directory / "rejected").exists()
            assert hashes(directory) == before, "failed export left files or changed source textures"
            print(f"PASS: negative {name} refused ({message}); no output or source changes", flush=True)
        print(f"PASS: Blender {report['blenderVersion']} static/PBR/rig/animation native regression; Studio import/rendering NOT validated", flush=True)


if __name__ == "__main__": main()
