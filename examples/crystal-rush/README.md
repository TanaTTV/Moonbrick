# Crystal Rush integration example

`python scripts/create-example.py <new-folder>` creates a full Rojo project, bundled kit/specs, a deterministic map, server round/cooldown/economy rules, saved coins, touch/gamepad-friendly ProximityPrompt pickups, server-fed HUD and Studio DebugHooks. No tool install, asset upload or Studio changes occur.

Run `bash tools/check.sh`, then `rojo build default.project.json -o crystal-rush.rbxlx`. Open **this new local place**, connect the project's Rojo server, and start a playtest. Minimum one player; multiplayer shares one server round. Collect crystals within 45 seconds; coins persist in published games and reset in Studio by default. This example is not intended for production publishing without the V1 acceptance gates.

Art direction: Moonstone Garden palette, matte slate map, amethyst collectibles, warm focal lights. The primitives make installation self-contained; replace them with approved Blender exports after import and screenshot review. `assets/art.json` is the shared art contract. Blender source can be generated with `assets/blender/example_scene.py` and exported with `scripts/assets.py`.

Acceptance in a dedicated place:

1. `K.test()` passes; round moves Waiting → Intermission → Playing → Results.
2. `K.hook("CrystalRush", "state")` reports the actual server state; `skip` advances the deadline.
3. Real ProximityPrompt input awards exactly one coin, hides one crystal and updates HUD; duplicate and distant `CrystalCollect` requests award nothing.
4. Two players see the same countdown; each sees their own score/coins. Leave/respawn works without stale UI or data access.
5. Touch and gamepad can collect and read the HUD; screenshot-review lighting, contrast and small-screen layout.
6. A separate test experience validates real save/load and shutdown; use no production player keys.

Local type checking/building and pure rules can be tested without Studio. These do not prove the six acceptance steps above.
