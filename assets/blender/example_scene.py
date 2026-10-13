"""Generate an original low-poly prop fixture. Only writes the explicitly supplied .blend file."""
from pathlib import Path
import sys
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from assets import material_node_tree

destination = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
if destination.exists(): raise ValueError("refusing to replace an existing .blend file")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1
material = bpy.data.materials.new("Moonbrick_Amethyst")
material.diffuse_color = (0.37, 0.21, 0.68, 1)
node_tree = material_node_tree(material, bpy.app.version, enable=True)
if node_tree is None: raise RuntimeError("material has no shader node tree")
bsdf = node_tree.nodes.get("Principled BSDF")
if bsdf is None: raise RuntimeError("material has no default Principled BSDF")
bsdf.inputs["Base Color"].default_value = material.diffuse_color
bsdf.inputs["Roughness"].default_value = 0.7
bsdf.inputs["Metallic"].default_value = 0.05
bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.35, radius2=0, depth=1.2)
crystal = bpy.context.object
crystal.name = "Crystal"
crystal.data.materials.append(material)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.45, location=(1.2, 0, 0))
rock = bpy.context.object
rock.name = "Rock"
rock.data.materials.append(material)
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(destination))
