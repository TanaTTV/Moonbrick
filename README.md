# roblox-kit

A Claude Code plugin for building Roblox games with AI — fast, safely, and with good game feel.

It connects three things that work badly on their own:
- **Claude Code** writes code quickly but can't see your game,
- the **Roblox Studio MCP** can see and drive Studio, but every call is slow and verbose,
- **Rojo** keeps your code in real files, but needs setup.

roblox-kit wires them together so Claude edits code as files (instant, type-checked, in git), uses Studio only for building and testing, and tests features in ~5 MCP calls instead of 15+.

## What you get

| | |
|---|---|
| `/roblox-kit:new` | New game project: Rojo sync, strict type checking (luau-lsp), linting (selene), formatting (StyLua), git, everything below |
| `/roblox-kit:import` | Bring an existing game in: saves its scripts into the project with Rojo syncback |
| `/roblox-kit:playtest` | Verify a feature in a real playtest: unit tests, debug-hook driven actions, recorded UI/camera/effects, error logs |
| `/roblox-kit:review` | Code, security, performance, platform and screenshot-based design review → prioritized fix list |
| `/roblox-kit:ship` | Pre-publish checklist incl. player-data safety, then a tagged release |
| `/roblox-kit:update` | Update a project's bundled kit code to the installed plugin version |

**Game libraries** (copied into each project under `src/kit/`, so games don't depend on the plugin at runtime):
- **VFX** — one-call effects: shockwave, energy sphere, light pillar, particle bursts, auras, glows, highlights, camera shake, flash, FOV punch, colour-grade spikes, title slams.
- **UI** — themed buttons/panels/labels/toasts with hover, press, pulse and pop animations; 48 px touch minimum; gamepad-friendly.
- **Net** — remotes with per-argument validation (rejects NaN/inf, wrong types, extra args) and per-player rate limits.
- **PlayerData** — DataStore saving with session locking, retries, autosave, shutdown saves, template upgrades, and an in-memory fallback in Studio.
- **DebugHooks** — Studio-only actions so tests can drive features without clicking.

**MCPKit** — a Luau helper loaded in Studio that makes MCP calls short and their output small: compact trees and property reads, bulk edits, a unit test runner, background recorders, log filtering, perf snapshot, pre-publish audit, and export of Studio-built objects to Rojo files.

**Skills** that load when relevant: `studio` (fast MCP workflow + hard-won Roblox gotchas), `game-systems` (server authority, secure remotes, data, recipes), `game-design` (design docs, game feel, first-time experience, mobile/console, visual review, fair monetization).

## Install

Requirements: [Claude Code](https://claude.com/claude-code), [Roblox Studio](https://create.roblox.com/) with the Studio MCP enabled (Studio → Assistant settings), `git`, `curl`. On Windows, Git Bash (already required by Claude Code).

```
/plugin marketplace add <github-user>/roblox-kit
/plugin install roblox-kit@roblox-kit
```

Then: `/roblox-kit:new my-game`. The first project installs [Rokit](https://github.com/rojo-rbx/rokit) and, through it, Rojo, luau-lsp, selene and StyLua (pinned versions), plus the Rojo Studio plugin.

## Daily use
1. Start Claude Code **inside your project folder** — a session hook starts `rojo serve` automatically.
2. In Studio: Plugins → Rojo → Connect (once per Studio session).
3. Ask for features in plain language. Claude writes files, runs `tools/check.sh`, and verifies with `/roblox-kit:playtest`.
4. Commit often; `/roblox-kit:ship` before publishing.

## Project layout
```
src/server/   -> ServerScriptService.Server        src/kit/shared/ -> ReplicatedStorage.Kit
src/client/   -> StarterPlayerScripts.Client       src/kit/server/ -> ServerScriptService.Kit
src/shared/   -> ReplicatedStorage.Shared          tests/          -> ServerStorage.Tests
src/world/    -> Workspace.World                   tools/MCPKit.luau -> ServerStorage.MCPKit
```
Your hand-built map, terrain and lighting stay in the place file — Rojo never overwrites them.

## Status
v0.1 — built and tested on Windows 11 with Roblox Studio and Claude Code. The shell scripts are written for macOS too but haven't been tested on a Mac yet; reports welcome.

## License
MIT
