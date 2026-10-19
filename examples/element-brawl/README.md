# Element Brawl — showcase example

A Smash-style platform fighter built with the Moonbrick Kit. Pick an element, rack up damage on your rivals and launch them off the Sky Shrine.

`python scripts/create-example.py <new-folder> --example element-brawl` creates a full Rojo project with the Kit, the stage, server rules, bots, saved wins/KOs, a side-on camera and a damage HUD. No tool install, asset upload or Studio changes occur. Then run `bash tools/check.sh`, `rojo build default.project.json -o element-brawl.rbxlx`, open that **new local place** and press Play.

## How it plays

- **Damage %, not health.** Every hit adds percent; the higher it is, the further the next hit launches you (`Rules.knockback`). Fly past the blast zone and you lose a stock. Three stocks each; last fighter standing (or most stocks, then lowest percent, when the 2-minute timer ends) wins.
- **Four elements**, each with its own special:

| Element | Special | What it does |
|---|---|---|
| Fire | Flame Dash | Bursts forward 18 studs, hitting everyone in the path |
| Ice | Frost Lance | Fires a fast shard; the target is slowed for 1.2 s |
| Storm | Thunder Blink | Teleports 16 studs ahead and calls lightning that launches upward |
| Wind | Gale Burst | Radial blast with the biggest knockback, made for ledge-guarding |

- **Everyone has** a quick Strike, a double jump and one free recovery jump after every launch.
- **Bots** fill the round up to four fighters, one per unused element, and a passive Sandbag stands in between rounds for practice. Solo play works.

| | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Move | A / D | Left stick | Thumbstick |
| Jump (twice) | Space | A | Jump button |
| Strike | Click or F | R2 | HIT button |
| Special | Q | X | POW button |

## What it shows off in Moonbrick

- **Server authority** (`Kit.Net`, `Kit.Cooldown`): clients only send `Attack("strike" | "special")`, which is validated and rate-limited. The server owns percent, stocks, cooldowns, hit detection, KO credit and the winner. Launch velocity is computed on the server and applied by whichever machine simulates the character.
- **Rounds** (`Kit.Round`): Waiting → Intermission → Playing → Results, with an early finish when one fighter is left.
- **Saved progress** (`Kit.PlayerData`): Wins and KOs on the leaderboard, session-locked.
- **Juice** (`Kit.VFX`, `Kit.UI`): element-coloured bursts, shockwaves, lightning pillars, KO impacts, camera shake/FOV punch on big hits, "KO!" and "WINS!" titles, punchy percent numbers and an element picker.
- **Pure, tested rules** (`src/server/Rules.luau`, `tests/Rules.spec.luau`): knockback scaling, blast zones, hit boxes and winner tie-breaks run headless in CI.
- **Debug hooks** for AI-driven playtests: `K.hook("Brawl", "state")`, `"skip"`, `"hit"`, `"attack"`, `"pick"`.

## Limits

This is a showcase, not a production fighter. Fighter movement is simulated by each client, as in any Roblox character game; there is no rollback netcode or anti-teleport check on attackers. The map is parts only, so it needs no uploads; swap in your own meshes with the [assets skill](../../skills/assets/SKILL.md).
