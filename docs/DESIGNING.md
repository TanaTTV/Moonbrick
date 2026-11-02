# Designing with Moonbrick

How to get a game that looks and feels like *yours* rather than a generic AI build. This covers the
workflow, how to prompt, what the creative Kit can do, and where its limits are.

## The workflow

1. **Brief.** Claude asks at most three questions (the moment that matters, references, mood or genre mix).
   If you'd rather not decide, it proposes three contrasting directions and you pick or mix.
2. **Record.** The direction goes into `docs/design.md` (Art direction section) and `assets/art.json`
   (`style`: palette, genres, references, UI tokens, motion). `python KIT/scripts/assets.py theme
   assets/art.json --output src/shared/ArtStyle.luau` turns it into code (`UI.useTheme` + an `Fx`
   palette), so the look lives in one place.
3. **Build** with the creative Kit (`tools/KIT_CREATIVE.md`): effects, motion, poses, audio, textures and
   procedural meshes, all driven by that palette.
4. **Review with screenshots.** Claude freezes the key moments, names the three biggest weaknesses, fixes
   them and recaptures until a round finds nothing important. Stills can't prove motion: **you watch the
   moving version** and say what's off. Claude records the why in `docs/design.md` ("What works" /
   "Avoid").

## Prompting examples

Good prompts name the moment, the references and what to borrow from each.

> Make a fireball ability for my anime arena game. The moment that matters is the hit: I want it to feel
> heavy, with a freeze frame like Jujutsu Kaisen fights, but our palette is teal and bone white, not orange.

> A pet-hatching sequence for a cozy forest game. Take the anticipation of Pet Simulator's hatch and the
> soft glow of Ori's key art. Rarer eggs should wobble longer. Phone-first.

> Hybrid: a farming sim with a deep-sea horror mood. Farming owns the loop; horror owns lighting, sound and
> UI. Give me three directions before you build anything.

> Here's a screenshot of a game I like (attached). Use its colour and lighting structure for our lobby, not
> its characters or logo.

Vague is fine too ("make it look cool"): you'll get three named directions to choose from instead of a guess.

## Reference images

Attach screenshots, concept art or photos. Claude extracts the *principles*: palette, value structure
(where the light and the darkest darks are), silhouettes, composition and material contrast. It writes
them into the design doc in words, then executes them originally. It won't copy characters, logos or a
specific artwork, and it won't commit someone else's image to your repo.

## What the creative Kit can do

| Module | Use it for | Notes |
|---|---|---|
| `Fx` | Layered effects: particles, meshes (ball, ring, torus, shard…), beams, lights, sounds, camera (shake, FOV, flash, grade), debris, events | One shared scheduler; pooled; `Low`/`Medium`/`High` quality from the player's graphics setting; markers (`handle:on`), hitstop (`handle:freeze`), time scale. Extends the V1 `VFX` API, which still works unchanged. |
| `Motion` | Easing curves, keyframes, springs, tweens | Named eases (`backOut`, `anticipate`, `expoIn`…), sub-stepped springs. |
| `Pose` | Procedural R15/R6 poses and short clips with markers, blending, rig checks | Plays via `Transform`; also wraps `Animator` tracks and their markers. |
| `Audio` | Roblox-native sounds, groups, positional cues, pitch variation, loops | Placeholder sounds from `scripts/sfx.py` (synthesised locally, no licensing questions). |
| `Tex` | Effect textures (glow, ring, spark, star, smoke flipbooks…) | `scripts/fxtex.py` renders matching PNGs. |
| `Geo` | Procedural meshes: lathe, torus, tube, extrude, sphere, vertex colours; "spots" dressed on clients | Props without Blender or uploads. |
| `UI` | Themed panels, buttons, labels | `UI.useTheme` tokens: fonts, corners, button fill (gradient/flat/outline), panel surface, outlines. V1 defaults unchanged. |

## Limits, honestly

- **Uploads.** Generated textures and sounds preview in Studio on your computer only. Players see stock
  textures and hear nothing custom until you upload them (Claude asks first; uploads use your account).
- **Procedural meshes** are built on each client (server-built ones show a checker), so a published game
  needs Game Settings → Security → "Allow Mesh & Image APIs". Keep the number of distinct shapes small;
  copies are cheap.
- **Animation.** `Pose` makes procedural poses and short clips, good for abilities and emotes. It is not a
  substitute for an animator's walk cycle or facial work. R15 is verified in Studio; R6 joint names and
  rig checks are unit-tested but no R6 rig was played in Studio for V1.1.
- **Rigging.** Moonbrick doesn't rig characters. Rigged meshes come from Blender through the `assets`
  skill (optional) and need the Studio import checks it lists.
- **Effects** are original compositions of simple layers. They won't match a studio's hand-painted
  flipbooks; uploading custom textures closes much of that gap.
- **UI StyleSheets** (Roblox's token system) were investigated: they instantiate in Studio, but their
  live-game status is unverified, so V1.1 uses `UI.useTheme` tokens instead.
- **Visual review** works from stills. Timing, pacing and feel need a human watching.
- **Measured on one PC.** Frame time and cleanup were measured in Studio on a desktop; no phone was tested.

## 3D assets

Three routes, from lightest to heaviest:
1. **Procedural (`Geo`)**: lathed, extruded and tubed shapes with vertex colours, dressed on the client
   No tools, no uploads, stylised low-poly look.
2. **Parts and the world folder**: classic Roblox building, exported to `src/world/*.model.json`.
3. **Blender (optional, `moonbrick:assets`)**: `assets/art.json` sets budgets and style; `assets.py export`
   validates and exports FBX locally. Import, upload and rig correctness are separate, manual gates.
