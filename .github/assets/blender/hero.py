"""Moonbrick hero render: a glossy brick on a floating island under a crescent moon, ringed by the four
Element Brawl elements. Pure procedural geometry and materials (no downloaded assets).

Run headless:  blender -b -P .github/assets/blender/hero.py -- <out.png> [banner|brawl] [samples]
"""
import math
import time
import random
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "//hero.png"
MODE = argv[1] if len(argv) > 1 else "banner"
CAMERA = {"banner": ((4.8, -27.0, 6.5), (4.8, 0.0, 1.0)), "brawl": ((0.0, -17.0, 4.6), (0.0, 0.0, 0.2))}[MODE]
SAMPLES = int(argv[2]) if len(argv) > 2 else 96
SCALE = int(argv[3]) if len(argv) > 3 else 100

FIRE = (1.0, 0.32, 0.08)
ICE = (0.35, 0.8, 1.0)
STORM = (0.62, 0.38, 1.0)
WIND = (0.35, 1.0, 0.6)
BRICK = (0.86, 0.09, 0.16)

T0 = time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
rng = random.Random(4)


# ---------- materials ----------
def principled(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0, transmission=0.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if transmission:
        bsdf.inputs["Transmission Weight"].default_value = transmission
        bsdf.inputs["IOR"].default_value = 1.33
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
    return mat


EMISSIONS = {}


def emission(name, color, strength):
    # Reuse identical materials: every unique material costs a shader compile at render time.
    key = (tuple(round(c, 2) for c in color), round(strength, 1))
    if key in EMISSIONS and not name.startswith("Moon"):
        return EMISSIONS[key]
    mat = bpy.data.materials.new(name)
    EMISSIONS[key] = mat
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    em.inputs["Strength"].default_value = strength
    links.new(em.outputs[0], out.inputs[0])
    return mat


def rock_material():
    mat = bpy.data.materials.new("Rock")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.5
    noise.inputs["Detail"].default_value = 8
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.05, 0.04, 0.08, 1)
    ramp.color_ramp.elements[1].color = (0.2, 0.16, 0.26, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return mat


def link(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


# ---------- world: night gradient with stars ----------
world = bpy.data.worlds.new("Night")
scene.world = world
world.use_nodes = True
wn, wl = world.node_tree.nodes, world.node_tree.links
wn.clear()
wout = wn.new("ShaderNodeOutputWorld")
coord = wn.new("ShaderNodeTexCoord")
sep = wn.new("ShaderNodeSeparateXYZ")
wl.new(coord.outputs["Generated"], sep.inputs[0])
grad = wn.new("ShaderNodeValToRGB")
grad.color_ramp.elements[0].position = 0.0
grad.color_ramp.elements[0].color = (0.045, 0.014, 0.08, 1)
grad.color_ramp.elements[1].position = 0.3
grad.color_ramp.elements[1].color = (0.002, 0.0015, 0.008, 1)
wl.new(sep.outputs["Z"], grad.inputs["Fac"])
stars = wn.new("ShaderNodeTexVoronoi")
stars.inputs["Scale"].default_value = 140
star_ramp = wn.new("ShaderNodeValToRGB")
star_ramp.color_ramp.elements[0].position = 0.0
star_ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
star_ramp.color_ramp.elements[1].position = 0.06
star_ramp.color_ramp.elements[1].color = (0, 0, 0, 1)
wl.new(coord.outputs["Generated"], stars.inputs["Vector"])
wl.new(stars.outputs["Distance"], star_ramp.inputs["Fac"])
add = wn.new("ShaderNodeMix")
add.data_type = "RGBA"
add.blend_type = "ADD"
add.inputs["Factor"].default_value = 0.9
wl.new(grad.outputs["Color"], add.inputs[6])
wl.new(star_ramp.outputs["Color"], add.inputs[7])
bg = wn.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 1.0
wl.new(add.outputs[2], bg.inputs["Color"])
wl.new(bg.outputs[0], wout.inputs[0])

# ---------- the floating island ----------
rock = rock_material()
grass = principled("Grass", (0.1, 0.34, 0.3), rough=0.8)

bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=4.2, radius2=0.25, depth=6.5, location=(0, 0, -3.35))
island = bpy.context.object
island.rotation_euler = (math.pi, 0, 0)
island.name = "Island"
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.subdivide(number_cuts=6)
bpy.ops.object.mode_set(mode="OBJECT")
tex = bpy.data.textures.new("RockNoise", "CLOUDS")
tex.noise_scale = 0.9
disp = island.modifiers.new("Displace", "DISPLACE")
disp.texture, disp.strength = tex, 0.9
island.modifiers.new("Subsurf", "SUBSURF").levels = 1
link(island, rock)

bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=4.35, depth=0.45, location=(0, 0, -0.1))
top = smooth(link(bpy.context.object, grass))
top.modifiers.new("Bevel", "BEVEL").width = 0.12

