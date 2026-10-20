# Moonbrick Kit API

Generated from the Kit sources by `scripts/kit-api.py`; do not edit by hand.
Use this card for exact signatures. Open the Kit source only when the card is not enough.
`ReplicatedStorage`/`ServerScriptService` mean `game:GetService(...)`; on the client use `:WaitForChild("Kit")`.
`Mod.fn(self: Obj, ...)` is a method: call it as `obj:fn(...)` on the object returned by `Mod.new`.

## Net
`local Net = require(ReplicatedStorage.Kit.Net)` — both

> Net: named remotes with server-side argument validation and per-player rate limiting.
> Clients are untrusted: every argument a client sends is checked against a validator list before
> your handler runs, extra arguments are rejected, and NaN/inf numbers never get through.
>
> Server:
> Net.on("BuyItem", { Net.string(32), Net.int(1, 99) }, function(player, itemId, qty) ... end, { rate = 5 })
> Net.handle("GetPrice", { Net.string(32) }, function(player, itemId) return 100 end)
> Net.fire(player, "Notify", "Saved!")   Net.fireAll("RoundStarted", 3)
> Net.stats() -- copied rejection totals/reasons and distinct currently connected players per remote
> Client:
> Net.fireServer("BuyItem", "sword", 1)   Net.listen("Notify", function(msg) ... end)
> local price = Net.invoke("GetPrice", "sword")

```lua
export type Validator = (value: any) -> (boolean, string?)
export type Options = {
	rate: number?, -- max calls per second per player (default 10); bursts up to the same number
	maxInFlight: number?, -- maximum yielding request handlers per player (default 4)
}
export type RejectionStats = {
	total: number,
	reasons: { [string]: number },
	distinctPlayers: number,
}
```

- `Net.string(maxLength: number?): Validator`
- `Net.number(min: number?, max: number?): Validator`
- `Net.int(min: number?, max: number?): Validator`
- `Net.boolean(): Validator`
- `Net.vector3(maxMagnitude: number?): Validator`
- `Net.instance(className: string, ancestor: Instance?): Validator`
  An Instance of the given class (IsA). Optionally require it to be a descendant of `ancestor`.
- `Net.oneOf(...: any): Validator`
  One of a fixed set of values (e.g. item ids, enum-like strings).
- `Net.optional(validator: Validator): Validator`
- `Net.check(validators: { Validator }, args: { any }, count: number): (boolean, string?)`
  Check an argument list against validators. Exposed for tests and custom remotes.
- `Net.stats(): { [string]: RejectionStats }`
  Server-local lifetime counters; player identities are never exposed or retained after leave.
- `Net.on(name: string, validators: { Validator }, handler: (Player, ...any) -> (), opts: Options?)`
  Server: handle a client -> server event.
- `Net.handle(name: string, validators: { Validator }, handler: (Player, ...any) -> ...any, opts: Options?)`
  Server: answer a client -> server request. Invalid or rate-limited requests return nil.
- `Net.declare(name: string)`
  Server: create an event the server fires to clients (so clients can listen before the first fire).
- `Net.fire(player: Player, name: string, ...: any)`
- `Net.fireAll(name: string, ...: any)`
- `Net.fireServer(name: string, ...: any)`
  Client side.
- `Net.listen(name: string, handler: (...any) -> ()): RBXScriptConnection`
- `Net.invoke(name: string, ...: any): ...any`

## VFX
`local VFX = require(ReplicatedStorage.Kit.VFX)` — both (screen effects: client)

> VFX: one-call visual effects.
> World effects (shockwave, sphere, pillar, burst, aura, highlight, impact) work on server or client:
> called on the server everyone sees them; called on a client only that player does.
> Screen effects (shake, flash, fovPunch, grade, title) are client-only.

```lua
export type ImpactOptions = Options & { pillar: boolean? }
export type GradeOptions = Options & { contrast: number?, saturation: number?, bloom: number? }
export type Options = {
	color: Color3?, -- main colour (default gold)
	color2: Color3?, -- secondary colour for gradients (default purple)
	size: number?, -- final size in studs (effect-specific default)
	time: number?, -- duration in seconds (effect-specific default)
	count: number?, -- particle count for bursts
	texture: string?, -- particle texture (default VFX.Textures.Sparkle)
}
```

- `VFX.Textures = { Sparkle, Fire, Smoke }`
  Particle textures that ship with Roblox (no asset upload needed).
- `VFX.Style = { titleFont = Enum.Font.FredokaOne }`
  Presentation defaults a game can restyle (V1 values by default).
- `VFX.tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween`
- `VFX.numSeq(points: { { number } }): NumberSequence`
- `VFX.shockwave(position: Vector3, opts: Options?)`
  Flat neon ring that expands outward along the ground.
- `VFX.sphere(position: Vector3, opts: Options?)`
  Translucent energy sphere that swells and fades.
- `VFX.pillar(position: Vector3, opts: Options?)`
  Beam of light from the sky that narrows to nothing.
- `VFX.burst(at: BasePart | Attachment | Vector3, opts: Options?)`
  One-shot particle burst from a part, attachment or world position.
