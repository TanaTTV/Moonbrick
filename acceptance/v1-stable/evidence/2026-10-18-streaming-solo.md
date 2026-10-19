# 2026-10-18 — Streaming stream-out/in, solo (partial, does not close the gate)

- **Repo commit:** afa10ed (`qa/v1-stable-evidence`)
- **Studio:** 0.743.0.7431133, Windows 11
- **Place:** fresh `python scripts/create-example.py` → `bash tools/check.sh` (OK) → `rojo build streaming.project.json -o streamtest.rbxlx`; new local unpublished file, memory-only persistence. Opened in its own Studio window; no other place was touched.
- **Disposable extension (test harness only, not shipped):** `streaming.project.json` = the generated project plus a 16-stud walkway of 15 anchored 40-stud segments from z=40 to z=640 and a marker at z=640, and `Workspace.StreamOutBehavior = Opportunistic`. The shipped default (`LowMemory`) only streams out under memory pressure, so without this Studio would retain everything. Shipped radii unchanged: min 64, target 128.
- **Driver:** Claude Code orchestrator through the Roblox Studio MCP, Play Solo (1 player). Movement was real walking with `Humanoid:MoveTo` in ≤48-stud steps at WalkSpeed 16 (no teleport bypass); the Studio navigation tool cannot route into unstreamed regions. Pickups used the game's real `CrystalCollect` remote from the client; rounds were advanced with the `CrystalRush.skip` DebugHook.

## Observed

| Check | Observed | Result |
|---|---|---|
| Initial streaming | Client at spawn (z=-25) held only `Walk00–02`; all 9 crystals present | pass |
| Stream-out | Walking out: 9 crystals at z≈200, 6 at z=246, **0** at z=293 and beyond. At z=623 the client held only `Walk08–14` + `FarMarker`; arena crystals and near segments gone | pass |
| HUD without crystals | At z=623 with 0 crystals on the client, HUD kept updating (`Playing · 40s` → `38s`, `Crystals: 0 Coins: 1`) | pass |
| Distant request | `CrystalCollect` for Crystal5 and Crystal8 from z=623 → both `Move closer`, coins unchanged | pass |
| Stream-in | Walking back, crystals 1–3 arrived at z≈127 and 4–9 at z≈191 (`ChildAdded`); walkway segments returned | pass |
| Late state, round reset while away | Crystal8 claimed in round 2, rounds 3–4 elapsed while it was streamed out; on return it arrived restored (Transparency 0.08, prompt and light enabled) | pass |
| Late state, claimed in the same round | Round 6: claimed Crystal8 (Transparency 1, prompt off), walked to z=299 (0 crystals on client, Crystal8 absent), walked back within the round (36 s): Crystal8 arrived **hidden**, prompt and light disabled; HUD `Crystals: 1 Coins: 2` | pass |
| Duplicate requests | Round 7: three `CrystalCollect Crystal5` (two in the same frame) → coins 2 → 3 (+1 once), then `Already collected` ×2 | pass |
| Teleport pickup | Client `PivotTo` 20 studs to Crystal1 then requested it → `Move closer`, no coin, character pulled back by `Rules.plausibleMove`, Crystal1 untouched | pass |
| Logs | No game errors or warnings; only Studio CorePackages UIBlox warnings and an unrelated core `rbxassetid://203785492` content warning (not referenced by the project) | pass |

## Not covered (gate stays pending)

- **2-player authority:** shared countdown and separate scores, and a crystal claimed by the *other* player staying hidden when it streams in. Needs Test → Local Server + 2 Players, which the Studio MCP cannot start. The single-player late-arrival checks above exercise the same server-owned replication path, but they are not a substitute.
- **Shipped stream-out behaviour:** stream-out was forced with `Opportunistic`; under the shipped `LowMemory` default, Studio would not have streamed anything out.