# Hanging crystals under the island.
for i, color in enumerate((FIRE, ICE, STORM, WIND, STORM, ICE)):
    angle = i / 6 * math.tau + 0.4
    r = 1.4 + rng.random() * 1.5
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.22, radius2=0, depth=1.2 + rng.random(), location=(math.cos(angle) * r, math.sin(angle) * r, -3.4 - rng.random() * 1.6))
    c = bpy.context.object
    c.rotation_euler = (math.pi + rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0)
    link(c, emission(f"Crystal{i}", color, 6))

# Element shrines on the rim, as on the Element Brawl stage.
marble = principled("Marble", (0.85, 0.83, 0.92), rough=0.35)
for i, color in enumerate((FIRE, ICE, STORM, WIND)):
    a = math.radians(120 + i * 38)
    x, y = math.cos(a) * 3.5, math.sin(a) * 3.5
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.75))
    pillar = bpy.context.object
    pillar.scale = (0.32, 0.32, 1.3)
    link(pillar, marble)
    pillar.modifiers.new("Bevel", "BEVEL").width = 0.04
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.26, location=(x, y, 1.75))
    gem = bpy.context.object
    gem.rotation_euler = (0.4, 0.3, a)
    link(gem, emission(f"Gem{i}", color, 7))

# ---------- the brick ----------
def brick(location, rotation, scale=1.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    body = bpy.context.object
    body.scale = (2.0 * scale, 1.0 * scale, 0.72 * scale)
    bpy.ops.object.transform_apply(scale=True)
    bev = body.modifiers.new("Bevel", "BEVEL")
    bev.width, bev.segments = 0.06 * scale, 4
    parts = [body]
    for ix in range(4):
        for iy in range(2):
            x = (-0.75 + ix * 0.5) * scale
            y = (-0.25 + iy * 0.5) * scale
            bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.15 * scale, depth=0.16 * scale, location=(location[0] + x, location[1] + y, location[2] + 0.44 * scale))
            stud = bpy.context.object
            b = stud.modifiers.new("Bevel", "BEVEL")
            b.width, b.segments = 0.025 * scale, 3
            parts.append(stud)
    mat = principled("Brick", BRICK, rough=0.22, emit=BRICK, strength=0.0)
    for p in parts:
        link(p, mat)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    except (AttributeError, RuntimeError):
        bpy.ops.object.shade_flat()
    body.rotation_euler = rotation
    return body


hero = brick((0, 0, 1.25), (math.radians(4), math.radians(-6), math.radians(24)), scale=1.55)
print("T brick", round(time.time() - T0, 1))


# ---------- the four elements ----------
def orb(name, location, color, strength=3.5, radius=0.42):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=48, ring_count=24)
    o = smooth(link(bpy.context.object, emission(name, color, strength)))
    light = bpy.data.lights.new(name + "Light", "POINT")
    light.color, light.energy, light.shadow_soft_size = color, 350, 0.3
    lo = bpy.data.objects.new(name + "Light", light)
    lo.location = location
    scene.collection.objects.link(lo)
    return o


ring_r, ring_z = 3.1, 1.9
positions = {}
for i, (name, color) in enumerate((("Fire", FIRE), ("Ice", ICE), ("Storm", STORM), ("Wind", WIND))):
    a = math.radians(-35 + i * 90)
    positions[name] = Vector((math.cos(a) * ring_r, math.sin(a) * ring_r, ring_z + math.sin(a * 2) * 0.35))
    orb(name, positions[name], color)

# Fire: flame tongues.
for k in range(7):
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.12, radius2=0.0, depth=0.45 + rng.random() * 0.35, location=positions["Fire"] + Vector((rng.uniform(-0.22, 0.22), rng.uniform(-0.22, 0.22), 0.42)))
    link(bpy.context.object, emission(f"Flame{k}", (1.0, 0.3 + rng.random() * 0.25, 0.04), 6))
