---
name: game-systems
description: How to write Roblox gameplay code with moonbrick's libraries (Kit.VFX, Kit.UI, Kit.Net, Kit.PlayerData, DebugHooks) and server-authoritative patterns. Use before writing or changing any gameplay feature, UI, remote, effect, economy, or saved data in a Roblox project.
---

# Game systems

Write features on top of the Kit libraries instead of from scratch: less code, consistent look, and security/data-safety built in. Paths in a moonbrick project:

```lua
local Kit = game:GetService("ReplicatedStorage"):WaitForChild("Kit")
local VFX = require(Kit:WaitForChild("VFX"))   -- server or client
local UI  = require(Kit:WaitForChild("UI"))    -- client
local Net = require(Kit:WaitForChild("Net"))   -- both
local ServerKit = game:GetService("ServerScriptService"):WaitForChild("Kit")
local PlayerData = require(ServerKit:WaitForChild("PlayerData")) -- server
local DebugHooks = require(ServerKit:WaitForChild("DebugHooks")) -- server
```
**Exact signatures, types and options for every Kit function are in `tools/KIT_API.md` (~15 KB).** Read that card instead of the library source; open `src/kit/` only when the card doesn't answer the question.

## Non-negotiables
1. **Server is the authority.** Clients ask (`Net.fireServer`), the server decides (prices, cooldowns, damage, rewards) and tells clients (`Net.fire`). Never trust a client-sent amount, price, position or target without checking it against server state.
2. **Every client→server remote goes through `Net.on`/`Net.handle`** with a validator per argument (`Net.string(max)`, `Net.int(min,max)`, `Net.number(min,max)`, `Net.boolean()`, `Net.vector3(max)`, `Net.instance(class, ancestor)`, `Net.oneOf(...)`, `Net.optional(v)`) and a sensible `rate`. Then still check game rules (owns item? close enough? cooldown over?).
3. **Saved data through `PlayerData`.** One start per game. `update` is a nonyielding transaction: errors/yields/invalid values are cancelled; keep remotes and saves outside it. Check `save`'s boolean before reporting durability. Add template fields to reconcile; renames/removals/store-name changes require a migration plan. Studio defaults to memory, live testing uses a separate test experience/store. Lost sessions become inaccessible and kick by default. Saved data that fails validation is never loaded or overwritten (player gets `onLoadFailed`); to recover, set `onInvalidData = PlayerData.sanitize` or a custom nonyielding fix-up — the original is kept in the record's `backups`.
4. **UI follows server state.** Show/hide on server events, not only in the UI's own click handlers.
5. **Debug hooks for every feature** (`DebugHooks.register(name, { action = fn })`) returning short status strings, so playtests can drive it without clicking.
6. **Juice every reward and state change** (see game-design): use VFX + UI animation, not instant silent changes.

## Library cheat sheet
**VFX** (`opts`: `color`, `color2`, `size`, `time`, `count`, `texture`)
- World (server = everyone sees, client = local only): `shockwave(pos)`, `sphere(pos)`, `pillar(pos)`, `burst(partOrAttachmentOrPos, {count})`, `impact(pos, {pillar=true})` (combo), `aura(part) -> remove()`, `glow(part) -> (emitter, light)` (idle pickup sparkle), `highlight(model) -> Highlight`.
- Screen (client only): `shake(duration, strength)`, `flash()`, `fovPunch(degrees)`, `grade({color, contrast, saturation, bloom})`, `title(text)`.
- Custom Scriptable cameras: `camera.CFrame = cf * VFX.shakeOffset()`. Helpers: `VFX.tween(inst, time, props, style?, dir?)`, `VFX.numSeq{{t,v},...}`, `VFX.Textures.Sparkle/Fire/Smoke`.

**UI** (`UI.Theme` holds colours/font/corner — restyle there, not per screen)
- `UI.screen(name)`, `UI.panel({size, title})`, `UI.button({text, style="primary"|"secondary"|"danger"|"success", onClick, pulse})`, `UI.label({text})`, `UI.show(gui, visible)` (pop animation, safe to spam), `UI.toast(text)`.
- Buttons already have hover/press feedback, gamepad selection and a 48 px touch minimum.

**Net**: server `on(name, validators, handler, {rate})`, `handle(...)` (returns values), `declare(name)` (server→client events, so clients can listen first), `fire(player, name, ...)`, `fireAll(name, ...)`; client `fireServer`, `listen(name, fn)`, `invoke`.
Inspect server `Net.stats()` for copied per-remote `total`, `reasons` and `distinctPlayers` (currently connected rejected players, cleared on leave). Totals last for this server; reasons are truncated to 160 bytes and capped at 16 buckets including `other`. Persistent rejections emit an event-driven summary at most once per remote per 60 seconds after its first warning; use counters for monitoring between summaries.

**PlayerData**: `start({template, leaderstats={"Coins"}, name?, autosave?, studioStore?="memory"|"live", onLoadFailed?, onSessionLost?, onSaveInvalid?, onInvalidData?})`, `get(player)`, `wait(player)`, `set`, `increment`, `update(player, fn)`, `save(player)`, `loaded:Connect/Once/Wait` `(player, data)` with the live table. `onSaveInvalid(player, reason)` fires when live data becomes unsaveable (NaN, invalid UTF-8, mixed keys); default kicks, keeping the last good save.

**Server genre systems**: `Cooldown.new(clock?)` → `use(player, seconds)`, `remaining`, `clear`, `prune`; `Round.new({minPlayers, intermission, duration, results, clock?})` → `step(serverPlayerCount)`, `snapshot`, Studio-driver `skip`; `Economy.buy(data, serverCatalog, itemId)` / `award(data, amount)` are pure integer-currency rules for `PlayerData.update`. Clear player-keyed state on leave. These helpers do not process paid product receipts.

## Recipes
Start from a checked recipe instead of writing from scratch: `tools/recipes/` has `Data` (the one `PlayerData.start`), `Pickups` (touch-to-collect saved coins), `Ability` (Q/X/touch area attack with cooldown + VFX) and `Shop` (server-priced purchase + UI). Copy each recipe's `server/`, `client/`, `shared/` files into `src/server/`, `src/client/`, `src/shared/`, then adapt names and numbers. They already pass `tools/check.sh`.
**Round loop** — one `Round.new` controller stepped on one server loop, broadcast `snapshot` with `Net.fireAll`, clients render it; hooks `skip`, `state`.

## Before you finish a feature
`bash tools/check.sh` → specs for rule-heavy logic in `tests/` → playtest recipe (studio skill) including UI recording → `K.audit()` (Edit mode) → commit.