- `VFX.aura(part: BasePart, opts: Options?): () -> ()`
  Continuous fire + sparkle aura with a glow light. Returns a function that removes it.
- `VFX.glow(part: BasePart, opts: Options?): (ParticleEmitter, PointLight)`
  Gentle idle sparkle + light for pickups and interactables. Toggle with `.Enabled` on both.
- `VFX.highlight(target: Instance, opts: Options?): Highlight`
  Coloured glow outline on a model or part. Destroy the returned Highlight to remove it.
- `VFX.impact(position: Vector3, opts: ImpactOptions?)`
  Big impact combo: shockwave + energy sphere + particle burst (+ light pillar with `pillar = true`).
- `VFX.shakeOffset(): CFrame`
  Current shake offset. Scripts that drive a Scriptable camera every frame should multiply it in:
  camera.CFrame = myCFrame * VFX.shakeOffset()
- `VFX.shake(duration: number, strength: number)`
  Camera shake that decays over `duration`. Works with the default camera automatically.
- `VFX.flash(opts: Options?)`
  Full-screen flash that fades out.
- `VFX.fovPunch(amount: number, time: number?)`
  Kick the field of view out by `amount` degrees and ease it back.
- `VFX.grade(opts: GradeOptions?)`
  Temporary colour-grade + bloom spike that settles back to normal.
- `VFX.title(text: string, opts: Options?)`
  Big text that slams onto the screen, holds, and fades.

## UI
`local UI = require(ReplicatedStorage.Kit.UI)` — client

> UI: themed components with built-in juice (pop-in, hover/press feedback, pulse) that work on
> mouse, touch and gamepad. Client-only. Change UI.Theme once to restyle every screen.
>
> local gui = UI.screen("Shop")
> local panel = UI.panel({ parent = gui, size = UDim2.fromOffset(420, 300), title = "Shop" })
> UI.button({ parent = panel, text = "BUY", onClick = function() ... end })
> UI.show(panel, true)        UI.toast("Saved!")

```lua
export type Style = "primary" | "secondary" | "danger" | "success"
export type ButtonProps = {
	parent: Instance?,
	text: string,
	style: Style?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	onClick: (() -> ())?,
	pulse: boolean?, -- gentle breathing scale to draw attention
	name: string?,
}
export type LabelProps = {
	parent: Instance?,
	text: string,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	color: Color3?,
	scaled: boolean?, -- TextScaled: fills the label's box
	name: string?,
}
export type PanelProps = {
	parent: Instance?,
	size: UDim2,
	position: UDim2?, -- default: screen centre
	anchor: Vector2?,
	title: string?,
	padding: number?,
	name: string?,
}
```