# Ice: glassy shards around the orb.
ice_glass = principled("IceGlass", (0.75, 0.93, 1.0), rough=0.05, transmission=1.0)
for k in range(6):
    a = k / 6 * math.tau
    p = positions["Ice"] + Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, rng.uniform(-0.2, 0.2)))
    bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=0.09, radius2=0, depth=0.55, location=p)
    s = bpy.context.object
    s.rotation_euler = (rng.uniform(0, math.pi), rng.uniform(0, math.pi), 0)
    link(s, ice_glass)
# Storm: jagged lightning bolts as emissive curves.
for k in range(3):
    curve = bpy.data.curves.new(f"Bolt{k}", "CURVE")
    curve.dimensions, curve.bevel_depth = "3D", 0.025
    spline = curve.splines.new("POLY")
    pts = [positions["Storm"] + Vector((0, 0, 0.3))]
    for _ in range(5):
        pts.append(pts[-1] + Vector((rng.uniform(-0.22, 0.22), rng.uniform(-0.22, 0.22), 0.18)))
    spline.points.add(len(pts) - 1)
    for p, v in zip(spline.points, pts):
        p.co = (*v, 1)
    bolt = bpy.data.objects.new(f"Bolt{k}", curve)
    curve.materials.append(emission(f"BoltMat{k}", (0.8, 0.6, 1.0), 9))
    scene.collection.objects.link(bolt)
# Wind: swirling rings.
for k in range(3):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.5 + k * 0.1, minor_radius=0.014, location=positions["Wind"])
    t = bpy.context.object
    t.rotation_euler = (math.radians(70 + k * 12), math.radians(k * 25), math.radians(k * 40))
    link(t, emission(f"WindRing{k}", WIND, 3))

# An energy arc linking the orbs around the brick.
arc = bpy.data.curves.new("Orbit", "CURVE")
arc.dimensions, arc.bevel_depth = "3D", 0.012
sp = arc.splines.new("NURBS")
n = 64
sp.points.add(n - 1)
for j in range(n):
    a = j / n * math.tau
    sp.points[j].co = (math.cos(a) * ring_r, math.sin(a) * ring_r, ring_z + math.sin(a * 2 + math.radians(70)) * 0.35, 1)
sp.use_cyclic_u = True
orbit = bpy.data.objects.new("Orbit", arc)
arc.materials.append(emission("OrbitMat", (1.0, 0.9, 0.75), 3))
scene.collection.objects.link(orbit)

# ---------- crescent moon ----------
MOON = Vector((-4, 45, 1.5))
bpy.ops.mesh.primitive_uv_sphere_add(radius=6, location=MOON, segments=64, ring_count=32)
moon = smooth(bpy.context.object)
# The bite must go straight through along the view line, or a dent seen head-on still reads as a full disc.
view = (MOON - Vector(CAMERA[0])).normalized()
side = view.cross(Vector((0, 0, 1))).normalized()
up = side.cross(view).normalized()
bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=5.4, depth=40, location=MOON - side * 2.6 + up * 2.0)
cutter = bpy.context.object
cutter.rotation_euler = view.to_track_quat("Z", "Y").to_euler()
boolean = moon.modifiers.new("Crescent", "BOOLEAN")
boolean.operation, boolean.object = "DIFFERENCE", cutter
bpy.context.view_layer.objects.active = moon
bpy.ops.object.modifier_apply(modifier="Crescent")
bpy.data.objects.remove(cutter)
moon_mat = emission("Moon", (1.0, 0.88, 0.66), 1.1)
# Soft craters: darken the emission with a coarse noise.
mn, ml = moon_mat.node_tree.nodes, moon_mat.node_tree.links
crater = mn.new("ShaderNodeTexNoise")
crater.inputs["Scale"].default_value = 2.2
crater_ramp = mn.new("ShaderNodeValToRGB")
crater_ramp.color_ramp.elements[0].position = 0.45
crater_ramp.color_ramp.elements[0].color = (0.82, 0.68, 0.5, 1)
crater_ramp.color_ramp.elements[1].position = 0.62
crater_ramp.color_ramp.elements[1].color = (1.0, 0.9, 0.7, 1)
ml.new(crater.outputs["Fac"], crater_ramp.inputs["Fac"])
ml.new(crater_ramp.outputs["Color"], next(n for n in mn if n.type == "EMISSION").inputs["Color"])
link(moon, moon_mat)
print("T moon", round(time.time() - T0, 1))

