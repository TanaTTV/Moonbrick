---
name: game-design
description: Roblox game design and creative direction — the creative brief (references, hybrid genres, art direction), design docs, core loops, game feel ("juice"), first-time player experience, mobile/console/PC support, screenshot-based visual review, and fair monetization. Use when planning a game or feature, when the user asks for a look, style or vibe, when they share reference images, when they ask to make something feel better, look better, or be more fun, and before calling a player-facing feature done.
---

# Game design

## 1. Creative brief (before the first visual)
Read `docs/design.md` and `assets/art.json` first. If the direction is already there, follow it; don't re-ask.
Otherwise ask **at most 3 questions**, only those the request leaves open:
1. **The moment:** who plays, on what device, and the one moment that must feel amazing.
2. **References:** games, films or images to borrow from, and *what* to take from each.
3. **Mood and genre mix:** three mood words; for hybrids, which genre owns the rules and which owns the look.

If the user says "up to you" or answers vaguely, don't ask again: propose **three contrasting directions**
(different shape language, palette, motion and UI, not three colour swaps). Give each one a name, a line per
channel and its references. Let them pick or mix, then record the result.

**Hybrid genres:** split ownership explicitly. Example: *cyberpunk western*. The western owns silhouettes,
architecture and pacing (false fronts, dust, standoffs); cyberpunk owns light, signage and UI (neon,
scanlines, glitch). Write the split down. A blend with no owner turns to mush.

**Reference images:** extract palette, value structure (where the light is), silhouettes, composition and
material contrast, and describe them in words in the design doc. Never copy characters, logos or a specific
artwork, and never commit someone else's image. The goal is the *principle*, executed originally.

## 2. Record it once
- `docs/design.md` → "Art direction" section (template next to this file): references with take/avoid,
  genre ownership, palette roles, shape language, motion feel, UI shape, effect style, camera.
- `assets/art.json` → `style` holds the machine-readable part: `palette`, `genres`, `references`,
  `ui` (`font`, `displayFont`, `corner`, `stroke`, `buttonFill`), `motion`. Validate it with
  `python KIT/scripts/assets.py validate assets/art.json` (an empty `assets` list is fine without Blender).
- `python KIT/scripts/assets.py theme assets/art.json --output src/shared/ArtStyle.luau` generates
  `ArtStyle.apply()` (`UI.useTheme`) and `ArtStyle.palette` (Fx roles). Edit the manifest, not the output.

## 3. Calibrate away from AI defaults
Untended output drifts to the same look. Choose each of these deliberately rather than by default:
- the purple/teal gradient on everything, FredokaOne for every label, white text outlines on every surface;
- global bloom washing the scene, pure-white highlights, sparkles as the answer to every effect;
- every effect a growing sphere, every UI centred, every animation linear or the same `backOut`;
- one hero colour used at full saturation everywhere (no value contrast, no focal point).
Prefer one focal colour against restrained surroundings, a shape language that repeats (round and soft,
or sharp and angular), and motion with anticipation → impact → follow-through.
For effects, animation, procedural props and themed UI, read `KIT_CREATIVE.md` (Fx, Motion, Pose, Audio,
Tex, Geo).

## 4. Game feel checklist (every player-facing action)
- **Anticipation → action → impact → follow-through.** The peak stacks 3+ channels: visual, screen
  (shake/flash/FOV), UI (number pop) and sound. Hitstop (`handle:freeze`) sells weight.
- **Escalation** on repeats; **feedback for everything**, including refusals ("Need 50 coins").
- Small actions respond in < 0.15 s; big moments take 2–8 s and must be skippable or worth repeating.
- You can't hear: synthesise placeholders (`scripts/sfx.py`) or leave named cues; the user approves audio.

## 5. First-time experience (players decide in < 60 s)
Goal and first interactable visible within 10 s; teach by doing; first reward < 30 s; first "wow"
within minutes; nothing modal on spawn.

## 6. Platforms (most players are on phones)
Buttons ≥ 48 px, nothing vital in the top corners, thumb-reachable actions; every action reachable by
gamepad (`ProximityPrompt`, `GuiService.SelectedObject`); `Fx` quality levels for low-end devices.

## 7. Visual review (screenshots, then fix)
Numbers prove logic; only images prove looks. Capture 1–3 stills at the key moments (freeze effects with
`Fx.setGlobalTimeScale(0)`; see the studio skill), then score:
- **Read at a glance:** silhouette and value. Squint: is the focal point still the brightest, clearest thing?
- **Hierarchy:** one focal point per moment; UI never covers the action.
- **Direction match:** palette roles, shape language and type from the art direction, not defaults (§3).
- **Contrast:** text readable on both bright and dark backgrounds.
- **Clutter:** remove anything that doesn't serve the moment.
Name the **top 3 weaknesses**, fix them, recapture, and repeat until a round finds nothing important
(the plateau). Stills can't prove timing or motion: say so and ask the user to watch it play.

## 8. Retention and monetization (fair and policy-safe)
Progression, collection, daily goals and social play bring players back. Sell convenience and cosmetics,
never power. Show odds before any paid random item. Players may be children, so keep it honest.

## 9. When the user gives feedback
Record **why** in `docs/design.md` ("What works" / "Avoid") so future features match their taste.
