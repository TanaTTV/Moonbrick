"""Runs inside Blender only. Exports selected asset hierarchies using the native FBX operator."""
import json
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from assets import material_node_tree, validate

manifest_path, output = map(Path, sys.argv[sys.argv.index("--") + 1:])
manifest = validate(manifest_path)
scene = bpy.context.scene
if scene.unit_settings.system != "METRIC" or abs(scene.unit_settings.scale_length - 1) > 1e-6:
    raise ValueError("scene must use Metric with unit scale 1 (meters)")

report = {"blenderVersion": bpy.app.version_string, "units": "meters", "style": manifest["style"]["name"], "assets": []}
for asset in manifest["assets"]:
    bpy.ops.object.select_all(action="DESELECT")
    selected = set()
    for name in asset["objects"]:
        obj = scene.objects.get(name)
        if obj is None: raise ValueError("missing scene object: " + name)
        selected.add(obj)
        selected.update(obj.children_recursive)
    meshes = [obj for obj in selected if obj.type == "MESH"]
    rigs = [obj for obj in selected if obj.type == "ARMATURE"]
    if not meshes: raise ValueError("asset has no meshes: " + asset["id"])
    if bool(rigs) != (asset["kind"] == "rig"): raise ValueError("kind does not match selected armatures: " + asset["id"])
    if any(obj.type not in {"MESH", "ARMATURE", "EMPTY"} for obj in selected): raise ValueError("unsupported selected object type")
    triangles, materials, images = 0, set(), set()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        if obj.matrix_world.determinant() <= 0: raise ValueError("apply negative/zero scale before export: " + obj.name)
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
            for slot in obj.material_slots:
                material = slot.material
                if material is None: continue
                materials.add(material)
                node_tree = material_node_tree(material, bpy.app.version)
                if node_tree is not None:
                    for node in node_tree.nodes:
                        if node.type == "TEX_IMAGE" and node.image:
                            images.add(node.image)
                            if not mesh.uv_layers: raise ValueError("textured mesh has no UVs: " + obj.name)
        finally:
            evaluated.to_mesh_clear()
    if triangles > asset["maxTriangles"]: raise ValueError(f"triangle budget exceeded: {asset['id']} ({triangles})")
    if len(materials) > asset["maxMaterials"]: raise ValueError("material budget exceeded: " + asset["id"])
    for image in images:
        if max(image.size) > asset["maxTextureSize"]: raise ValueError("texture budget exceeded: " + image.name)
        if not image.packed_file and (not image.filepath or not Path(bpy.path.abspath(image.filepath)).is_file()):
            raise ValueError("texture must be packed or backed by an existing file: " + image.name)
    for obj in selected:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    destination = output / (asset["id"] + ".fbx")
    result = bpy.ops.export_scene.fbx(
        filepath=str(destination), use_selection=True, object_types={"MESH", "ARMATURE", "EMPTY"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", global_scale=1.0,
        use_mesh_modifiers=True, use_triangles=True, mesh_smooth_type="FACE",
        axis_forward="-Z", axis_up="Y", add_leaf_bones=False,
        bake_anim=asset.get("animation", False), bake_anim_use_all_actions=False,
        bake_anim_use_nla_strips=True, path_mode="COPY", embed_textures=True,
    )
    if "FINISHED" not in result: raise RuntimeError("native FBX exporter did not finish")
    report["assets"].append({"id": asset["id"], "triangles": triangles, "materials": len(materials), "textures": len(images), "rigs": len(rigs), "animation": asset.get("animation", False), "file": destination.name})

(output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