# Small distant islands and drifting brick fragments for depth.
for i in range(5):
    x, y, z = rng.uniform(-18, 14), rng.uniform(14, 34), rng.uniform(-6, 5)
    s = rng.uniform(0.5, 1.2)
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=1.6 * s, radius2=0.1, depth=2.2 * s, location=(x, y, z - 1.1 * s))
    small = bpy.context.object
    small.rotation_euler = (math.pi, 0, 0)
    link(small, rock)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=1.65 * s, depth=0.2 * s, location=(x, y, z))
    link(bpy.context.object, grass)
for i in range(6):
    b = brick((rng.uniform(-9, 7), rng.uniform(4, 16), rng.uniform(-3, 5)), (rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3)), scale=rng.uniform(0.18, 0.35))

# ---------- lights and camera ----------
key = bpy.data.lights.new("Moonlight", "AREA")
key.energy, key.size, key.color = 3200, 12, (0.8, 0.78, 1.0)
ko = bpy.data.objects.new("Moonlight", key)
ko.location = (-8, 14, 14)
ko.rotation_euler = (math.radians(-50), math.radians(-25), math.radians(200))
scene.collection.objects.link(ko)
rim = bpy.data.lights.new("Rim", "AREA")
rim.energy, rim.size, rim.color = 1600, 6, (1.0, 0.45, 0.6)
ro = bpy.data.objects.new("Rim", rim)
ro.location = (9, -4, 6)
ro.rotation_euler = (math.radians(60), 0, math.radians(70))
scene.collection.objects.link(ro)

cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = 40
cam_data.dof.use_dof = True
cam_data.dof.focus_distance = 27.0
cam_data.dof.aperture_fstop = 8
cam = bpy.data.objects.new("Camera", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
if MODE == "banner":
    # Hero on the left third; the right side stays dark for the title.
    cam.location, target = CAMERA[0], Vector(CAMERA[1])
    scene.render.resolution_x, scene.render.resolution_y = 2560, 1280
else:
    cam.location, target = CAMERA[0], Vector(CAMERA[1])
    scene.render.resolution_x, scene.render.resolution_y = 2048, 2048
direction = target - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

# ---------- render ----------
for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):  # the identifier changed between Blender 4.x and 5.x
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.eevee.taa_render_samples = SAMPLES
for attr, value in (("use_shadows", True), ("use_raytracing", False)):
    if hasattr(scene.eevee, attr):
        setattr(scene.eevee, attr, value)
print("ENGINE", scene.render.engine)
scene.view_settings.view_transform = "Standard"
try:
    scene.view_settings.look = "Medium High Contrast"
except TypeError:
    pass
scene.render.film_transparent = False
scene.render.resolution_percentage = SCALE
scene.render.filepath = OUT
scene.render.image_settings.file_format = "PNG"

# Bloom through the compositor so emissive orbs glow.
def set_glare(node, name, value):
    # Blender 5 moved glare settings from properties to sockets.
    if name.lower() in node.inputs.keys() or name in node.inputs.keys():
        node.inputs[name if name in node.inputs.keys() else name.lower()].default_value = value
    elif hasattr(node, name.lower()):
        setattr(node, name.lower(), value)


if hasattr(scene, "compositing_node_group"):  # Blender 5+
    tree = bpy.data.node_groups.new("Bloom", "CompositorNodeTree")
    scene.compositing_node_group = tree
    tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    out = tree.nodes.new("NodeGroupOutput")
    out_socket = out.inputs[0]
else:
    scene.use_nodes = True
    tree = scene.node_tree
    for node in list(tree.nodes):
        tree.nodes.remove(node)
    out = tree.nodes.new("CompositorNodeComposite")
    out_socket = out.inputs["Image"]
rl = tree.nodes.new("CompositorNodeRLayers")
glare = tree.nodes.new("CompositorNodeGlare")
if "Type" in glare.inputs.keys():
    glare.inputs["Type"].default_value = "Fog Glow"
else:
    glare.glare_type = "FOG_GLOW"
for setting, value in (("Threshold", 0.9), ("Strength", 0.6), ("Size", 0.6)):
    try:
        set_glare(glare, setting, value)
    except (TypeError, KeyError, AttributeError) as error:
        print("glare setting skipped:", setting, error)
tree.links.new(rl.outputs["Image"], glare.inputs["Image"])
tree.links.new(glare.outputs["Image"], out_socket)

print("T setup", round(time.time() - T0, 1))
bpy.ops.render.render(write_still=True)
print("T render", round(time.time() - T0, 1))
print("RENDERED", OUT)
