# Designing with Moonbrick

How to get a game that looks and feels like *yours* rather than a generic AI build. This covers the
workflow, how to prompt, what the creative Kit can do, and where its limits are.

## The workflow

1. **Brief.** Claude asks at most three questions (the moment that matters, references, mood or genre mix).
   If you'd rather not decide, it proposes three contrasting directions and you pick or mix.
2. **Record.** The direction goes into `docs/design.md` (Art direction section) and `assets/art.json`
   (`style`: palette, genres, references, UI tokens, motion). The plugin's `assets.py theme` command
   turns it into code (`UI.useTheme` + an `Fx`
   palette), so the look lives in one place.
3. **Build** with the creative Kit (`tools/KIT_CREATIVE.md`): effects, motion, poses, audio, textures and
   procedural meshes, all driven by that palette.
4. **Review with screenshots.** Claude freezes the key moments, names the three biggest weaknesses, fixes
   them and recaptures, for at most three rounds. The `art-critic` agent can then score the result against
   `art.json` without having built it. Stills can't prove motion: **you watch the moving version** and say
   what's off. Claude records the why in `docs/design.md` ("What works" / "Avoid").

Three skills do the specialist work:

- **`level-design`** for maps: a text map first (areas, paths, the moment in each), then a greybox at real
  Roblox scale, a test jump, a walkthrough, dressing and a review tour.
- **`vfx`** for effects: silhouette first, timed layers, contact-sheet review of 4 to 6 frozen moments.
- **`assets`** for 3D models: picks Parts, `Geo` or Blender, and can model in Blender through its MCP.

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
  The phone rules in `level-design` are working rules, not measurements.
- **Levels.** A walkthrough proves a route can be walked, not that it's fun. Movement numbers in
  `level-design` are Roblox defaults plus arithmetic, so each game confirms them with a test jump.
- **Terrain and hand-placed world** stay in the place file, so save the place. Scene settings live in
  `art.json` and reach the place only when you apply them.
- **Blender meshes.** The modelling loop judges from Blender views. How a mesh looks under Roblox lighting
  is only known after your manual import, and the importer's Meters setting hasn't been exercised in our
  Studio evidence, so the first import gets measured.

## 3D assets

Pick the lightest route that holds the shape:

1. **Parts** for anything box-shaped: floors, walls, platforms. Exported to `src/world/*.model.json`.
2. **Procedural (`Geo`)** for simple repeated props: lathed, extruded and tubed shapes with vertex colours,
   dressed on the client. No tools, no uploads, stylised low-poly look.
3. **Blender (optional)** for hero objects and anything rigged. If the Blender MCP is connected, Claude
   creates the `.blend`, looks at it from several angles, fixes the top 3 weaknesses against `art.json` for
   at most three rounds, then exports. `assets/art.json` sets budgets and style; `assets.py export` validates
   and exports FBX locally. If Blender isn't available, Claude says so and asks before using a stand-in.

**Importing is manual.** No Studio MCP tool imports a local FBX, so you run File → Import yourself; the skill
gives the settings. Claude then checks size and looks at the result. A failed export or import is reported
with its exact error. Claude won't quietly replace your model with something else.
