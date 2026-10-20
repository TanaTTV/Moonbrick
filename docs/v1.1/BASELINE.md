# V1.1 baseline (recorded before any V1.1 change)

Branch `v1.1/creative-engine`, cut from `main` at `1d847a5` (v1.0.0). Audit: `.artifacts/v1.1-audit/REPORT.md` (local, not tracked).

## Public interfaces that must stay compatible

The exact signatures are generated into [`luau/API.md`](../../luau/API.md) by `scripts/kit-api.py`. That card is the compatibility contract; V1.1 may only **add** to it.

| Module | Surface kept unchanged |
|---|---|
| `VFX` | `Textures`, `tween`, `numSeq`, `shockwave`, `sphere`, `pillar`, `burst`, `aura`, `glow`, `highlight`, `impact`, `shakeOffset`, `shake`, `flash`, `fovPunch`, `grade`, `title`; `Options` fields `color/color2/size/time/count/texture`; defaults gold `#FFC828` / purple `#AA5AFF` and stock `rbxasset://textures/particles/*` |
| `UI` | `Theme` (same keys and default values, FredokaOne), `screen`, `button`, `label`, `panel`, `show`, `toast`; 48 px touch minimum; gradient button with white stroke and Back press animation |
| `Net`, `PlayerData`, `Cooldown`, `Round`, `Economy`, `DebugHooks` | Unchanged (not in V1.1 scope) |

Behaviour to preserve: V1 games that never touch the new modules must render and behave exactly as before. New styling only applies when a game opts in.

## Tests that protect them

- `luau/tests/VFX_UI.spec.luau`: world effects clean up and don't collide; aura cleanup; screen effects refuse the server; button theme, touch minimum and click wiring; panel layout; show/hide animation cancellation.
- `luau/tests/{Net,PlayerData,Gameplay,MCPKit}.spec.luau`, `scripts/test-luau.py` (headless, 72 tests including both examples' rules).
- `tests/test_kit_api.py`: the card is up to date, lists every public function, and stays under a third of the source size.
- CI: StyLua, strict luau-lsp + Selene on the Kit, the template scaffold, the recipes (`scripts/check-recipes.sh`) and both examples; Rojo build; install/upgrade tests.

## Reusable today

`VFX.tween`/`numSeq`/`shake`/`shakeOffset`; `UI` components; Element Brawl's camera, launch and HUD patterns; the Crystal Rush HUD layout tests; the Blender export pipeline (`scripts/assets.py`); DebugHooks + MCPKit playtest recipe.

## Dependencies and installation

Required: Claude Code, Roblox Studio with the Studio MCP, Python 3.10+, git, curl, Git Bash on Windows; Rokit-pinned Rojo, luau-lsp, Selene, StyLua. Optional: Blender (asset export), Pillow + numpy (brand art only). **V1.1 rule: no new required dependency.**

## Known limitations (from the audit)

- No animation or audio code anywhere in the Kit, recipes or examples.
- One hardcoded look: `UI.Theme` gold/purple Fredoka, gradient buttons; `VFX` gold/purple defaults; `VFX.title` hardcodes FredokaOne and ignores `UI.Theme`; three stock particle textures.
- VFX are single-layer bursts; there is no timeline, layering, pooling, quality level or scheduler.
- No art-direction step; the design skill did not trigger in the cost benchmark.
- Visual quality is never measured.
- V1.0.0 waivers remain open (9 gates, `acceptance/v1-stable/WAIVERS.md`).

## Platform facts verified in Studio 0.743.0.7431133 (2026-10-19)

- `AssetService:CreateEditableMesh` with vertices, triangles, per-face colours, normals and UVs, then `CreateMeshPartAsync(Content.fromObject(mesh))` → MeshPart: works in Edit.
- `AssetService:CreateEditableImage` + `WritePixelsBuffer`; the resulting `Content` is accepted by `ParticleEmitter.TextureContent`, `Beam.TextureContent`, `Trail.TextureContent`, `ImageLabel.ImageContent`, `Decal.ColorMapContent`, `MeshPart.TextureContent`, `SurfaceAppearance.ColorMapContent` (`ParticleEmitter.Texture` itself only takes a ContentId).
- `StyleSheet`/`StyleRule`/`StyleDerive`/`StyleQuery`, `AudioPlayer`/`AudioEmitter`/`Wire`, `IKControl`, `AnimationConstraint`, `UIShadow` can be created. Live-game behaviour of StyleSheets is **not** verified.
- Built-in content usable without uploads: particle textures (`explosion01_core/implosion/shockwave/smoke`, `forcefield_glow/vortex`, `fire`, `smoke`, `sparkles`) and sounds (`impact_explosion_03.mp3`, footsteps, jump, water and a few others).
- Published games need **Allow Mesh & Image APIs** (Game Settings → Security) for EditableMesh/EditableImage. Replication of runtime meshes and images to clients is to be verified in a playtest before relying on it.

## External sources checked (2026-10-19)

| Repository | Revision | Licence | Decision |
|---|---|---|---|
| zriptic/roclicks-skills | `a8b66c1bb9ca` | MIT (RoClicks); `roblox-vfx` also MIT (TabooHarmony, "Roqer") | **Adapt** `roblox-vfx/templates/Emit.luau` (attribute-timed effect playback, time scale/hitstop) with both notices. **Reference** meshlab geometry techniques (lathe/tube/loft/bevel, vertex-colour AO), `vfxtex` texture recipes and the local-preview trick, Capture. Created 2026-10-15: young project |
| Willikk/Roblox | `c77902e8f59c` | **None** | **Reference only** (no code copied): pooling, hitstop, easing, camera shaker, texture animation, beam arcs, R6 procedural layers |
| yansha-os/motion-tools | `7ff9b0bbdddc` | **None** | **Reject**: no licence, 6.5 MB TypeScript MCP server (resident service) |
| Sleitnick/RbxUtil | `31f9120fca02` | MIT | **Reference**: Trove/Signal patterns are already covered by small local code; not worth a dependency |
| TeamSwordphin/ShapecastHitbox | `ac5c0e0a9fe7` | MIT | **Reference**: server-validated sweeps are written locally; last push 2025-08-12 |
| Mqxsyy/Lumina | `08969fa9d612` | MIT | **Reject**: custom particle system with a graph editor, inactive since 2024-07; Roblox's native emitters + EditableImage textures cover the need |
