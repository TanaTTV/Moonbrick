---
name: new
description: Create a new Roblox game project set up for fast AI development (Rojo sync, strict type checking, linting, MCP toolkit, VFX/UI/Net/PlayerData libraries, unit tests, debug hooks). Use when the user wants to start a new Roblox game or project.
argument-hint: "[project name]"
---

# New moonbrick project

The plugin root is two folders above this skill's base directory (`<base>/../..`); call it `KIT`.

1. **Name and location.** Use the argument as the name, or ask. Default location `~/RobloxProjects/<name>` (on Windows `C:\Users\<you>\RobloxProjects\<name>`) unless the user picked one. The folder must not exist or must be empty.
2. **Prerequisites:** Python 3.10+, Git Bash on Windows, git and curl. Tell the user the project installs checksum-verified Rokit 1.2.0 if missing, pinned Rojo/luau-lsp/selene/StyLua and the Rojo Studio plugin. Respect existing installation authorization; don't ask again if already granted. `--no-tools` scaffolds without installation.
3. Run `bash "KIT/scripts/new-project.sh" "<dir>" "<name>"` (Bash tool). It copies the template, the kit and its tests, installs tools, downloads Roblox type definitions and makes the first git commit.
4. Start syncing: `CLAUDE_PROJECT_DIR="<dir>" bash "KIT/scripts/dev-start.sh" </dev/null`.
5. Tell the user:
   - Open Roblox Studio (a new Baseplate is fine). If Studio was already open during setup, restart it so the Rojo plugin loads.
   - Make sure the Studio MCP is enabled (Studio Assistant settings) so Claude can reach Studio.
   - Plugins tab → Rojo → **Connect**.
6. When they confirm, verify in one call: `list_roblox_studios`, then `execute_luau` (Edit): `local K=require(game.ServerStorage.MCPKit) return K.tree("game.ReplicatedStorage", 2) .. "\n" .. K.tree("game.ServerScriptService", 2)` — expect `Kit` with `VFX/UI/Net` and `Kit` with `PlayerData/DebugHooks/DevTools`.
7. Wrap up with next steps:
   - For best results, start Claude Code **inside the project folder** from now on (loads its `CLAUDE.md`; the session hook keeps Rojo running).
   - Offer to write `docs/design.md` together (game-design skill: a brief of at most 3 questions, recorded in `docs/design.md` and `assets/art.json`) before building features.
