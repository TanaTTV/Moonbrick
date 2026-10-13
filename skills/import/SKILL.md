---
name: import
description: Turn an existing Roblox game (a place with scripts and UI built in Studio) into a moonbrick project, so its code lives in files Claude can edit fast and safely. Use when the user wants Claude to work on a game they already have.
argument-hint: "[path to .rbxl, or project name]"
disable-model-invocation: true
---

# Import an existing game

The plugin root is two folders above this skill's base directory (`<base>/../..`); call it `KIT`. Uses Rojo's `syncback`, which reads a saved place file with full property fidelity.

1. **Get a place file.** Ask the user to save their game from Studio: File → **Save to File As…** → `.rbxl`. (Publishing alone isn't enough; syncback reads a local file.) Get the path.
2. **Project folder + name** (default `~/RobloxProjects/<game-name>`), then create it like `/moonbrick:new`: `bash "KIT/scripts/new-project.sh" "<dir>" "<name>"` (tell the user what gets installed first if Rokit is missing).
3. **Import:** `bash "KIT/scripts/import-place.sh" "<dir>" "<path/to/place.rbxl>"`. It switches the project to a service-mirroring layout (`src/ServerScriptService/…`, `src/ReplicatedStorage/…`, `src/StarterGui/…`, `src/StarterPlayer/…`, `src/ReplicatedFirst/…`, `src/ServerStorage/…`, `src/Workspace/…` for scripts only), runs syncback, keeps the Kit paths, and commits. Workspace parts, terrain and lighting stay in the place file.
4. **Review** what was imported: `git -C "<dir>" show --stat HEAD | tail -5`, and skim the tree (`find "<dir>/src" -maxdepth 3 | head -50`). Run `bash "<dir>/tools/check.sh"`: imported games often show many type warnings, so summarize the counts by kind instead of fixing them all — the project's `.luaurc` can be set to `"nonstrict"` if the user prefers.
5. **Connect safely:** the user opens the **same** place in Studio, then Rojo → Connect. Rojo shows a diff; it should be empty or tiny (kit files added). If it wants to delete or change many things, stop and investigate before accepting.
6. Suggest next: `/moonbrick:review` for a quality pass, and a design doc if there isn't one.
