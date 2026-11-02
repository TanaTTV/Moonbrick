---
name: vfx
description: Compose Roblox visual effects with Fx: explosions, slashes, fireballs, hits, spells, auras, pickups, beams, plus custom textures and flipbooks. Use for "make a fireball", "this hit feels weak", "add an explosion", "make the effect better", "draw a smoke texture".
argument-hint: "[effect, or the moment it serves]"
---

# Effects

An effect is one idea, read in a third of a second, then cleaned up. Exact layer fields are in `tools/KIT_CREATIVE.md`; open the `Fx` section only. Palette comes from `src/shared/ArtStyle.luau` (`ArtStyle.palette`), so colours are roles, not hex.

## 1. Plan the read
Write three lines before any code:
- **Moment:** what happened in the game, and how heavy it is (tap, hit, finisher).
- **Read order:** what the eye gets first, second, third. Usually shape, then colour, then detail.
- **Silhouette:** the one shape that says what this is at 1/4 size: a ring for a shockwave, an arc for a slash, a column for a strike, a burst of lines for an impact. If it could be a sphere in any game, pick again.

## 2. Build the silhouette first
Start with one mesh or thick particle layer in flat colour. Play it. If that alone reads, the effect will work; if not, more layers will only hide it. Add the rest only when the shape is right.

## 3. Layer and time it
A strong effect has a head, a body and a tail, and starts on the frame the game event lands: no fade-in on impacts.

| Layer | Starts at | Lasts | Job |
|---|---|---|---|
| Flash core (`core`, additive, mesh or `glow`) | 0 | 0.05 to 0.1 s | Sells the instant |
| Main shape (ring, arc, column) | 0 | 0.15 to 0.3 s, `expoOut` | The silhouette |
| Sparks or streaks (`spark`) | 0 to 0.02 | 0.2 to 0.4 s, fast then drag | Energy and direction |
| Light | 0 | 0.15 to 0.3 s | Lights the ground: ties it to the world |
| Smoke or dust (`smoke`, alpha) | 0.05 to 0.1 | 0.6 to 1.5 s | Weight, cover for cleanup |
| Decal or debris | 0.05 | 1 to 3 s | Evidence it happened |
| Camera and sound | 0 | shake 0.15 to 0.4 s | Felt, not seen |

Scale by weight: tap 0.2 to 0.4 s total, hit 0.4 to 0.8 s, finisher 1 to 2 s. Add `handle:freeze(0.05 to 0.1)` on hits only. Most of the size change belongs in the first 20% of life (`expoOut`), with the rest coasting; linear growth looks like a balloon. 3 to 5 visible layers carries almost everything. A sixth usually means a weak silhouette.

Windup for big moments: particles with `inward = true`, 0.2 to 0.5 s before the release, dim on purpose so the payoff has somewhere to go. Contrast in brightness and scale makes the peak, not raw size.

## 4. Additive or alpha
- **Additive** (`lightEmission` 1): light and energy: fire core, sparks, lasers, glows. Adds to what's behind it; goes white when stacked and vanishes on bright backgrounds.
- **Alpha** (`lightEmission` 0): matter: smoke, dust, debris, blood, ink. Occludes; survives bright skies.
- Mid values (0.3 to 0.6) suit hot smoke and magic mist.
- Pair them: an additive core over an alpha body reads on any background. If an effect must work on a white wall and a night sky, alpha needs to carry the silhouette.

Keep total additive coverage small: stacked additive particles at `count` 100 become a white blob and cost fill rate, the slowest thing on a phone.

## 5. Palette roles
`core` the hottest, nearly white version of the hue. `glow` the saturated identity colour. `accent` a complement, 10% of the area at most. `dark` and `smoke` the shadows and cooled matter, never pure grey unless the art direction says so. `spark` for flying bits. Effect colour should fall from hot to dark over life: `core` → `glow` → `smoke`. Pass the game's palette at play: `Fx.play(def, cf, { palette = ArtStyle.palette })`.

## 6. Textures
First choice: built-ins. `PYTHONUTF8=1 python "${CLAUDE_PLUGIN_ROOT}/scripts/fxtex.py" render fx`, then `... fxtex.py preview fx`, then `Tex.usePreview()` in Studio. `... fxtex.py list` shows the names. Custom ones when the built-ins can't carry the look (a brand-shaped slash, stylised flame): draw white with alpha in Blender with `execute_blender_code` and render to PNG, or generate in Python.

Check every custom texture before use: `PYTHONUTF8=1 python "${CLAUDE_PLUGIN_ROOT}/scripts/fxcheck.py" <file>`. Fix what it reports rather than arguing with it.

Rules it can't judge for you: white or near-white so `color` tints it; soft falloff for light and crisp edges for matter; the shape clear of the image edge; 1024 the largest side.

**Flipbooks:** 2x2, 4x4 or 8x8 only, in a square sheet of 1024 at most; cells stay empty at the borders so frames don't bleed; a one-shot may end on empty cells, a loop must match its first and last frame. More frames means fewer pixels each: at 8x8 of 1024, a cell is 128 px, fine for small sparks and mushy for a screen-filling explosion. Set `FlipbookLayout` before `FlipbookMode`. Passing means one frame shows at each moment in a capture, never the whole grid.

Previews are visible on this PC only. Before publishing, uploaded ids replace them through `Tex.useFiles`; the `ship` skill checks this.

## 7. Contact-sheet check (max 3 rounds)
Stills at the moments that matter prove what code can't:
1. Play on the client, then step to 4 to 6 moments: the first frame, the peak (usually 0.05 to 0.1 s), mid-body, tail, end. Use `K.freeze`/`K.step` or `Fx.setGlobalTimeScale(0)` and `screen_capture`. Don't try "wait, then capture": turn latency lands at random times.
2. Check against a bright and a dark background if the effect appears on both.
3. Score: Does the first frame read as the event? Is the peak the brightest, clearest moment? Is the tail clean or a lingering smear? Does any frame show an invisible or solid-square layer?
4. Name the top 3 weaknesses, fix, recapture.

Stop at round 3 or when no fix changes the read. Say plainly that stills don't prove timing, and ask the user to watch it play. For an opinion from something that didn't build it, leave the effect frozen at its peak and give the `moonbrick:art-critic` agent the camera and look-at positions.

## 8. Before calling it done
- `Fx.play` on clients; damage and rules stay on the server, broadcast with `Net`.
- `minQuality = "Medium"` or `"High"` on sparkle, debris and secondary smoke. The silhouette layer runs at every quality: Low must still read.
- Measure: `Fx.live()` returns to 0 after the effect; `Fx.length(def)` matches the plan.
- A failed texture or missing mesh: report the exact error. Never settle silently for a stock texture when the user asked for a custom one.

Persistent atmosphere (dust, fog, fireflies) is `Fx.ambience`, not a long `Fx.play`.
