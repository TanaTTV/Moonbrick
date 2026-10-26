# <Game name> — design

## Pitch
One sentence: who you are, what you do, why it's fun.

## Audience and platforms
Who plays (age range, casual/competitive), main platform (phone/PC/console), session length.

## Core loop
The 30-second loop the player repeats (e.g. collect → upgrade → collect faster), and the longer loop around it (progression, goals).

## Fantasy and mood
How it should feel, in three words. The one moment that must feel amazing.

## Art direction
Machine-readable parts live in `assets/art.json` → `style` (palette, genres, references, ui, motion);
regenerate `src/shared/ArtStyle.luau` with `python KIT/scripts/assets.py theme assets/art.json --output src/shared/ArtStyle.luau`.

- **Genres:** base genre (owns the rules) + flavour genre (owns the look), and what each one owns.
- **References:**
  | Reference | Take | Avoid |
  |---|---|---|
- **Palette roles:** focal colour, support, surfaces, text (hex in art.json). Where the brightest value goes.
- **Shape language:** round/soft or sharp/angular; silhouettes that read on a phone.
- **Motion:** anticipation and impact style, easing feel, idle life.
- **Effects:** what an impact looks like here (forms, textures, how long it lingers), and what's off-limits.
- **UI:** fonts (display/body), corners, button style, panel surface; one sentence on how it matches the world.
- **Lighting and camera:** time of day, atmosphere, where the camera sits for the key moment.

## Features
| Feature | Serves the loop by | Status |
|---|---|---|

## What works (keep doing)
- 

## Avoid
- 
