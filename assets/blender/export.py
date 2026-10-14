"""Runs inside Blender only. Exports selected asset hierarchies using the native FBX operator."""
import json
import hashlib
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from assets import material_node_tree, validate, validate_texture, validate_skin_budget


def fcurves(action, slot):
    if bpy.app.version < (4, 4, 0):
        return list(action.fcurves)
    return [curve for layer in action.layers for strip in layer.strips
            for bag in strip.channelbags if bag.slot_handle == slot.handle for curve in bag.fcurves]


def pbr_images(material):
    tree = material_node_tree(material, bpy.app.version)
    output_node = next((n for n in tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None) if tree else None
    surface = output_node.inputs["Surface"] if output_node else None
    bsdf = surface.links[0].from_node if surface and surface.is_linked else None
    if bsdf is None or bsdf.type != "BSDF_PRINCIPLED":
        raise ValueError("PBR requires an active Principled BSDF: " + material.name)
    images = {}
    for role, socket in (("ColorMap", "Base Color"), ("NormalMap", "Normal"), ("RoughnessMap", "Roughness"), ("MetalnessMap", "Metallic")):
        source = bsdf.inputs[socket]
        node = source.links[0].from_node if source.is_linked else None
        if role == "NormalMap":
            if node is None or node.type != "NORMAL_MAP" or node.space != "TANGENT":
                raise ValueError("NormalMap requires a tangent-space Normal Map node: " + material.name)
            source = node.inputs["Color"]
            node = source.links[0].from_node if source.is_linked else None
        if node is None or node.type != "TEX_IMAGE" or node.image is None:
            raise ValueError(f"{role} requires a directly linked image texture: {material.name}")
        images[role] = node.image
    return images


def skin_evidence(rigs, meshes, asset):
    evidence = []
    for rig in sorted(rigs, key=lambda obj: obj.name):
        bones = [{"name": bone.name, "parent": bone.parent.name if bone.parent else None,
                  "deform": bone.use_deform} for bone in rig.data.bones]
        validate_skin_budget(len(bones), [], asset.get("maxBones", 128), asset.get("maxInfluences", 4))
        skinned = []
        for obj in meshes:
            modifiers = [mod for mod in obj.modifiers if mod.type == "ARMATURE"]
            if not any(mod.object == rig for mod in modifiers): continue
            if len(modifiers) != 1 or any(mod.type != "ARMATURE" for mod in obj.modifiers):
                raise ValueError("skinned meshes support one armature modifier only: " + obj.name)
            modifier = modifiers[0]
            if not modifier.use_vertex_groups or modifier.use_bone_envelopes or not modifier.show_viewport or not modifier.show_render:
                raise ValueError("skinning requires enabled vertex groups, no bone envelopes: " + obj.name)
            deform = {bone.name for bone in rig.data.bones if bone.use_deform}
            nondeform_groups = {group.index for group in obj.vertex_groups if group.name in rig.data.bones and group.name not in deform}
            if any(group.weight > 0 for vertex in obj.data.vertices for group in vertex.groups if group.group in nondeform_groups):
                raise ValueError("weights on non-deform bones cannot be preserved by FBX: " + obj.name)
            groups = {group.index for group in obj.vertex_groups if group.name in deform}
            maximum = validate_skin_budget(len(bones),
                ([group.weight for group in vertex.groups if group.group in groups] for vertex in obj.data.vertices),
                asset.get("maxBones", 128), asset.get("maxInfluences", 4))
            skinned.append({"mesh": obj.name, "vertices": len(obj.data.vertices), "maxInfluences": maximum})
        if not skinned: raise ValueError("armature has no selected skinned mesh: " + rig.name)
        evidence.append({"name": rig.name, "boneCount": len(bones), "bones": bones, "skins": skinned})
    for obj in meshes:
        if any(mod.type == "ARMATURE" and mod.object not in rigs for mod in obj.modifiers):
            raise ValueError("skinned mesh references an unselected armature: " + obj.name)
    return evidence


def animation_evidence(rigs, asset, scene):
    clips = []
    if not asset.get("animation"): return clips
    for rig in sorted(rigs, key=lambda obj: obj.name):
        data = rig.animation_data
        if data is None or data.action is None: raise ValueError("animation requires an active action: " + rig.name)
        if any(not track.mute for track in data.nla_tracks):
            raise ValueError("export one active action per rig; mute NLA tracks: " + rig.name)
        slot = data.action_slot if bpy.app.version >= (4, 4, 0) else None
        if bpy.app.version >= (4, 4, 0) and slot is None:
            raise ValueError("animation requires an assigned action slot: " + rig.name)
        curves = fcurves(data.action, slot)
        keyed = sorted({bone.name for bone in rig.pose.bones for curve in curves
                        if curve.data_path.startswith(bone.path_from_id() + ".") and len(curve.keyframe_points)})
        if not keyed: raise ValueError("animation action has no keyed bones: " + rig.name)
        start, end = map(float, data.action.frame_range)
        if start != int(start) or end != int(end) or end <= start:
            raise ValueError("animation needs a positive integer-frame clip range: " + rig.name)
        clips.append({"rig": rig.name, "action": data.action.name, "frameRange": [start, end],
                      "fps": scene.render.fps / scene.render.fps_base, "keyedBones": keyed})
    if len({tuple(clip["frameRange"]) for clip in clips}) != 1:
        raise ValueError("selected rig actions must share one frame range")
    scene.frame_start, scene.frame_end = map(int, clips[0]["frameRange"])
    scene.frame_set(scene.frame_start)
    return clips

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
    rig_data = skin_evidence(rigs, meshes, asset)
    clips = animation_evidence(rigs, asset, scene)
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
        validate_texture("image " + image.name, list(image.size), image.colorspace_settings.name, asset["maxTextureSize"])
        if not image.packed_file and (not image.filepath or not Path(bpy.path.abspath(image.filepath)).is_file()):
            raise ValueError("texture must be packed or backed by an existing file: " + image.name)
    surfaces = []
    if asset.get("pbr"):
        if not materials: raise ValueError("PBR asset has no materials: " + asset["id"])
        # Validate every map before writing any of this asset's files.
        material_maps = [(mat, pbr_images(mat)) for mat in sorted(materials, key=lambda mat: mat.name)]
        for material, maps in material_maps:
            for role, image in maps.items():
                validate_texture(role, list(image.size), image.colorspace_settings.name, asset["maxTextureSize"])
        for index, (material, maps) in enumerate(material_maps):
            surface = {"material": material.name, "maps": {}}
            for role, image in maps.items():
                destination = output / f"{asset['id']}_{index}_{role}.png"
                # Save a copy, leaving source pixels/files untouched. FBX then embeds the copy.
                # Image.copy() does not copy the pixel buffer in Blender 5.2.
                copy = bpy.data.images.new(destination.stem, width=image.size[0], height=image.size[1], alpha=True)
                copy.colorspace_settings.name = image.colorspace_settings.name
                copy.pixels.foreach_set(image.pixels[:])
                copy.filepath_raw = str(destination)
                copy.file_format = "PNG"
                copy.save()
                tree = material_node_tree(material, bpy.app.version)
                for node in tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image == image: node.image = copy
                surface["maps"][role] = {"file": destination.name, "size": list(image.size),
                    "colorspace": image.colorspace_settings.name, "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}
            surfaces.append(surface)
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
        bake_anim_use_nla_strips=False, bake_anim_simplify_factor=0.0,
        path_mode="COPY", embed_textures=True,
    )
    if "FINISHED" not in result: raise RuntimeError("native FBX exporter did not finish")
    report["assets"].append({"id": asset["id"], "triangles": triangles, "materials": len(materials), "textures": len(images), "rigs": len(rigs), "animation": asset.get("animation", False), "file": destination.name,
                             "surfaceAppearance": surfaces, "rigData": rig_data, "animations": clips})

(output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
