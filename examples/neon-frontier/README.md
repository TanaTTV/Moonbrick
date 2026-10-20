# Neon Frontier (V1.1 showcase)

A compact cyberpunk-western environment: one main street of a desert boomtown that got wired at dusk.
False-front saloons with flickering neon signs, warm lamplit windows, power cables sagging between
pylons, a water tower, a satellite dish, a parked hoverbike, drifting dust, and a bounty board whose card
matches the town's look.

```
python scripts/create-example.py ../neon-frontier --example neon-frontier
cd ../neon-frontier && bash tools/check.sh && rojo build -o frontier.rbxlx
```

## What it uses

| Piece | Kit module | Custom to this game |
|---|---|---|
| Cacti (neon-veined ribs), water tower, barrels, hoverbike, pylons, dish, lamp | `Geo.register` / `Geo.dress` | the seven shapes in `Props.luau` |
| Street, facades, lighting | `scripts/frontier_map.py` (parts only) | layout, palette, dusk grade |
| Neon signs | SurfaceGui + `Scheduler` | `Frontier.flicker` (failing tubes), canvas sized to beat the 100 px TextScaled cap |
| Dust, ambience | `Tex.apply`, `Audio.loop` (wind, buzz from `sfx.py`) | — |
| Bounty card | `UI.useTheme`, `UI.panel`, `UI.button`, `UI.label` | sharp corners, outline buttons, typewriter body, scanlines, glitch-in |

The bounty card is the same composition as Mythic Hatch's reward card (panel, banner, stat, flavour,
two buttons). Only the theme and two small custom touches differ; see `docs/v1.1/VARIANTS.md`.

## Verified in Studio (0.743, disposable place)

- 69/69 Kit + example tests in play mode (`K.test`), including the 3 Frontier specs.
- All 36 Geo prop spots dress on the client; signs, cables, dust and the bounty card render; no script
  errors from the showcase (one `rbxassetid://203785492` warning comes from Studio itself).
- Stills in `docs/v1.1/evidence/neon-frontier/`. Sign flicker and dust drift are motion: watch it play.

## Limits

- No gameplay beyond walking and reading the board; nothing is saved. Bounties are fiction.
- The hoverbike is a rough procedural silhouette; it needs an artist's pass (or a modelled mesh).
- Published games need "Allow Mesh & Image APIs" and the owner's upload of the preview textures/sounds.
