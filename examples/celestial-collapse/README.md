# Celestial Collapse (V1.1 showcase)

A cinematic magic ability on a sunset desert terrace. The caster gathers a star in the hand, raises it
overhead, throws it in an arc; it implodes, then explodes with particles, rings, light, debris, camera
work and sound, while the R15 caster's pose is synchronised to every phase. Two artistic styles share one
recipe: **Celestial** (a gold-and-cyan star, a dome blast) and **Abyssal** (green glass shards, spires
from the ground).

```
python scripts/create-example.py ../celestial-collapse --example celestial-collapse
cd ../celestial-collapse && bash tools/check.sh && rojo build -o collapse.rbxlx
```

Controls: **Q** / **X** / tap to cast, **T** / **Y** to switch style. The Astromancer NPC can cast from
Studio without a player: `game.ServerStorage.DebugHooks.Collapse:Invoke("cast", "Abyssal")`.

## What it uses

| Piece | Kit module | Custom to this game |
|---|---|---|
| Orb, implosion, blast, aftermath | `Fx` (particles, mesh incl. torus/shard, beam, light, sound, camera, debris layers; markers; hitstop via `handle:freeze`; quality levels) | the two style tables and the layer recipe in `Collapse.luau` |
| Caster animation | `Pose` (R15 clips gather → rise → throw with a `release` marker → recover) | the four clips |
| Orb flight | `Motion` (arc easing), `Scheduler` | `Collapse.arc` |
| Sound | `Audio` + `scripts/sfx.py` (charge, hum, whoosh, implode, boom) | cue choice per phase |
| Rings and spires | `Geo.unitTorus`, `Geo.unitShard` | — |
| Server authority | `Net` (validated style, rate 2/s), `Cooldown` (4 s), `DebugHooks` | server-chosen target (raycast 26 studs ahead), damage falloff `25 + 55·f²` at the blast time |

## Verified in Studio (0.743, disposable places)

- The server picks the target and refuses a second cast inside the cooldown; Sentinels go from 200 HP to
  154 / 141 / 154 with falloff; K.test 71/71 (Kit + 5 Collapse specs).
- Cleanup: after one cast `Fx.live()`, `Scheduler.count()` and `Pose.activeCount()` return to 0; after
  8 overlapping casts `Fx.live()` and `Scheduler.count()` return to 0 and the workspace returns to its
  starting instance count.
- Frame time on this PC (60 Hz cap): about 16.7 ms on average for a single cast at High and at Low;
  8 overlapping casts peaked at 22.8 ms and 347 extra instances. Low quality uses about a third of
  High's instances (+18 vs +49 for Celestial). No phone was measured.
- Stills in `docs/v1.1/evidence/celestial-collapse/` (before/after the review loop, and both styles).
  They are stills: pacing, the hitstop and the synchronisation of pose, orb and sound need a human to
  watch them play.

## Limits

- Effect textures and sounds are local previews in Studio (`fxtex.py preview`, `sfx.py preview`). A
  published game shows stock particle textures and no custom sounds until the owner uploads them.
- Poses are procedural R15 `Transform` clips, not authored animations; an R6 caster would need its own
  clips (`Pose` refuses a rig mismatch).
