"""Actual Blender static-prop export and reimport regression. Optional; never installs Blender."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("asset_tools", ROOT / "scripts/assets.py")
    assets = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(assets)
    with tempfile.TemporaryDirectory(prefix="moonbrick-blender-") as tmp:
        root = Path(tmp)
        source = root / "source/props.blend"
        subprocess.run([args.blender, "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python", str(ROOT / "assets/blender/example_scene.py"), "--", str(source)], check=True, stdout=subprocess.DEVNULL, timeout=60)
        cfg = json.loads((ROOT / "assets/art.example.json").read_text())
        manifest = root / "art.json"
        manifest.write_text(json.dumps(cfg))
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        assets.export(manifest, root / "export", args.blender)
        report = json.loads((root / "export/report.json").read_text())
        assert report["sourceSha256"] == digest
        assert [asset["id"] for asset in report["assets"]] == ["crystal", "rock"]
        assert all(0 < asset["triangles"] <= 500 for asset in report["assets"])
        try: assets.export(manifest, root / "export", args.blender)
        except ValueError: pass
        else: raise AssertionError("export overwrote an existing output")
        # Reimport with Blender's native FBX reader and assert real geometry and scale.
        check = root / "reimport.py"
        check.write_text('''import bpy,sys
from pathlib import Path
bpy.ops.wm.read_factory_settings(use_empty=True)
source=Path(sys.argv[sys.argv.index("--")+1])
bpy.ops.import_scene.fbx(filepath=str(source))
meshes=[obj for obj in bpy.context.scene.objects if obj.type=="MESH"]
assert len(meshes)==1
assert abs(meshes[0].dimensions.z-1.2)<0.001, str(meshes[0].dimensions)
assert len(meshes[0].data.polygons)>0
print("PASS: FBX native reimport preserves geometry and 1.2m height")
''')
        subprocess.run([args.blender, "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python", str(check), "--", str(root / "export/crystal.fbx")], check=True, timeout=60)
        cfg["assets"][0]["maxTriangles"] = 1
        manifest.write_text(json.dumps(cfg))
        try: assets.export(manifest, root / "rejected", args.blender)
        except RuntimeError: pass
        else: raise AssertionError("over-budget geometry was accepted")
        assert not (root / "rejected").exists()
        assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
        print(f"PASS: {report['blenderVersion']} static assets, native FBX round-trip, budgets, source fidelity and output refusal")


if __name__ == "__main__": main()
