---
name: studio
description: Fast, token-efficient way to work with Roblox Studio through the Studio MCP (mcp__Roblox_Studio__*). Use before ANY Roblox Studio task — building, scripting, inspecting, testing or editing a place — to cut tool round-trips and output size, and to avoid known Roblox pitfalls.
---

# Working with Roblox Studio fast

Measured: the MCP adds ~60 ms per call (a Studio-side floor). Your own turn costs seconds. So speed = **fewer calls, shorter code, shorter output**. Concurrent calls run in parallel — except in the **Client** datamodel, which runs MCP calls one at a time.

## Session start (2 calls max)
1. `list_roblox_studios` once; reuse the `studio_id`. Skip `get_studio_state` unless you need play mode.
2. Start every kit call with the require line for the datamodel — no pre-check call:
   - Edit / Server: `local K=_G.K or require(game.ServerStorage.MCPKit)`
   - Client (playtest): `local K=_G.K or require(game.ReplicatedStorage:WaitForChild("MCPKit"))`

In a roblox-kit project (`tools/MCPKit.luau` exists) the kit is synced by Rojo. Otherwise, if `require` errors, read `luau/MCPKit.luau` from this plugin (two folders above this skill's base directory) and pass its full contents to `execute_luau` once per datamodel. Edit-mode `require` is cached across calls: after the kit file changes, refresh with `_G.K=require(game.ServerStorage.MCPKit:Clone())`.

## MCPKit (`K`)
| Call | Returns |
|---|---|
| `K.tree(root, depth=2, class?, limit=300)` | indented `Name [Class] +N` tree |
| `K.find(root, class?, namePattern?, limit=500)` → `K.paths(list)` | matching instances / their paths |
| `K.props(path, {"Size","Color",...})` | `Size=..; Color=..; @attr=..` |
| `K.set(listOrPath, {Prop=val}, chunk=1000)` | count; one undo step, yields per chunk |
| `K.src/edit/write/grep` | script read/edit/create/search — **only for scripts Rojo doesn't manage** |
| `K.test(filter?)` | runs `ServerStorage.Tests` specs → `N passed, M failed` + failures |
| `K.hook(feature, action, ...)` | calls a Studio-only debug hook (Server datamodel) |
| `K.mark()` → `K.logs(filter?)` | warnings/errors since the mark, or `clean` |
| `K.record(name, fn(t), {every?, timeout?})` → `K.results(name, wait?)` | background sampler; `fn` returns a row, nil, or `"stop"` |
| `K.screen(path)` | screen `x,y` of a part for `user_mouse_input` (Client) |
| `K.perf(top?)` | instance/part counts, heaviest classes, Studio memory |
| `K.audit()` | deprecated APIs, unvalidated remotes, console-unfriendly input, leftovers |
| `K.toModelJson(path)` | Rojo `.model.json` of a Studio-built object |

## Rules
- **roblox-kit project? Code goes through files, never MCP.** Edit `src/**/*.luau` with Read/Edit/Grep, then `bash tools/check.sh`. MCP is for world-building, inspection, tests and playtests. Rojo overwrites MCP edits to synced scripts.
- **Batch into one `execute_luau`.** Several instances/properties = one script. Read everything in one call; write everything in one call.
- **Parallel calls for independent work** — but never two Client-datamodel calls that depend on each other's timing.
- **Return only what you need.** Prefer `K.tree`/`K.props` over `inspect_instance` (every property) and `search_game_tree` (always pass `path`; without it you get ~20 KB of services).
- **Avoid slow tools unless required:** `subagent` (another LLM), `screen_capture` (image tokens; use for visual/design review, not for logic checks), `generate_*` (async jobs).
- **Heavy builds:** create in a container outside the DataModel, parent per chunk, `task.wait()` per chunk (~1000 items).
- **World objects you build via MCP must end up in files:** `K.toModelJson(path)` → write `src/world/<Name>.model.json` → once Rojo syncs the copy, delete the original. Unsaved places lose MCP-built objects.
- **API docs:** `http_get` with `query` on `create.roblox.com/docs/reference/engine/classes/<Class>.md`.

## Playtest recipe (~5 calls)
1. `start_stop_play` true (code reaches a playtest only after a restart).
2. **Client** `execute_luau`: `K.mark()`; arm `K.record(...)` for anything time-based **and for every UI element the feature touches**.
3. **Server** `execute_luau`: `K.mark()`, `K.test()` if logic changed, drive the feature with `K.hook(...)`, wait, assert end state, return `K.logs()`. Never `CharacterAdded:Wait()` without checking `player.Character` first — it hangs and the MCP call dies.
4. **Client** `execute_luau`: `K.results(...)` + `K.logs()`.
5. `start_stop_play` false.
Hooks bypass input, so UI that only reacts to its own clicks goes stale unnoticed — that's why step 2 records UI. Use `user_mouse_input` only to test input itself: UI by `instance_path`, 3D parts by `K.screen` coords (screen, not viewport, coordinates).

## Gotchas (each cost real debugging time)
- **Avatar joints:** current R15 avatars use `AnimationConstraint`, not `Motor6D`. Editing `C0` or joint attachments does nothing visible. Pose procedurally by setting `joint.Transform` every `RunService.PreSimulation` (works for both), and disconnect when done.
- **`Model:ScaleTo`** on a character also scales `WalkSpeed`/`JumpPower`; set movement stats after scaling.
- **ClickDetector** can't be fired from scripts and doesn't work on console — add a `ProximityPrompt`; test via a debug hook.
- **`get_console_output`** can be empty during playtests; use `K.logs()`.
- **Edit-mode `require` caching:** modules keep their first-loaded code until Studio restarts. Run tests in a playtest (fresh VM), or require a `:Clone()`.
- **Rojo templates** map Workspace/Lighting properties; never let a project file overwrite Studio's world.
- **Unpublished places / no API access:** DataStore calls fail in Studio; `Kit.PlayerData` falls back to memory with a warning.
