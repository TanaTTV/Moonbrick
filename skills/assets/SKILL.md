---
name: assets
description: 'Make 3D models for a Roblox game (props, trees, weapons, statues, buildings, rigs): pick Parts, Geo or Blender, model in Blender, export FBX, import to Studio. Use for "make a model", "low-poly tree", "build this in Blender", "import this FBX".'
argument-hint: "[art manifest or asset brief]"
---

# 3D assets

`assets/art.json` is the contract: style, palette, budgets. If it's missing, copy `${CLAUDE_PLUGIN_ROOT}/assets/art.example.json` there and adapt style, palette, silhouettes, materials, lighting and budgets to `docs/design.md`. Reuse the palette in UI and effects. Record ownership, licence and references in the design doc. `python` means Python 3.10+; if it isn't found, use `py -3` (Windows) or `python3`.

## Pick the route

| The thing is | Route | Why |
|---|---|---|
| Box-shaped: floor, wall, platform, hitbox, trigger | Parts, exported to `src/world/` | Collides, saves, replicates, costs almost nothing |
| Simple and repeated: rock, crate, fence, lamp, tree | `GeoShapes`/`Geo` spots | No Blender, no upload; clones share one mesh. Published games need "Allow Mesh & Image APIs" |
| Seen up close, named in the brief, or needs its own silhouette, UVs or PBR: statue, weapon, vehicle, landmark | Blender | Parts and lathes can't hold that shape |
| Skinned or animated | Blender rig | Read `${CLAUDE_SKILL_DIR}/references/pipeline.md` first |

If Blender is the right route but `get_addon_status` fails or the Blender tools aren't listed, tell the user in one line and offer to connect it or accept a `Geo` stand-in. Use the stand-in only on their yes, and label it a stand-in in `docs/design.md`.

## Create the `.blend` (Blender MCP)

1. `get_addon_status`, then `get_scene_info`. Passing: Blender answers and you know what's open. Don't touch a scene the user is working in without asking.
2. With `execute_blender_code`, in small steps: Metric, unit scale 1, new scene, then `bpy.ops.wm.save_as_mainfile` to `assets/source/<name>.blend`. Keep `.blend` sources inside the manifest folder. Look shader nodes up by type, not name. Pack textures or keep their source files beside the `.blend`.
3. Read `${CLAUDE_SKILL_DIR}/references/modelling.md`, then block the silhouette. Keep a character-height box beside it for scale and remove it before export.
4. Run the review loop below.
5. Name the export root plainly, add the asset to `assets` in `art.json` with its budgets, save.

## Review loop (max 3 rounds)

Each round:
1. `look` with `mode: "angles"`, target the root, `views: ["front", "right", "top", "three_quarter"]`, `shading: "material"`, `max_size: 512`. Add a close `distance` only to read one detail.
2. `get_scene_info` with `fields: ["details", "topology", "materials", "ground"]` and `root` set to the asset. Compare faces and materials with the budget.
3. Name the **top 3 weaknesses against `art.json`**: silhouette, value zones, proportion, material contrast, palette. "Looks unfinished" is not a weakness; "handle and blade share one value, so it reads as one blob at phone size" is.
4. Fix those three, nothing else.

Stop at round 3, or earlier if a round finds nothing that changes the read at game distance, and report what's still weak rather than polishing on. For a hero asset, give the object name to the `moonbrick:art-critic` agent, which didn't build it and takes its own views. Its findings go to the user; they don't start a fourth round unless the user asks.

## Export

1. `python "${CLAUDE_PLUGIN_ROOT}/scripts/assets.py" validate assets/art.json`. Passing: one `Art manifest OK` line.
2. Save, then `python "${CLAUDE_PLUGIN_ROOT}/scripts/assets.py" export assets/art.json --output assets/exports/<new-version> --blender <executable>`. Get the executable from `bpy.app.binary_path` if `blender` isn't on PATH. Use a new version folder every time; exports never overwrite.
3. Passing: `Exported N FBX assets` and a `report.json`. That proves local file generation and budgets only, not how it looks in Studio. Over budget: fix the model. Don't raise a budget without telling the user.

## Import into Studio (manual, today)

No Studio MCP tool imports a local FBX, and `execute_luau` can't read one. This is the user's step, so hand them exact instructions:

File → Import → the `.fbx`; check the preview; **Scale Unit: Meters**; turn **Upload to Roblox** off while iterating (it's on by default, and any upload needs their explicit OK, as does another creator's inventory asset). In the preview, read bounds, pivots, normals, collision fidelity, materials, UVs and rig warnings. Keep the result in an isolated review container until accepted.

When they say it's in: `K.tree` to find it, `K.props` for `Size`, then a screenshot beside a character. Passing: right size, right way up, no missing faces, materials present. The Meters setting hasn't been exercised in this repo's Studio evidence (that run used the default, where 1 Blender metre came in as 1 stud), so measure the first import. If scale is off, report the ratio and re-import; don't resize in Studio to hide it.

## When something fails

Report the exact error text and the step that produced it. The `.blend` stays as it is, so the step can be retried. Never quietly swap Parts, a Toolbox model or a generated mesh in for a failed export or import; the user decides. `search_assets`, `import_asset` and `generate_3d` run only when the user asks, because of licences and credits.

## Keep it

Preserve meshes, UI, rigs and effects as `.rbxm` or native Rojo syncback output. `K.toModelJson` is a basic primitives/light/value exporter; it refuses complex classes and references. Never delete the Studio original before validating fidelity in the rebuilt or synced copy. Iterate on the source and re-export rather than patching in Studio.

Finish with a screenshot review of readability, consistency, hierarchy, clutter and performance on target devices. Manifest details, PBR, rigs and animation import: `${CLAUDE_SKILL_DIR}/references/pipeline.md`. Maintainer regression for the exporter: `python "${CLAUDE_PLUGIN_ROOT}/scripts/test-blender.py" --blender <executable>` (Blender only, no Roblox import), described in `${CLAUDE_PLUGIN_ROOT}/docs/ASSETS.md`.
