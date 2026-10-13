---
name: assets
description: Build consistent Roblox art assets with an optional native Blender pipeline, local validation, FBX export and Studio import review. Use for professional 3D props, environments, rigs or asset workflow requests.
argument-hint: "[art manifest or asset brief]"
---

# Professional assets

The plugin root is two folders above this skill; call it `KIT`. Blender remains optional. Use native Studio tools for simple prototypes, Blender for authored meshes/UVs/rigs, and native Rojo syncback for full-fidelity instance export.

1. Read `docs/design.md` and the project art manifest. If absent, copy `KIT/assets/art.example.json` to `assets/art.json` and adapt the style, palette, silhouettes, materials, lighting and explicit geometry/texture budgets to the user's brief. Reuse the same palette in UI/VFX. Record asset ownership/license and references in the design doc.
2. Keep `.blend` sources inside the manifest folder. Author in Metric, unit scale 1 (meters); name export roots explicitly. Assets include selected roots and their descendants. For rigs include the armature and skinned meshes, review NLA clips and weights. Pack textures or keep their source files available.
3. `python KIT/scripts/assets.py validate assets/art.json`. It prints one compact summary. Inspect only relevant scene objects/materials, not the whole Blender datablock tree.
4. `python KIT/scripts/assets.py export assets/art.json --output assets/exports/<new-version> --blender <executable>`. Native background Blender, embedded-script autoexecution disabled; validates triangles/materials/texture sizes, exports FBX, keeps source hashes and a report. Never overwrites prior exports or saves the input `.blend`.
5. Review `report.json`. A successful export proves local file generation only. Rig animation and textured assets require native round-trip and Studio tests; do not claim these passed based on static props.
6. Studio File → Import: preview FBX, set Scale Unit to **Meters**, review bounds/pivots, normals, collision fidelity, materials, UVs and rig/animation warnings. Disable **Upload to Roblox** during iteration. Obtain approval before any upload/publication or use of another creator's inventory asset. Keep imported models in an isolated review container until accepted.
7. Preserve meshes/UI/rigs/effects as `.rbxm` or native Rojo syncback output. `K.toModelJson` is a basic primitives/light/value exporter; it refuses complex classes and references. Never delete the Studio original before validating fidelity in the rebuilt/synced copy.
8. Screenshot-review readability, consistency, hierarchy, clutter and performance on target devices. Iterate source/export rather than patching synced scripts in Studio.

For a repeatable native smoke test: `python KIT/scripts/test-blender.py --blender <executable>`. It creates original low-poly fixtures, exports/reimports FBX, checks scale/budgets and source preservation, and never uploads assets.
