<p align="center">
  <img src=".github/assets/banner.png" alt="Moonbrick: build Roblox games at the speed of thought" width="100%">
</p>

<p align="center">
  <b>A Claude Code plugin that makes AI genuinely good at Roblox development.</b><br>
  Real files, real type checking, real playtests, and visuals that don't look like a placeholder.
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-8b5cf6?style=flat-square"></a>
  <img alt="Version" src="https://img.shields.io/badge/version-0.1.0-ff6b6b?style=flat-square">
  <img alt="Claude Code plugin" src="https://img.shields.io/badge/Claude%20Code-plugin-d97757?style=flat-square">
  <img alt="Luau" src="https://img.shields.io/badge/Luau-strict-00a2ff?style=flat-square">
  <img alt="Rojo" src="https://img.shields.io/badge/Rojo-7.7-e13835?style=flat-square">
  <img alt="Platforms" src="https://img.shields.io/badge/Windows%20%7C%20macOS-supported-555?style=flat-square">
</p>

<p align="center">
  <a href="#-install">Install</a> ·
  <a href="#-what-you-get">Features</a> ·
  <a href="#-how-it-works">How it works</a> ·
  <a href="#-game-libraries">Libraries</a> ·
  <a href="#-roadmap">Roadmap</a>
</p>

---

<p align="center">
  <img src=".github/assets/showcase-leer.jpg" alt="Reyna's Leer from Valorant, built in Roblox with Moonbrick" width="100%">
  <br><sub><i>Reyna's Leer from Valorant, built end-to-end with Moonbrick: first-person viewmodel, cast choreography, an eye that flies through walls, and Nearsight. Every texture was drawn by code, uploaded, playtested and screenshot-reviewed by Claude.</i></sub>
</p>

## ✨ Why Moonbrick

AI can write Luau, but Roblox development with AI usually goes like this: slow tool calls that dump walls of text, scripts edited blind inside Studio, bugs found only after a playtest, and results that *work* but look low budget.

Moonbrick fixes the workflow end to end:

| Without Moonbrick | With Moonbrick |
|---|---|
| Claude edits scripts through Studio, one slow call at a time | Claude edits **real files**; Rojo syncs them into Studio instantly |
| Bugs show up mid-playtest | **Strict type checking + linting** catches them in ~3 s, before you press Play |
| Testing a feature takes 15+ Studio calls | **~5 calls**: debug hooks drive the feature, recorders capture UI/camera/effects, logs come back filtered |
| Inspecting the game returns ~20,000 characters | Compact helpers return **~100** |
| Every feature written from scratch | **Ready-made systems**: VFX, UI, secure remotes, saved data |
| "It works" = done | **Design-first**: reference images, drawn textures, screenshot review |

## 📦 Install

