---
name: new
description: Create a new Roblox game project set up for fast AI development (Rojo sync, strict type checking, linting, MCP toolkit, VFX/UI/Net/PlayerData libraries, unit tests, debug hooks). Use when the user wants to start a new Roblox game or project.
argument-hint: "[project name]"
---

# New moonbrick project

1. **Name and location.** Use the argument as the name, or ask. Default location `~/RobloxProjects/<name>` (on Windows `C:\Users\<you>\RobloxProjects\<name>`) unless the user picked one. The folder must not exist or must be empty.
2. **Prerequisites:** Python 3.10+, Git Bash on Windows, git and curl. Tell the user the project installs checksum-verified Rokit 1.2.0 if missing, pinned Rojo/luau-lsp/selene/StyLua and the Rojo Studio plugin. Respect existing installation authorization; don't ask again if already granted. `--no-tools` scaffolds without installation.
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/new-project.sh" "<dir>" "<name>"` (Bash tool). It copies the template, the kit and its tests, installs tools, downloads Roblox type definitions and makes the first git commit.
4. Start syncing: `CLAUDE_PROJECT_DIR="<dir>" bash "${CLAUDE_PLUGIN_ROOT}/scripts/dev-start.sh" </dev/null`.
5. Tell the user:
   - Open Roblox Studio (a new Baseplate is fine). If Studio was already open during setup, restart it so the Rojo plugin loads.
   - Make sure the Studio MCP is enabled (Studio Assistant settings) so Claude can reach Studio.
   - Plugins tab → Rojo → **Connect**.
6. When they confirm, verify in one call: `list_roblox_studios`, then `execute_luau` (Edit): `local K=require(game.ServerStorage.MCPKit) return K.tree("game.ReplicatedStorage", 2) .. "\n" .. K.tree("game.ServerScriptService", 2)` — expect `Kit` with `VFX/UI/Net` and `Kit` with `PlayerData/Cooldown/Round/Economy/DebugHooks/DevTools`.
7. Wrap up with next steps:
   - Start Claude Code **inside the project folder** from now on (loads its `CLAUDE.md`; the session hook keeps Rojo running). If they carry on in this session instead, read `<dir>/CLAUDE.md` now and use `<dir>`-prefixed paths: its rules aren't loaded here and `tools/check.sh` won't resolve.
   - Offer to write `docs/design.md` together (game-design skill: a brief of at most 3 questions, recorded in `docs/design.md` and `assets/art.json`) before building features.

## If setup fails
Report the exact error first. A failed run can be resumed, so fix the cause (usually network or git) and **rerun the same `new-project.sh` command**. It keeps existing files and stops short of a second first commit.
- `target must be absent, empty, or an unfinished Moonbrick scaffold`: the folder holds something else. Ask for another location. Never delete a folder to make room.
- Rojo port or ownership messages: `${CLAUDE_PLUGIN_ROOT}/docs/TROUBLESHOOTING.md`.
