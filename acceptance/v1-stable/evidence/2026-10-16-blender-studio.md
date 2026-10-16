# 2026-10-16 — Blender → Studio import (static/PBR pass, rig/animation FAIL)

- **Repo commit:** 31c8d6d-based worktree (`qa/v1-stable-evidence`); exporter unchanged from `d45f9f5`
- **Blender:** 5.2.2 LTS — `python scripts/test-blender.py` PASS; fixtures re-exported to a local `.artifacts` folder with the same manifests
- **Studio:** 0.743.0.7431133, Windows 11; new empty local review place (baseplate only, PlaceId 0)
- **Import:** owner ran File → Import 3D on `pbr.fbx` and `rig.fbx` with the importer's default settings (owner-approved private asset upload, nothing published). The assets skill's **Scale Unit = Meters** setting was *not* used, so 1 m imported as 1 stud.
- **Inspection:** Claude Code via Studio MCP (edit-mode property dump, playtest bone sampling, screenshots kept locally — they contain the owner's avatar)

## blender-studio-static-pbr — pass

| Check | Observed |
|---|---|
| Mesh | `PBRProp` MeshPart, 1.0 × 1.0 × 1.0 (matches the 1 m Blender cube at default unit) |
| SurfaceAppearance | ColorMap, NormalMap, MetalnessMap, RoughnessMap all assigned automatically by the importer |
| Rendering | purple texture visible across faces, lighting/shading consistent, no inverted faces |
| UV | texture variation mapped across faces |

Limitations: the static `rock.fbx`/`crystal.fbx` fixtures were not imported; the Meters scale unit was not exercised; 16 px maps only show coarse detail.

## blender-studio-rig-animation — FAIL

| Check | Observed | Result |
|---|---|---|
| Rig structure | `SkinnedMesh` MeshPart with bones Root → Middle → Tip, AnimationController | pass |
| Scale | 0.4 × 3 × 0.4 (Blender rig is 3 m tall) | pass (default unit) |
| Skinning | Tip rotation visibly bends the mesh in playtest | pass |
| Importer-saved clip `RBX_ANIMSAVES.rig.Scene` | 25 keyframes, 1.000 s, Root −0.3 / Tip +0.3 rad at 0.5 s. Top pose is named `FixtureRig` (Blender armature), not `SkinnedMesh`, so **Root keys are ignored at playback**; only Tip moves. Renaming the top pose to `SkinnedMesh` makes Root animate (−0.298 rad). | **fail** |
| Animation Editor → Import → From FBX Animation (owner) | Remaps top pose to `SkinnedMesh` correctly, but every Root key carries a **−90° X offset** (t=0 −1.571, t=0.5 −1.871). In playback the rig **lies flat and swings up and down** (owner observed the same). | **fail** |

## Root cause and next step

`assets/blender/export.py` exports with `axis_forward="-Z", axis_up="Y"` and no baked space transform, so the Z-up→Y-up conversion stays as a −90° X rotation on the armature, which Studio bakes into Root keys. Trying `bake_space_transform=True` breaks the existing Blender round-trip assertions (meshes re-import Y-up), so the fix needs its own change: probably rig-only (or a rest-pose-neutral armature), updated round-trip assertions, then a new Studio import + Animation Editor check. The armature/root naming (`FixtureRig` vs mesh part) should also be aligned or documented.
