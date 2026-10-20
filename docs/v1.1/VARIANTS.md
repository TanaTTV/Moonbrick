# V1.1 artistic variants (Phase 5)

Two pairs, each built from one reusable composition, differing in more than colour. Screenshots are
Studio stills from disposable places; motion and timing differences need someone to watch them play.

## 1. Effect: Celestial vs Abyssal Collapse

Source: `examples/celestial-collapse/src/shared/Collapse.luau` (`Collapse.styles`).

| | Celestial | Abyssal |
|---|---|---|
| Silhouette of the orb | Neon sphere, glass body, tilted torus ring | Cluster of glass shards |
| Blast form | Dome: flash, shell, two torus waves, thin pillar | Nine shard spires bursting out of the ground |
| Timing / easing | Gather 0.85 s, `backOut`/`expoOut` snap | Slower phases, `anticipate` wind-up |
| Particle textures | `spark`, `star`, `glow` | `shard`, `wisp` |
| Screen grade | Warm flash | Desaturating grade |
| HUD type | Fondamento on umber | GrenzeGotisch on near-black |

Reused unchanged: the `Fx` runtime (layers, pooling, quality, markers, hitstop), the timeline and
`Collapse.build` recipe, the R15 pose clips, the server cast/damage path, `CollapsePlayer`.
Custom per style: one `style` table (palette, timing, orb, blast, textures, motion).
Evidence: `docs/v1.1/evidence/celestial-collapse/04-celestial-blast.jpg`, `05-abyssal-blast.jpg`.

## 2. UI composition: Mythic Hatch reward card vs Neon Frontier bounty card

Both are the same composition: `UI.panel` with a title, a banner strip, a large stat line, wrapped
flavour text and a two-button row, shown with `UI.show`.

| | Mythic Hatch | Neon Frontier |
|---|---|---|
| Shape language | Round corners (22), pill buttons, soft border | Sharp corners (2), outline buttons, 2 px neon stroke |
| Surface | Cream paper, opaque | Near-black glass, 10% transparent |
| Type | Kalam display, Nunito body | Sarpanch display, SpecialElite (typewriter) body |
| Banner | Rounded rarity ribbon with a moving two-colour shimmer | Hard-edged strip with threat pips |
| Motion | Pop-in, stat counts up | Glitch-in (horizontal jumps), scanline overlay |
| Ink | Plum on cream, no outlines (`labelStroke = 0`) | Pale lilac on black, amber reward |

Reused unchanged: `UI.panel`, `UI.label`, `UI.button`, `UI.show`, the list layout and button feedback.
Custom per game: one `UI.useTheme` call (about 15 tokens) plus ~30 lines each (ribbon shimmer; scanlines
and glitch). Kit change that made the cream card possible: `UI.Theme.labelStroke` (default keeps V1).
Evidence: `docs/v1.1/evidence/mythic-hatch/04-mythic-reveal-card.jpg`,
`docs/v1.1/evidence/neon-frontier/03-bounty-card.jpg`.

## Not counted

Mythic Hatch's Common/Rare/Mythic looks share one recipe and differ mainly in palette and how much
ceremony they get (wobbles, confetti count). They are rarity tiers, not artistic variants.
