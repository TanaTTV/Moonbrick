# Mythic Hatch (V1.1 showcase)

A non-combat pet hatch in a moonlit grove. The server rolls the rarity; every client plays the same
ceremony: the egg wobbles with cracks and glints, squashes, bursts into shell shards and star confetti,
and an original creature (the Mothling, a moth-fox) appears with a rarity aura and a reward card.

```
python scripts/create-example.py ../mythic-hatch --example mythic-hatch
cd ../mythic-hatch && bash tools/check.sh && rojo build -o hatch.rbxlx
```

Studio previews of the generated textures and sounds (this PC only, nothing is uploaded):
`python scripts/fxtex.py preview .artifacts/fxtex` and `python scripts/sfx.py preview .artifacts/sfx`.

## What it uses

| Piece | Kit module | Custom to this game |
|---|---|---|
| Egg, Mothling, grove props | `Geo` (lathe, sphere, torus, tube, extrude, `colorAt`, `register`/`dress`) | shapes, colours, idle animation |
| Burst, aura, crack glints | `Fx` (mesh, particles, light, sound, camera layers; `spinAxis`) | layer recipes per rarity |
| Wobble, squash, pop-in, camera push | `Motion`, `Scheduler` | timings in `Hatch.timeline` |
| Sounds | `Audio` + `scripts/sfx.py` (crack, fanfare, wind) | — |
| Reward card | `UI.useTheme` (cream paper, flat pill buttons, Kalam/Nunito, `labelStroke = 0`) | ribbon shimmer, stat count-up |
| Server authority | `Net`, `Cooldown`, `PlayerData`, `DebugHooks` | weights 70/25/5, glow ranges |

## Rules

- The client sends only "Hatch" (no arguments). The server rolls rarity and glow from its own `Random`,
  saves `{ kind, rarity, glow }` to `Pets` (capped at 50), and fires `Hatched` to everyone.
- One ceremony at a time on the shared pedestal; 2 s per-player cooldown; 2 requests/s rate limit.
- Studio: `game.ServerStorage.DebugHooks.Hatch:Invoke("hatch", "Mythic")` forces a rarity (nothing saved).

## Verified in Studio (0.743, disposable place)

- 70/70 Kit + example tests in play mode (`K.test`), including the 4 Hatch specs and the Geo winding specs.
- All 96 grove props dress on the client; Common, Rare and Mythic hatches play end to end through the
  server hook with the card; no script errors.
- Stills in `docs/v1.1/evidence/mythic-hatch/` (idle, anticipation, burst, Mythic and Common reveals).
  They are stills: timing and motion still need a human to watch it play.

## Limits

- Generated meshes are built on each client. A published game needs Game Settings → Security →
  "Allow Mesh & Image APIs", and the textures/sounds need the owner to upload them (until then particles
  use stock textures and the custom sounds are silent).
- The Mothling is procedural and rig-less; it bobs, flaps and sways but does not walk or follow you.