- `UI.Theme = { primary, secondary, danger, success, background, surface, text, textOutline, font, corner, stroke, minTouchSize, buttonFill, buttonStroke, displayFont, panelStroke, panelTransparency, textStrokeWidth, labelStroke }`
- `UI.useTheme(patch: { [string]: any })`
  Applies a partial theme (e.g. from the game's art direction) in one call.
- `UI.screen(name: string, displayOrder: number?): ScreenGui`
  Full-screen ScreenGui in the local player's PlayerGui (reused if it already exists).
- `UI.button(p: ButtonProps): TextButton`
  Gradient button with stroke, hover/press feedback and optional pulse.
- `UI.label(p: LabelProps): TextLabel`
- `UI.panel(p: PanelProps): Frame`
  Rounded surface with stroke and padding. Children added later are laid out top-to-bottom.
- `UI.show(gui: GuiObject, visible: boolean)`
  Show/hide with a pop animation. Cancel superseded animations before starting a new one.
- `UI.toast(text: string, opts: { color: Color3?, duration: number? }?)`
  Short notification that stacks at the top of the screen and fades out.

## PlayerData
`local PlayerData = require(ServerScriptService.Kit.PlayerData)` — server

> PlayerData: load and save per-player data safely (server only).
> * Session locking: only the server that loaded a player's data may write it, so hopping servers
> can't duplicate items or roll progress back.
> * Retries with backoff, autosave, save on leave and on server shutdown.
> * Template reconcile: fields you add to the template later appear in old saves.
> * Studio uses memory by default. Real DataStore access requires studioStore = "live" in a test place.
>
> PlayerData.start({ template = { Coins = 0, Inventory = {} }, leaderstats = { "Coins" } })
> local data = PlayerData.wait(player)          -- table, or nil if the player left / load failed
> PlayerData.increment(player, "Coins", 5)      -- updates the data and the leaderstat
> PlayerData.update(player, function(data) table.insert(data.Inventory, "Sword") end)

```lua
export type Store = {
	UpdateAsync: (self: any, key: string, transform: (any, any?) -> ...any) -> any,
}
export type Config = {
	template: { [string]: any },
	name: string?, -- DataStore name (default "PlayerData"); change it to start fresh
	leaderstats: { string }?, -- template keys to show on the leaderboard
	autosave: number?, -- seconds between autosaves (default 60)
	store: Store?, -- override the DataStore (tests use PlayerData.memoryStore())
	studioStore: ("memory" | "live")?, -- default memory; never point Studio at production stores
	onLoadFailed: ((Player, string) -> ())?, -- default: kick with a friendly message
	onSessionLost: ((Player, string) -> ())?, -- default: kick rather than allow unsaved play
	-- Saved data that fails validation is never loaded or overwritten by default (the player gets
	-- onLoadFailed). To recover, return replacement data from a copy, e.g. `onInvalidData = PlayerData.sanitize`.
	-- Must not yield. Return nil to keep refusing. The original is kept in the record's `backups` list.
	onInvalidData: ((data: any, reason: string) -> { [string]: any }?)?,
}
export type Migrate = (data: any, reason: string) -> { [string]: any }?
export type Session = <object; methods listed below>
```

- `PlayerData.deepCopy<T>(value: T, seen: { [any]: any }?): T`
- `PlayerData.validate(value: any, ancestors: { [any]: boolean }?, depth: number?)`
- `PlayerData.reconcile(data: { [any]: any }, template: { [any]: any }): { [any]: any }`
- `PlayerData.sanitize(data: any, _reason: string?): { [string]: any }?`
- `PlayerData.memoryStore(): Store & { values: { [string]: any } }`
  In-memory store with DataStore-like copy semantics. Used for tests and Studio without API access.
- `PlayerData.Session = Session`
- `Session.new(store: Store, key: string, template: { [string]: any }, opts: SessionOptions?): Session`
- `Session.load(self: Session): (boolean, string?)`
  Load and lock. Returns false + reason if the data is locked by a live server or the store keeps failing.
- `Session.save(self: Session, release: boolean?): (boolean, string?)`
  Write the data (refreshing the lock), or release the lock with `release = true`.
  Returns false if another server has taken the lock (this session then stops saving).
- `PlayerData.loaded: RBXScriptSignal`
  Fires (player, data) when a player's data has loaded.
- `PlayerData.start(cfg: Config)`
- `PlayerData.get(player: Player): { [string]: any }?`
  The player's data table, or nil if not loaded (yet). Mutate it directly, or use set/increment/update.
- `PlayerData.wait(player: Player, timeout: number?): { [string]: any }?`
  Wait until the player's data has loaded. Returns nil if they leave or loading fails.
- `PlayerData.set(player: Player, key: string, value: any)`
- `PlayerData.increment(player: Player, key: string, delta: number): number?`
- `PlayerData.update(player: Player, fn: ({ [string]: any }) -> ()): (boolean, string?)`
  Nonyielding transaction: callback errors, yields and invalid values never partially mutate live data.
  Keep external effects (remotes, DataStores) outside the callback. Outer data table identity is preserved.
- `PlayerData.save(player: Player): boolean`
  Save now (e.g. right after a purchase). Autosave and leave/shutdown saves happen automatically.

## Cooldown
`local Cooldown = require(ServerScriptService.Kit.Cooldown)` — server

> Server-owned cooldowns for abilities, pickups, interaction and shop actions.
> One gate per action family; key by Player. Clear on PlayerRemoving (or prune expired entries).

```lua
export type Gate = <object; methods listed below>
```

- `Cooldown.new(clock: (() -> number)?): Gate`
- `Cooldown.remaining(self: Gate, key: any): number`
- `Cooldown.use(self: Gate, key: any, seconds: number): (boolean, number)`
- `Cooldown.clear(self: Gate, key: any)`
- `Cooldown.prune(self: Gate): number`

## Round
`local Round = require(ServerScriptService.Kit.Round)` — server

> Deterministic server state machine for arenas, collection rounds, obbies and survival games.
> Call step(serverPlayerCount) on one bounded loop. Broadcast snapshot only on changes/whole seconds.

```lua
export type State = "Waiting" | "Intermission" | "Playing" | "Results"
export type Config = {
	intermission: number?,
	duration: number?,
	results: number?,
	minPlayers: number?,
	clock: (() -> number)?,
}
export type Snapshot = { state: State, remaining: number, roundId: number }
export type Controller = <object; methods listed below>
```

- `Round.new(config: Config?): Controller`
- `Round.snapshot(self: Controller): Snapshot`
- `Round.step(self: Controller, playerCount: number): (Snapshot, boolean)`
- `Round.skip(self: Controller): boolean`

## Economy
`local Economy = require(ServerScriptService.Kit.Economy)` — server

> Pure, nonyielding in-game currency rules. Call only with server catalog/data, inside PlayerData.update.
> This is not developer-product receipt processing or proof of a durable save.

```lua
export type Data = { Coins: number, Inventory: { string } }
export type Item = { price: number }
```

- `Economy.award(data: Data, amount: number): (boolean, string)`
- `Economy.buy(data: Data, catalog: { [string]: Item }, itemId: string): (boolean, string)`

## DebugHooks
`local DebugHooks = require(ServerScriptService.Kit.DebugHooks)` — server (Studio only)

> Studio-only test hooks: features register actions that MCP can call with K.hook(feature, action, ...).
> Nothing is created outside Studio, so published games are unaffected.

- `DebugHooks.register(feature: string, actions: { [string]: (...any) -> ...any })`
