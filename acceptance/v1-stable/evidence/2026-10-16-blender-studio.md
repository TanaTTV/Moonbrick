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

## Update — owner re-import (same day)

The owner imported `rig.fbx` again through the Animation Editor (no exporter or file change). The resulting `RBX_ANIMSAVES.rig.rig_Scene` has top pose `SkinnedMesh` and Root keys 0 → −0.3 → 0 rad (no −90° offset). Playtest playback via KeyframeSequenceProvider: Root −0.298 / Tip +0.298 at 0.5 s, and the screenshot shows the rig standing upright and bending. So **one Animation Editor import was tilted and one was correct**, and the cause of the difference is unknown. The exporter root-cause theory above is therefore unconfirmed. Status moved from failed to **pending**: one clean repeat (delete the saved clips, import once via the Animation Editor, play) decides it.

Note: Animation Editor clips only play in a running game when a script loads and plays them (and a published game needs an uploaded animation ID). The rig not animating in an ordinary Play session is expected, not a defect.

## Clean repeat (default settings) — flat, reproduced

The owner deleted all saved clips and re-imported via Animation Editor with default Import Settings: `rig_Scene` again had Root −1.571 at t=0 and −1.871 at 0.5 s, so the rig lay flat. A trial exporter change (`bake_space_transform=True` for rigs) only rotated the mesh object and left the armature bones unchanged (Blender's Apply Transform is experimental for armatures). Studio produced the same flat clip, so the change was reverted.

## Resolution — Rest Pose Source

The Animation Editor's Import Settings offer **Rest Pose Source**: *Imported Rig (Zeroed Rotations)* (default), *Imported Rig*, *Animation Editor Rig*. Clean run: delete `RBX_ANIMSAVES`, keep the imported rig, Animation Editor → Import → From File → the **original, unchanged** `rig.fbx`, Rig Type Custom, **Rest Pose Source = Imported Rig**, Scale Unit Stud, Import, Save.

| Time | Root X (rad) | Tip X (rad) |
|---|---|---|
| 0.00 | 0.000 | 0.000 |
| 0.25 | −0.150 | +0.150 |
| 0.50 | −0.300 | +0.300 |
| 1.00 | 0.000 | 0.000 |

The saved clip matches the Blender keys exactly (top pose `SkinnedMesh`). In playtest, KeyframeSequenceProvider playback measured Root −0.299 / Tip +0.299 at 0.5 s, and the screenshot shows the rig upright and bending. The owner observed it upright in the editor too. **Result: pass**, conditional on the documented setting. `skills/assets/SKILL.md` now requires Rest Pose Source = Imported Rig, matching Scale Units, and warns against the importer's auto-saved `Scene` clip.

Not exercised: Meters scale unit; R15/avatar rigs; multiple clips.
