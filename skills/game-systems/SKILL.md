---
name: game-systems
description: How to write Roblox gameplay code with roblox-kit's libraries (Kit.VFX, Kit.UI, Kit.Net, Kit.PlayerData, DebugHooks) and server-authoritative patterns. Use before writing or changing any gameplay feature, UI, remote, effect, economy, or saved data in a Roblox project.
---

# Game systems

Write features on top of the Kit libraries instead of from scratch: less code, consistent look, and security/data-safety built in. Paths in a roblox-kit project:

```lua
local Kit = game:GetService("ReplicatedStorage"):WaitForChild("Kit")
local VFX = require(Kit:WaitForChild("VFX"))   -- server or client
local UI  = require(Kit:WaitForChild("UI"))    -- client
local Net = require(Kit:WaitForChild("Net"))   -- both
local ServerKit = game:GetService("ServerScriptService"):WaitForChild("Kit")
local PlayerData = require(ServerKit:WaitForChild("PlayerData")) -- server
local DebugHooks = require(ServerKit:WaitForChild("DebugHooks")) -- server
```
Read the library source in `src/kit/` when you need details; the headers document every function.

## Non-negotiables
1. **Server is the authority.** Clients ask (`Net.fireServer`), the server decides (prices, cooldowns, damage, rewards) and tells clients (`Net.fire`). Never trust a client-sent amount, price, position or target without checking it against server state.
2. **Every client→server remote goes through `Net.on`/`Net.handle`** with a validator per argument (`Net.string(max)`, `Net.int(min,max)`, `Net.number`, `Net.vector3(max)`, `Net.instance(class, ancestor)`, `Net.oneOf(...)`, `Net.optional(v)`) and a sensible `rate`. Then still check game rules (owns item? close enough? cooldown over?).
3. **Saved data only through `PlayerData`.** One `PlayerData.start({ template, leaderstats })` per game; change values with `set`/`increment`/`update`; call `PlayerData.save(player)` right after purchases. Adding a field = add it to the template (old saves get it automatically). Renaming/removing fields needs a migration step in `update` — ask first.
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

**PlayerData**: `start({template, leaderstats={"Coins"}, name?, autosave?})`, `get(player)`, `wait(player)`, `set`, `increment`, `update(player, fn)`, `save(player)`, `loaded` event `(player, data)`.

## Recipes
**Purchase**
```lua
-- server
Net.on("Buy", { Net.oneOf("Sword", "Bow") }, function(player, itemId)
	local price = Shop[itemId].price -- server-side table, never client-sent
	local data = PlayerData.get(player)
	if not data or data.Coins < price or table.find(data.Inventory, itemId) then
		return Net.fire(player, "Toast", "Can't buy that")
	end
	PlayerData.update(player, function(d)
		d.Coins -= price
		table.insert(d.Inventory, itemId)
	end)
	PlayerData.save(player)
	Net.fire(player, "Bought", itemId)
end, { rate = 3 })
```
**Cooldown** — keep `lastUsed[player]` on the server; reject early calls in the handler; clear on `PlayerRemoving`.
**Pickups** — tag parts (`CollectionService`), set up per tag on the server, `VFX.glow` for idle, `VFX.burst` on collect, respawn with `task.delay`; add a `ProximityPrompt` if collection needs input.
**Round loop** — one server state machine (`"Intermission" | "Playing" | "Ended"`), broadcast with `Net.fireAll("Round", state, timeLeft)`, clients render it; hooks `skip`, `state`.

## Before you finish a feature
`bash tools/check.sh` → specs for rule-heavy logic in `tests/` → playtest recipe (studio skill) including UI recording → `K.audit()` → commit.
