# Blender asset pipeline: regression test

Maintainer detail behind the `assets` skill. Run from the repository root.

For a repeatable native regression: `python scripts/test-blender.py --blender <executable>`. It generates original static, four-map PBR and three-bone/two-keyed-bone fixtures, exports/reimports native FBX, checks non-PBR 300×200 texture export/reimport and decoded PBR texture pixels/references, skin weights, scale, clip range/fps and actual deformation, and rejects over-budget geometry/bones/influences, non-power-of-two PBR maps/oversize textures and a normal map without Non-Color. Blender re-import uses `anim_offset=0` to disable its default extra one-frame offset (range tolerance 0.01 frame). Source files/textures stay unchanged and failed exports leave no promoted output. Blender 5+ uses automatic node trees without deprecated `Material.use_nodes` access. This does not prove Roblox import/rendering or upload assets.

Studio import of the PBR prop and the rig/animation fixture passed separately on 2026-10-16; see [the evidence](../acceptance/v1-stable/evidence/2026-10-16-blender-studio.md).