You need [Claude Code](https://claude.com/claude-code), [Roblox Studio](https://create.roblox.com/) with the **Studio MCP** enabled (Studio → Assistant settings), plus `git` and `curl`. On Windows, Git Bash (already required by Claude Code).

```text
/plugin marketplace add TanaTTV/Moonbrick
/plugin install moonbrick@moonbrick
```

Then start your first game:

```text
/moonbrick:new my-game
```

The first project installs [Rokit](https://github.com/rojo-rbx/rokit) and, through it, pinned versions of [Rojo](https://rojo.space), [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp), [selene](https://github.com/Kampfkarren/selene) and [StyLua](https://github.com/JohnnyMorganz/StyLua), plus the Rojo plugin for Studio. Open Studio → Plugins → **Rojo** → **Connect**, and you're building.

## 🧰 What you get

### Commands

| Command | What it does |
|---|---|
| `/moonbrick:new` | New game project: Rojo sync, strict types, linting, formatting, tests, debug hooks, git. Ready in seconds. |
| `/moonbrick:import` | Bring an **existing game** in: its scripts become files via Rojo syncback; your map stays in the place file. |
| `/moonbrick:playtest` | Verify a feature in a real playtest: unit tests, hook-driven actions, recorded UI/camera/effects, filtered error logs. |
| `/moonbrick:review` | Code, security, performance, mobile/console and **screenshot-based design** review → a prioritized fix list. |
| `/moonbrick:ship` | Pre-publish checklist including player-data safety, then a tagged release. |
| `/moonbrick:update` | Update a project's bundled Moonbrick code to the installed version. |

### Skills (load automatically when relevant)

- **`studio`**: the fast, token-efficient way to drive Roblox Studio, plus hard-won gotchas (new avatar joints, flipbook quirks, edit-mode require caching…).
- **`game-systems`**: server authority, exploit-proof remotes, data saving, and recipes (purchases, cooldowns, pickups, round loops).
- **`game-design`**: design docs, game feel ("juice"), first-time experience, mobile/console support, visual review, fair monetization.

### MCPKit (inside Studio)

A Luau helper that makes every MCP call short and its output tiny:

```lua
local K = require(game.ServerStorage.MCPKit)
K.tree("Workspace", 2)                 -- compact tree instead of 20 KB of JSON
K.test()                               -- run unit tests: "18 passed, 0 failed"
K.hook("Leer", "cast")                 -- drive a feature without clicking
K.record("ui", fn) ; K.results("ui")   -- capture what happened, frame by frame
K.logs()                               -- only warnings/errors since the mark
K.audit()                              -- deprecated APIs, unvalidated remotes, console-unfriendly input
K.toModelJson("Workspace.Map")         -- export Studio-built objects to Rojo files
```

## 🔭 How it works

```mermaid
flowchart LR
    U([You: plain-language request]) --> C[Claude Code<br/>+ Moonbrick skills]
    C -->|edits| F[(Project files<br/>src/**/*.luau)]
    F -->|tools/check.sh<br/>strict types + lint| C
    F -->|Rojo live sync| S[Roblox Studio]
    C -->|Studio MCP<br/>MCPKit one-liners| S
    S -->|tests · hooks · recorders · logs · screenshots| C
```

- **Code lives in files.** Claude uses its normal, instant file tools; Rojo mirrors them into Studio. Your hand-built map, terrain and lighting stay in the place file and are never overwritten.
- **Studio is for building and testing.** MCP calls go through MCPKit one-liners; playtests are driven by Studio-only debug hooks, so no fragile mouse simulation.
- **Everything is checked.** Strict Luau types, selene lint, unit tests in a real server VM, and screenshots for anything visual.
- **A session hook keeps `rojo serve` running** for whichever project you open.

<details>
<summary><b>Project layout</b></summary>

```text
src/server/   -> ServerScriptService.Server        src/kit/shared/  -> ReplicatedStorage.Kit
src/client/   -> StarterPlayerScripts.Client       src/kit/server/  -> ServerScriptService.Kit
src/shared/   -> ReplicatedStorage.Shared          tests/           -> ServerStorage.Tests
src/world/    -> Workspace.World                   tools/MCPKit.luau -> ServerStorage.MCPKit
```
</details>

## 🎮 Game libraries

Copied into every project under `src/kit/`, so your game never depends on the plugin at runtime.

| Library | What it gives you |
|---|---|
| **VFX** | One-call effects: shockwave, energy sphere, light pillar, bursts, auras, glows, highlights, camera shake, flash, FOV punch, colour-grade spikes, title slams |
| **UI** | Themed buttons, panels, labels and toasts with hover/press/pulse/pop animation, a 48 px touch minimum and gamepad support. Restyle everything from one theme table. |
| **Net** | Remotes with per-argument validation (rejects wrong types, NaN/∞, extra args) and per-player rate limits |
| **PlayerData** | DataStore saving with session locking, retries, autosave, shutdown saves, template upgrades, and an in-memory fallback in Studio |
| **DebugHooks** | Studio-only actions so tests can drive features without clicking; absent in live games |

```lua
-- a secure purchase in a few lines
Net.on("Buy", { Net.oneOf("Sword", "Bow") }, function(player, item)
	local data = PlayerData.get(player)
	if not data or data.Coins < Shop[item].price then return end
	PlayerData.update(player, function(d) d.Coins -= Shop[item].price; table.insert(d.Inventory, item) end)
	VFX.burst(player.Character.HumanoidRootPart)
end, { rate = 3 })
```

All libraries are strictly typed and covered by unit tests (`tests/kit/`).

## 🎨 Design-first

Good-looking games come from art, not code. Moonbrick's design workflow:

1. **Reference first.** Share screenshots of what you want; they drive every decision.
2. **Images over primitives.** Effects are built from textures on particles and billboards, drawn by code and uploaded to your account, or taken from vetted packs.
3. **Screenshot review.** Claude captures key moments in Studio (edit or play mode), compares them against your references, and fixes what's off before calling anything done.

<p align="center">
  <img src=".github/assets/leer-textures.png" alt="Textures drawn by code for the Leer ability" width="80%">
  <br><sub><i>Leer's eye and 16-frame anime flame flipbook, drawn with Python and uploaded through Studio.</i></sub>
</p>

## 🗺 Roadmap

- [ ] **Safe Creator Store assets:** search and insert with quarantine, a backdoor scan and export to files
- [ ] **Community kit library:** share and install reusable systems (shops, abilities, round loops) as kits
- [ ] Design-review rubric, lighting presets, and the texture generator as a reusable tool
- [ ] Blender → Roblox asset pipeline
- [ ] Verified macOS run (scripts are written for it; reports welcome)

See [ROADMAP.md](ROADMAP.md) for details.

## 🤝 Contributing

Issues and PRs are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Found a Roblox gotcha that cost you an hour? Add it to the `studio` skill so nobody else loses that hour.

## 🙏 Built on

[Rojo](https://rojo.space) · [Rokit](https://github.com/rojo-rbx/rokit) · [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) · [selene](https://github.com/Kampfkarren/selene) · [StyLua](https://github.com/JohnnyMorganz/StyLua) · [Claude Code](https://claude.com/claude-code) · the Roblox Studio MCP

<p align="center"><sub>MIT © TanaTTV · Not affiliated with Roblox Corporation or Anthropic.</sub></p>
