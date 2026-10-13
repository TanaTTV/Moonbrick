# __PROJECT_NAME__ (Moonbrick project)

Roblox game built with Rojo. Code and generated world objects live on disk and sync into Studio. Use the `moonbrick:studio` skill for anything touching Studio, `moonbrick:game-systems` before writing gameplay code, and `moonbrick:game-design` for design work.

## Where things go
| Folder | In Studio | For |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | game server code |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | game client code |
| `src/shared/` | `ReplicatedStorage.Shared` | config + modules used by both |
| `src/world/` | `Workspace.World` | objects built via MCP, exported as `.model.json` |
| `src/kit/` | `ReplicatedStorage.Kit`, `ServerScriptService.Kit` | moonbrick libraries (VFX, UI, Net, PlayerData, DebugHooks). Managed by `/moonbrick:update`; don't edit, wrap instead |
| `tests/` | `ServerStorage.Tests` | `*.spec.luau` unit tests (`tests/kit/` = kit's own) |
| `tools/` | `ServerStorage.MCPKit` | MCP helper + `check.sh` |

`Foo.server.luau` = Script, `Foo.client.luau` = LocalScript, `Foo.luau` = ModuleScript, `Foo.model.json` = instances. Anything else (hand-built map, terrain, lighting) stays in the place file — never add Workspace/Lighting properties to `default.project.json`, it would overwrite Studio's copy.

## Workflow
- **Code: edit files with Read/Edit/Write/Grep, never MCP script tools** — Rojo overwrites MCP edits to synced scripts.
- After code changes: `bash tools/check.sh` (strict types + lint; `OK` or one line per problem; `--fix` formats). Fix everything before playtesting.
- Logic with rules (economy, damage, data) gets a spec in `tests/`; run with `K.test()` in the Server datamodel of a playtest.
- Every feature registers Studio-only debug hooks (`ServerScriptService.Kit.DebugHooks`) so playtests can drive it with `K.hook(feature, action)`. UI must follow server state, not only its own clicks.
- No silent early returns in feature code: `warn("<Feature>: why")` or return a reason string.
- `rojo serve` starts automatically (SessionStart hook). If Studio shows stale code, ask the user to click Connect in the Rojo plugin.
- Commit after each working feature. Remind the user to save the place after MCP changes that aren't exported to `src/world/`.

## Design
Read `docs/design.md` (if present) before building features; keep new work consistent with it.
