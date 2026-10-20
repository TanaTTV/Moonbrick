# __PROJECT_NAME__ (Moonbrick project)

Roblox game built with Rojo. Code and generated world objects live on disk and sync into Studio. Use the `moonbrick:studio` skill for anything touching Studio, `moonbrick:game-systems` before writing gameplay code, and `moonbrick:game-design` for design work.

## Where things go
| Folder | In Studio | For |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | game server code |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | game client code |
| `src/shared/` | `ReplicatedStorage.Shared` | config + modules used by both |
| `src/world/` | `Workspace.World` | objects built via MCP, exported as `.model.json` |
| `src/kit/` | `ReplicatedStorage.Kit`, `ServerScriptService.Kit` | VFX/UI/Net, PlayerData/Cooldown/Round/Economy/DebugHooks. Managed by `/moonbrick:update`; wrap instead of editing. **API: `tools/KIT_API.md`** (read it, not the source) |
| `tests/` | `ServerStorage.Tests` | `*.spec.luau` unit tests (`tests/kit/` = kit's own) |
| `tools/` | `ServerStorage.MCPKit` | MCP helper, `check.sh`, `KIT_API.md`, copy-ready `recipes/` (not synced) |

`Foo.server.luau` = Script, `Foo.client.luau` = LocalScript, `Foo.luau` = ModuleScript, `Foo.model.json` = instances. Anything else (hand-built map, terrain, lighting) stays in the place file — never add Workspace/Lighting properties to `default.project.json`, it would overwrite Studio's copy.

## Workflow
- **Code: edit files with Read/Edit/Write/Grep, never MCP script tools** — Rojo overwrites MCP edits to synced scripts.
- After code changes: `bash tools/check.sh` (strict types + lint; `OK` or one line per problem; `--fix` formats). Fix everything before playtesting.
- Logic with rules (economy, damage, data) gets a spec in `tests/`; run with `K.test()` in the Server datamodel of a playtest.
- `PlayerData.update` callbacks must not yield; keep saves/remotes outside them. Studio data is memory-only by default. Real-store tests use an explicitly separate test experience/store, never production keys.
- Visual work (effects, animation, procedural props, themed UI): read `tools/KIT_CREATIVE.md`. The game's look lives in `assets/art.json` → `style`; regenerate `src/shared/ArtStyle.luau` with `python <kit>/scripts/assets.py theme assets/art.json --output src/shared/ArtStyle.luau`.
- For professional assets, use `moonbrick:assets` and an `assets/art.json` style/budget contract. Blender is optional. A local export does not approve uploads or prove visual/rig correctness.
- Every feature registers Studio-only debug hooks (`ServerScriptService.Kit.DebugHooks`) so playtests can drive it with `K.hook(feature, action)`. UI must follow server state, not only its own clicks.
- No silent early returns in feature code: `warn("<Feature>: why")` or return a reason string.
- `rojo serve` starts automatically (SessionStart hook). If Studio shows stale code, ask the user to click Connect in the Rojo plugin.
- Commit after each working feature. Remind the user to save the place after MCP changes that aren't exported to `src/world/`.
- Review `.moonbrick/import-report.json` and all imported scripts before playtesting. Upgrade backups live under `.moonbrick/backups/`; never stage unrelated user work.

## Design
Read `docs/design.md` (if present) before building features; keep new work consistent with it.
