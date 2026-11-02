---
name: import
description: Turn an existing Roblox game (a place with scripts and UI built in Studio) into a moonbrick project, so its code lives in files Claude can edit fast and safely. Use when the user wants Claude to work on a game they already have.
argument-hint: "[path to .rbxl, or project name]"
disable-model-invocation: true
---

# Import an existing game

The plugin root is two folders above this skill's base directory (`<base>/../..`); call it `KIT`. Uses pinned Rojo 7.7.1 `syncback` to read a saved `.rbxl` or `.rbxlx`; fidelity has specific limits below.

1. **Get a place file.** Ask the user to save their game from Studio: File → **Save to File As…** → `.rbxl`. (Publishing alone isn't enough; syncback reads a local file.) Get the path.
2. **Project folder + name** (default `~/RobloxProjects/<game-name>`), then create it like `/moonbrick:new`: `bash "KIT/scripts/new-project.sh" "<dir>" "<name>"` (tell the user what gets installed first if Rokit is missing).
3. **Import:** `bash "KIT/scripts/import-place.sh" "<dir>" "<path/to/place.rbxl>"`. Requires a fresh scaffold. Stages native syncback, validates, then promotes a service-mirroring layout for ServerScriptService/ReplicatedStorage/ReplicatedFirst/ServerStorage/StarterGui/StarterPlayer scripts. Workspace (including its scripts), terrain and lighting stay in the original place. Existing game code and reserved Kit/Tests/MCPKit collisions are refused; rename in a copy or plan custom mappings. No automatic git staging or commit.
4. **Review before running anything:** inspect `git -C "<dir>" diff --stat`, untracked imported files, and `.moonbrick/import-report.json`. Read every imported script/model; the advisory scan is not a security certificate and can flag comments or miss obfuscated code. Do not playtest untrusted scripts until reviewed. Run `bash "<dir>/tools/check.sh"`; summarize imported diagnostics by kind. Preserve strict kit libraries; relax legacy game code only with an explicit compatibility decision. Previous mappings are in `.moonbrick/backups/`.
5. **Connect safely:** the user opens the **same** place in Studio, then Rojo → Connect. Rojo shows a diff; it should be empty or tiny (kit files added). If it wants to delete or change many things, stop and investigate before accepting.
6. Commit only the reviewed import files, then `/moonbrick:review` and a design doc if needed. Never delete the original saved place.

## Fidelity limits

- **World stays in the place:** Workspace (including its scripts), terrain, Lighting and Atmosphere are not imported. Keep the original place open when connecting; a rebuilt file is not a replacement for the game.
- **StarterPlayer settings:** only `StarterPlayerScripts` and `StarterCharacterScripts` are imported. Properties such as `CharacterWalkSpeed` stay in the original place; add reviewed mappings if a standalone rebuild needs them.
- **Script line endings:** Rojo normalizes CRLF to LF in script Source on rebuild. Convert in a copy first if that matters; never rewrite the user's saved place.
- **Reference attributes:** Rojo adds `Rojo_Id` and `Rojo_Target_<property>` attributes to keep links (PrimaryPart, Motor6D parts). Don't use those names for game data; review them in the connection diff.
- **Sibling order:** directory-backed children rebuild in name order. Keep model blobs or set `LayoutOrder` where UI order matters.

Not verified by the offline test: terrain voxels, rig playback, rendered UI, uploaded mesh/animation dependencies and the live connection diff. Test method and exact rules: `KIT/docs/IMPORT-FIDELITY.md` (regression: `python "KIT/scripts/test-import-fidelity.py"`).
