"""Native FBX regression assertions, executed in a fresh headless Blender process."""
import hashlib
import json
from pathlib import Path
import sys
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from assets import material_node_tree, PBR_MAPS

directory = Path(sys.argv[sys.argv.index("--") + 1])
manifest = json.loads((directory / "art.json").read_text())
evidence = {asset["id"]: asset["export"] for asset in manifest["assets"]}

def read(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Blender's importer adds one frame by default; disable that explicit UI offset.
    bpy.ops.import_scene.fbx(filepath=str(directory / (name + ".fbx")), anim_offset=0)
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]

if "crystal" in evidence:
    meshes = read("crystal")
    assert len(meshes) == 1 and len(meshes[0].data.polygons) > 0
    assert abs(meshes[0].dimensions.z - 1.2) < .001, str(meshes[0].dimensions)
    assert evidence["crystal"]["textures"] == 1
    tree = material_node_tree(meshes[0].data.materials[0], bpy.app.version)
    images = [node.image for node in tree.nodes if node.type == "TEX_IMAGE" and node.image]
    assert images and list(images[0].size) == [300, 200]
    print("PASS: non-PBR 300x200 texture exports and survives native FBX reimport")
    print("PASS: static FBX native reimport preserves geometry and 1.2m scale")
    meshes = read("rock")
    assert len(meshes) == 1 and len(meshes[0].data.polygons) > 0
    print("PASS: second static FBX native reimport preserves geometry")
else:
    meshes = read("pbr")
    assert len(meshes) == 1 and abs(meshes[0].dimensions.z - 1) < .001
    assert meshes[0].data.uv_layers
    surface = evidence["pbr"]["surfaceAppearance"][0]
    assert set(surface["maps"]) == set(PBR_MAPS)
    for role, info in surface["maps"].items():
        path = directory / info["file"]
        assert path.name == f"pbr_0_{role}.png"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == info["sha256"]
        image = bpy.data.images.load(str(path), check_existing=False)
        assert list(image.size) == info["size"] == [16, 16]
        assert info["colorspace"] == PBR_MAPS[role]
        image.colorspace_settings.name = info["colorspace"]
        assert len(image.pixels) == 16 * 16 * 4
        # Compare decoded source pixels, accounting for 8-bit PNG quantization.
        source = bpy.data.images.load(str(directory.parent / "source" / (role + ".png")), check_existing=False)
        source.colorspace_settings.name = info["colorspace"]
        assert all(abs(a - b) < .01 for a, b in zip(source.pixels[:], image.pixels[:])), role
    tree = material_node_tree(meshes[0].data.materials[0], bpy.app.version)
    bsdf = next(node for node in tree.nodes if node.type == "BSDF_PRINCIPLED")
    color = bsdf.inputs["Base Color"].links[0].from_node
    normal = bsdf.inputs["Normal"].links[0].from_node
    assert color.type == "TEX_IMAGE" and color.image and "ColorMap" in color.image.filepath
    assert normal.type == "NORMAL_MAP"
    normal_image = normal.inputs["Color"].links[0].from_node
    assert normal_image.type == "TEX_IMAGE" and normal_image.image and "NormalMap" in normal_image.image.filepath
    assert list(color.image.size) == list(normal_image.image.size) == [16, 16]
    assert normal_image.image.colorspace_settings.name == "Non-Color"
    for image in (color.image, normal_image.image):
        assert Path(bpy.path.abspath(image.filepath)).resolve().is_relative_to(directory.resolve()), image.filepath
    print("PASS: PBR native reimport preserves UVs, base-color + normal references and 1m scale")
    print("PASS: exported manifest records all four named PNG maps, colorspaces, sizes and verified SHA256 hashes")

    meshes = read("rig")
    rigs = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    assert len(rigs) == len(meshes) == 1
    rig, mesh = rigs[0], meshes[0]
    expected = evidence["rig"]["rigData"][0]
    hierarchy = {bone.name: bone.parent.name if bone.parent else None for bone in rig.data.bones}
    assert hierarchy == {bone["name"]: bone["parent"] for bone in expected["bones"]}, hierarchy
    assert len(rig.data.bones) == expected["boneCount"] == 3
    assert mesh.parent == rig and any(mod.type == "ARMATURE" and mod.object == rig for mod in mesh.modifiers)
    groups = {group.index for group in mesh.vertex_groups if group.name in hierarchy}
    assert all(1 <= sum(group.weight > 0 for group in vertex.groups if group.group in groups) <= 4 for vertex in mesh.data.vertices)
    assert len(mesh.data.vertices) == expected["skins"][0]["vertices"] == 16
    assert expected["skins"][0]["maxInfluences"] == 2
    for vertex in mesh.data.vertices:
        actual = {mesh.vertex_groups[group.group].name: group.weight for group in vertex.groups if group.group in groups and group.weight > 0}
        weights = ((1, 0, 0), (.5, .5, 0), (0, .5, .5), (0, 0, 1))[int(round(vertex.co.z))]
        wanted = {name: weight for name, weight in zip(("Root", "Middle", "Tip"), weights) if weight}
        assert actual.keys() == wanted.keys() and all(abs(actual[name] - weight) < .001 for name, weight in wanted.items()), actual
    print("PASS: rig native reimport preserves 3-bone names/hierarchy, armature modifier and vertex-group weights")

    clip = evidence["rig"]["animations"][0]
    action = rig.animation_data.action
    assert action is not None
    assert all(abs(a - b) < .01 for a, b in zip(action.frame_range, clip["frameRange"])), str(action.frame_range)
    assert clip["frameRange"] == [1, 25] and clip["fps"] == 24
    assert bpy.context.scene.render.fps / bpy.context.scene.render.fps_base == 24
    if bpy.app.version >= (4, 4, 0):
        slot = rig.animation_data.action_slot
        curves = [curve for layer in action.layers for strip in layer.strips for bag in strip.channelbags
                  if bag.slot_handle == slot.handle for curve in bag.fcurves]
    else:
        curves = list(action.fcurves)
    keyed = {bone.name for bone in rig.pose.bones for curve in curves
             if curve.data_path.startswith(bone.path_from_id() + ".") and len(curve.keyframe_points)}
    assert set(clip["keyedBones"]) == {"Root", "Tip"} and set(clip["keyedBones"]) <= keyed
    # Compare actual poses and deformed vertices, not only exporter-generated key labels.
    scene = bpy.context.scene
    scene.frame_set(1)
    start = {name: rig.pose.bones[name].matrix.copy() for name in clip["keyedBones"]}
    assert abs(mesh.dimensions.z - 3) < .001, str(mesh.dimensions)
    assert abs((rig.matrix_world @ rig.data.bones["Tip"].tail_local).z - 3) < .001
    first = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    positions = [vertex.co.copy() for vertex in first.vertices]
    mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    scene.frame_set(13)
    assert all(any(abs(start[name][i][j] - rig.pose.bones[name].matrix[i][j]) > .01
                   for i in range(4) for j in range(4)) for name in clip["keyedBones"])
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    posed = evaluated.to_mesh()
    assert any((a - b.co).length > .01 for a, b in zip(positions, posed.vertices))
    evaluated.to_mesh_clear()
    print("PASS: rig reimport preserves 3m mesh/bone scale; playback deforms skinned geometry")
    print("PASS: animation native reimport preserves action, frames 1..25 (0.01 tolerance), 24fps and moving Root/Tip bones")
