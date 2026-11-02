# Recipes

Copy-ready, strict-typed features built on the Kit. Copy a recipe's `server/`, `client/` and `shared/`
files into the project's `src/server/`, `src/client/` and `src/shared/`, then adapt names, numbers and
effects. CI copies every recipe into a fresh project and runs `tools/check.sh` on it.

| Recipe | What it does |
|---|---|
| `Data` | The game's single `PlayerData.start` (Coins + Inventory, Coins on the leaderboard). Required by the others. |
| `Pickups` | Parts tagged `Coin` award 1 saved coin on touch: server distance check, per-part debounce, burst VFX, respawn, debug hooks. |
| `Ability` | Key **Q** / gamepad **X** / touch button fires a server-validated area attack: cooldown, damage in radius, impact VFX for everyone, camera shake nearby. |
| `Shop` | Buy buttons; the server owns prices, buys inside `PlayerData.update` with `Economy.buy`, saves, and answers with a toast. |
| `Checkpoints` | Spawn and respawn: parts tagged `Checkpoint` (attribute `Order`) record the furthest one reached; players respawn there. |
| `Zones` | Parts tagged `Zone` name areas: the server sets a `Zone` attribute on the Player, the client toasts it and blends a `Scene` mood from `ZoneMoods`. |
| `Round` | A full round loop on `Kit.Round`: moves players between `LobbySpawn` and `ArenaSpawn` parts and shows a phase timer. One player is enough in Studio. |
| `Obby` | Staged obstacle course: `ObbyStage`, `ObbyHazard`, `ObbyFinish` tags, respawn at the last stage, timer, best time, coins. `K.hook("Obby", "build")` makes a sample course. |
