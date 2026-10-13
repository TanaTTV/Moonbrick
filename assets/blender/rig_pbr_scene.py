"""Original procedural PBR/skinned animation fixtures; no downloads or interactive session."""
from pathlib import Path
import sys
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from assets import material_node_tree, PBR_MAPS

arguments = sys.argv[sys.argv.index("--") + 1:]
destination = Path(arguments[0]).resolve()
variant = arguments[1] if len(arguments) > 1 else "valid"
if destination.exists(): raise ValueError("refusing to replace an existing .blend file")
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 25

material = bpy.data.materials.new("Procedural_PBR")
tree = material_node_tree(material, bpy.app.version, enable=True)
bsdf = tree.nodes.get("Principled BSDF")
for role, socket in (("ColorMap", "Base Color"), ("NormalMap", "Normal"), ("RoughnessMap", "Roughness"), ("MetalnessMap", "Metallic")):
    width = 30 if variant == "npot" and role == "NormalMap" else 16
    if variant == "oversize" and role == "RoughnessMap": width = 2048
    image = bpy.data.images.new(role, width=width, height=16)
    image.colorspace_settings.name = "sRGB" if variant == "normal_colorspace" and role == "NormalMap" else PBR_MAPS[role]
    pixels = []
    for y in range(16):
        for x in range(width):
            checker = (x // 4 + y // 4) % 2
            color = {"ColorMap": (0.25 + checker * 0.2, 0.12, 0.55, 1),
                     "NormalMap": (0.5 + checker * 0.03, 0.5, 1, 1),
                     "RoughnessMap": (0.3 + checker * 0.4,) * 3 + (1,),
                     "MetalnessMap": (float(checker),) * 3 + (1,)}[role]
            pixels.extend(color)
    image.pixels[:] = pixels
    image.filepath_raw = str(destination.parent / (role + ".png"))
    image.file_format = "PNG"
    image.save()
    node = tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    if role == "NormalMap":
        normal = tree.nodes.new("ShaderNodeNormalMap")
        tree.links.new(node.outputs["Color"], normal.inputs["Color"])
        tree.links.new(normal.outputs["Normal"], bsdf.inputs[socket])
    else:
        tree.links.new(node.outputs["Color"], bsdf.inputs[socket])
bpy.ops.mesh.primitive_cube_add(size=1)
bpy.context.object.name = "PBRProp"
bpy.context.object.data.materials.append(material)

armature = bpy.data.armatures.new("FixtureSkeleton")
rig = bpy.data.objects.new("FixtureRig", armature)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
previous = None
names = ["Root", "Middle", "Tip"] + (["ExtraA", "ExtraB"] if variant == "influences" else [])
for index, name in enumerate(names):
    bone = armature.edit_bones.new(name)
    bone.head, bone.tail = (0, 0, index), (0, 0, index + 1)
    bone.parent = previous
    if previous: bone.use_connect = True
    previous = bone
bpy.ops.object.mode_set(mode="OBJECT")

vertices = [(x, y, z) for z in range(4) for x, y in ((-.2, -.2), (.2, -.2), (.2, .2), (-.2, .2))]
faces = [(3, 2, 1, 0), (12, 13, 14, 15)]
for ring in range(3):
    for corner in range(4):
        a, b = ring * 4 + corner, ring * 4 + (corner + 1) % 4
        faces.append((a, b, b + 4, a + 4))
mesh = bpy.data.meshes.new("SkinnedGeometry")
mesh.from_pydata(vertices, [], faces)
skin = bpy.data.objects.new("SkinnedMesh", mesh)
scene.collection.objects.link(skin)
skin.parent = rig
modifier = skin.modifiers.new("Skin", "ARMATURE")
modifier.object = rig
for index, name in enumerate(names):
    group = skin.vertex_groups.new(name=name)
    for vertex in mesh.vertices:
        z = vertex.co.z
        weights = ((1, 0, 0), (.5, .5, 0), (0, .5, .5), (0, 0, 1))[int(z)]
        weight = 0.2 if variant == "influences" else weights[index]
        if weight: group.add([vertex.index], weight, "REPLACE")
skin.data.materials.append(bpy.data.materials.new("Rig_Matte"))
for frame, angle in ((1, 0), (13, .3), (25, 0)):
    for name, sign in (("Root", 1), ("Tip", -1)):
        bone = rig.pose.bones[name]
        bone.rotation_mode = "XYZ"
        # Bend across the bone axis; opposing twists could cancel Tip's world pose.
        bone.rotation_euler.x = sign * angle
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=name)
rig.animation_data.action.name = "FixtureWave"
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(destination))
