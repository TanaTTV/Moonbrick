# Moonbrick Kit API: creative modules (Fx, Motion, Pose, Audio, Tex, Geo)

Generated from the Kit sources by `scripts/kit-api.py`; do not edit by hand.
Use this card for exact signatures. Open the Kit source only when the card is not enough.
`ReplicatedStorage`/`ServerScriptService` mean `game:GetService(...)`; on the client use `:WaitForChild("Kit")`.
`Mod.fn(self: Obj, ...)` is a method: call it as `obj:fn(...)` on the object returned by `Mod.new`.

## Fx
`local Fx = require(ReplicatedStorage.Kit.Fx)` — client (presentation; on the server every part replicates)

> Fx: composable effects. An effect is a list of timed layers (particles, growing/shrinking meshes,
> beams, lights, debris, sound, camera, markers) that one shared scheduler plays together.
>
> local Burst = Fx.define({ name = "Burst", layers = {
> { kind = "mesh", shape = "ball", material = "Neon", color = "core",
> keys = { { t = 0, size = 1 }, { t = 0.15, size = 8, ease = "expoOut" }, { t = 0.4, size = 9, transparency = 1 } } },
> { kind = "particles", at = 0.02, texture = "spark", count = 30, color = "glow", speed = { 30, 60 } },
> { kind = "sound", at = 0, id = Audio.Builtin.explosion },
> { kind = "camera", at = 0, shake = { 0.4, 1.2 } },
> { kind = "event", at = 0.05, name = "impact" },
> } })
> local handle = Fx.play(Burst, CFrame.new(position), { scale = 1.5, palette = { core = Color3.new(1, 0.4, 0.1) } })
> handle:on("impact", function() ... end) ; handle:freeze(0.08) -- hitstop
>
> Colours can be role names ("core", "glow", "accent", "dark", "smoke", "spark") resolved from the
> options palette, then the definition's palette, then `Fx.Palette`, so one definition restyles per game.
> Play effects on CLIENTS (presentation); keep damage and rules on the server and broadcast with Net.
> `Fx.emit` also plays editor-authored instance effects (EmitDelay/EmitCount/EmitDuration attributes).

```lua
export type Quality = "Low" | "Medium" | "High"
export type ColorSpec = Color3 | string | ColorSequence | { Color3 | string }
export type NumberKeys = number | { any } -- constant, or { {t, value, envelope?}, ... } over normalised life
export type MeshKey = {
	t: number,
	size: (number | Vector3)?,
	transparency: number?,
	color: (Color3 | string)?,
	offset: CFrame?,
	ease: Motion.Ease?,
}
export type Layer = {
	kind: "particles" | "mesh" | "beam" | "light" | "sound" | "camera" | "debris" | "event",
	name: string?,
	at: number?,
	offset: CFrame?,
	minQuality: Quality?,
	-- particles
	texture: string?,
	flipbook: number?,
	count: number?,
	rate: number?,
	duration: number?,
	lifetime: { number }?,
	speed: { number }?,
	spread: number?,
	drag: number?,
	acceleration: Vector3?,
	size: NumberKeys?,
	transparency: NumberKeys?,
	color: ColorSpec?,
	lightEmission: number?,
	brightness: number?,
	rotation: { number }?,
	rotSpeed: { number }?,
	zOffset: number?,
	shape: string?,
	shapeSize: (number | Vector3)?,
	direction: Vector3?,
	orientation: string?,
	locked: boolean?,
	squash: NumberKeys?,
	inward: boolean?, -- with `shape`: particles start on the shape and travel to its centre
	-- mesh
	material: string?,
	keys: { any }?, -- MeshKey tables: { t, size?, transparency?, color?, offset?, ease? }
	spin: number?,
	decal: string?, -- Tex name drawn on the mesh's top face (fades with the mesh), e.g. "crack"
	-- beam
	from: Vector3?,
	to: Vector3?,
	width: { { number } }?,
	segments: number?,
	curve: number?,
	-- light
	range: number?,
	lightKeys: { { number } }?,
	-- sound
	id: string?,
	volume: number?,
	pitch: (number | { number })?,
	-- camera
	shake: { number }?, -- { duration, strength }
	fov: { number }?, -- { degrees, seconds }
	flash: { color: (Color3 | string)?, time: number? }?,
	grade: { color: (Color3 | string)?, contrast: number?, saturation: number?, time: number? }?, -- screen colour grade
	-- debris
	gravity: number?,
	sizeRange: { number }?,
}
export type Definition = {
	name: string,
	layers: { Layer },
	palette: { [string]: Color3 }?,
	duration: number?,
}
export type PlayOptions = {
	scale: number?,
	palette: { [string]: Color3 }?,
	timeScale: number?,
	quality: Quality?,
	parent: Instance?,
	follow: (BasePart | Attachment)?, -- keep the effect attached to a moving part
	camera: boolean?, -- false disables camera layers (default: on, scaled by distance)
	sound: boolean?, -- false mutes sound layers
	onDone: (() -> ())?,
}
export type Handle = {
	time: number,
	finished: boolean,
	root: Model,
	on: (self: Handle, name: string, fn: () -> ()) -> Handle,
	setTimeScale: (self: Handle, scale: number) -> (),
	freeze: (self: Handle, seconds: number) -> (),
	stop: (self: Handle) -> (),
}
```

- `Fx.Palette = { core, glow, accent, dark, smoke, spark }`
  Default palette roles. Games override per effect or globally (`Fx.Palette.core = ...`).
- `Fx.getQuality(): Quality`
  Current global quality. Defaults from the player's graphics setting on clients, High on servers.
- `Fx.setQuality(quality: Quality?)`
- `Fx.countFor(count: number, quality: Quality, scale: number?): number`
  Particle count after the quality multiplier (pure; tested).
- `Fx.allowed(layer: Layer, quality: Quality): boolean`
  Whether a layer runs at `quality` (pure; tested).
- `Fx.colorSequence(spec: ColorSpec?, palette: { [string]: Color3 }?): ColorSequence`
  ColorSpec → ColorSequence using the palette (pure).
- `Fx.numberSequence(keys: NumberKeys?, default: number, scale: number?): NumberSequence`
  NumberKeys → NumberSequence, multiplied by `scale` (pure).
- `Fx.layerEnd(layer: Layer): number`
  Seconds until a layer has fully finished (pure; tested): start + active time + longest lifetime.
- `Fx.length(def: Definition): number`
  Total length of a definition in seconds (pure).
- `Fx.key(t: number, fields: KeyFields?): MeshKey`
- `Fx.define(def: Definition): Definition`
  Validates and returns a definition (errors name the bad layer).
- `Fx.setGlobalTimeScale(scale: number)`
  Global time scale for every playing effect and the shared scheduler (0 freezes a frame for review).
- `Fx.live(): number`
  Live effect count (for leak tests and budgets).
- `Fx.play(def: Definition, origin: CFrame | BasePart | Attachment, opts: PlayOptions?): Handle`
  Plays a definition at `origin` (a CFrame, or a part/attachment it starts from). Returns a Handle.
- `Fx.emit(template: Model | BasePart, cframe: CFrame, opts: PlayOptions?): Handle`
  Plays a copy of an editor-authored effect (a Model or BasePart) at `cframe`; copies are pooled.

## Motion
`local Motion = require(ReplicatedStorage.Kit.Motion)` — both

> Motion: easing curves, keyframe tracks and springs on the shared Scheduler.
> Pure helpers (`ease`, `sample`, `springStep`) need no engine, so timing is unit tested.
>
> Motion.to(frame, { Position = UDim2.fromScale(0.5, 0.4) }, { time = 0.3, ease = "backOut" })
> Motion.keys(part, "Size", { { t = 0, v = Vector3.one }, { t = 0.2, v = Vector3.one * 6, ease = "expoOut" } })
> local s = Motion.spring(0, { speed = 12, damping = 0.6 }) ; s.target = 1 -- s.value follows

```lua
export type Ease = string
export type Key<T> = { t: number, v: T, ease: Ease? }
export type Spring = { value: number, velocity: number, target: number, speed: number, damping: number }
export type TweenOptions = { time: number?, ease: Ease?, delay: number?, onDone: (() -> ())? }
```

- `Motion.isEase(name: string): boolean`
- `Motion.ease(name: Ease?, x: number): number`
  Eased progress for `x` in 0..1 (clamped). Unknown names fall back to linear.
- `Motion.springStep(s: Spring, dt: number)`
  Advances a damped spring by `dt` (semi-implicit Euler, sub-stepped for stability).
- `Motion.spring(initial: number, opts: { speed: number?, damping: number? }?): Spring & { stop: () -> () }`
  A spring driven by the shared scheduler until `stop` is called. Read `value`, set `target`.
- `Motion.to(inst: Instance, props: { [string]: any }, opts: TweenOptions?): () -> ()`
  Tweens properties of `inst` on the shared scheduler. Returns a cancel function.

## Pose
`local Pose = require(ReplicatedStorage.Kit.Pose)` — client (Transform does not replicate)

> Pose: rig inspection, procedural keyframed poses with markers, and helpers for uploaded animations.
>
> local rig = Pose.inspect(character)          -- { type = "R15" | "R6" | "Custom", joints = {...} }
> local Throw = Pose.clip({ name = "Throw", rig = "R15", length = 0.9,
> keys = { { t = 0, joints = {} },
> { t = 0.35, ease = "quadOut", joints = { RightShoulder = CFrame.Angles(0, 0, math.rad(160)) } },
> { t = 0.55, ease = "expoOut", joints = { RightShoulder = CFrame.Angles(0, 0, math.rad(-40)) } } },
> markers = { { t = 0.5, name = "release" } } })
> Pose.play(character, Throw):on("release", function() ... end)
>
> Procedural poses write joint `Transform` before physics (PreSimulation), which works for both
> Motor6D and AnimationConstraint joints. Transform is NOT replicated: play poses on every client that
> should see them (broadcast with Net), never only on the server. Joint names are the rig's own:
> R15 (`RightShoulder`, `Waist`, …) and R6 (`Right Shoulder`, `RootJoint`, …) are different rigs with
> different joint axes, so a clip declares its rig and refuses the other one.

```lua
export type RigType = "R15" | "R6" | "Custom"
export type Joint = { instance: Instance, kind: "Motor6D" | "AnimationConstraint" }
export type Rig = { type: RigType, model: Model, joints: { [string]: Joint }, humanoid: Humanoid?, animator: Animator? }
export type Key = { t: number, joints: { [string]: CFrame }, ease: Motion.Ease? }
export type Clip = {
	name: string,
	rig: RigType | "Any",
	length: number,
	looped: boolean?,
	keys: { Key },
	markers: { { t: number, name: string } }?,
}
export type PlayOptions = { speed: number?, fadeIn: number?, fadeOut: number?, weight: number? }
export type Track = {
	clip: Clip,
	time: number,
	finished: boolean,
	on: (self: Track, marker: string, fn: () -> ()) -> Track,
	stop: (self: Track, fade: number?) -> (),
}
```

- `Pose.R15 = {  }`
- `Pose.R6 = { "RootJoint", "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }`
- `Pose.classify(names: { string }): RigType`
  Rig type from a list of joint names (pure; tested).
- `Pose.inspect(model: Model): Rig`
  Finds a character's joints (Motor6D and AnimationConstraint) and classifies the rig.
- `Pose.clip(clip: Clip): Clip`
  Validates and returns a clip (keys sorted by time, markers inside the clip).
- `Pose.sample(clip: Clip, t: number): { [string]: CFrame }`
  The joint offsets of a clip at time `t` (pure; tested). A joint missing from a key holds identity
  there, so poses return to rest unless every key names the joint.
- `Pose.play(model: Model, clip: Clip, opts: PlayOptions?): Track`
  Plays a clip on a character. Joints the clip doesn't name keep their Animator pose.
- `Pose.stopAll(model: Model, fade: number?)`
  Stops every procedural pose on a model.
- `Pose.activeCount(): number`
  Number of models with active procedural poses (for leak tests).
- `Pose.track(model: Model, animation: string | Animation, opts: { priority: Enum.AnimationPriority?, looped: boolean? }?): AnimationTrack`
  Loads an uploaded animation on a character's Animator. Animations must be owned by the experience
  owner (or Roblox) to play in a published game.
- `Pose.marker(track: AnimationTrack, name: string, fn: (string) -> ()): RBXScriptConnection`
  Connects to a named marker (KeyframeMarker) of an uploaded animation.

## Audio
`local Audio = require(ReplicatedStorage.Kit.Audio)` — both (client = local only)

> Audio: sound groups, a project cue map and positional playback on Roblox's Sound API.
> Called on a client, only that player hears it; on the server, everyone does.
>
> Audio.define({ Boom = { id = Audio.Builtin.explosion, volume = 0.9, pitch = { 0.92, 1.05 }, group = "SFX" } })
> Audio.play("Boom", impactPosition)                   -- 3D at a position (or a part/attachment)
> Audio.play("Click")                                  -- 2D (UI)
> local amb = Audio.loop("Wind", nil, { fade = 2 }) ; amb.stop(1.5)
>
> Use your own uploads, Roblox's built-in sounds (`Audio.Builtin`) or Creator Store audio you are
> allowed to use. Nothing here uploads or publishes audio.

```lua
export type Group = "Master" | "Music" | "SFX" | "UI" | "Ambience"
export type Cue = {
	id: string, -- rbxassetid://… or rbxasset://sounds/…
	volume: number?,
	pitch: (number | { number })?, -- fixed, or { min, max } for variation
	group: Group?,
	rolloff: { number }?, -- { min, max } distance in studs for 3D sounds
	looped: boolean?,
	start: number?, -- TimePosition to start from
}
export type Where = Vector3 | BasePart | Attachment
export type PlayOptions = { volume: number?, pitch: number?, delay: number? }
export type Loop = { sound: Sound, stop: (fade: number?) -> () }
```

- `Audio.Builtin = { explosion, water, jump, land, footstep, getUp, falling, swim, tick }`
  Sounds that ship with every Roblox client: usable without uploads.
- `Audio.group(name: Group): SoundGroup`
  The SoundGroup for `name` under SoundService (created once; all groups route into Master).
- `Audio.setVolume(name: Group, volume: number)`
- `Audio.define(map: { [string]: Cue })`
  Adds or replaces cues by name.
- `Audio.cue(name: string): Cue?`
- `Audio.pitchFor(cue: Cue, rand: number?): number`
  Picks a pitch from a cue's fixed value or { min, max } range; `rand` (0..1) is injectable for tests.
- `Audio.play(nameOrId: string, where: Where?, opts: PlayOptions?): Sound`
  Plays a cue (or a raw sound id) once. Returns the Sound, which cleans itself up.
- `Audio.loop(nameOrId: string, where: Where?, opts: { fade: number?, volume: number? }?): Loop`
  Starts a looping cue (ambience, music) with an optional fade-in. `stop(fade)` fades it out.

## Tex
`local Tex = require(ReplicatedStorage.Kit.Tex)` — client

> Tex: original effect textures (white shapes with alpha; Color tints them). No borrowed art.
>
> Tex.apply(emitter, "spark")          -- particles/beams/trails: a texture FILE (see below)
> Tex.apply(decal, "crack")            -- decals/images/meshes: drawn at runtime (EditableImage)
>
> Verified in Studio 0.743: ImageLabel, Decal (and MeshPart/SurfaceAppearance) render runtime
> EditableImages; ParticleEmitter, Beam and Trail accept them but render nothing. So those three use
> files rendered by `python scripts/fxtex.py`: `Tex.usePreview()` after `fxtex.py preview` (Studio on
> this computer only), or `Tex.useFiles({ spark = "rbxassetid://…" })` after you upload them.
> Without either they fall back to stock Roblox particle textures, so nothing is ever invisible.
> Runtime images: draw on the CLIENT (they don't replicate); published games need Game Settings →
> Security → "Allow Mesh & Image APIs". `Tex.alpha` is the pure pixel function shared with fxtex.py.

```lua
export type Name =
export type Options = {
	size: number?, -- pixels per side (or per cell for flipbooks), default 128
	seed: number?,
	softness: number?, -- edge falloff, 0..1
	thickness: number?, -- ring/streak width, 0..1
	points: number?, -- star/spark points
	flipbook: number?, -- 2, 4 or 8: animated grid of `flipbook`² frames
}
```

- `Tex.Flipbooks = { smoke = 4, wisp = 4 } :: { [string]: number }`
  Flipbook grids of the rendered files (fxtex.py draws these as animated sheets).
- `Tex.useFiles(map: { [string]: string })`
  Uses uploaded texture files: { name = "rbxassetid://…" } (overrides preview and stock).
- `Tex.usePreview(base: string?)`
  Uses the local Studio preview copied by `python scripts/fxtex.py preview` (this computer only).
- `Tex.fileFor(name: string): (string, number?)`
  The file texture for a particle/beam/trail and whether it is a flipbook sheet (pure).
- `Tex.Fallback = { glow, core, ring, spark, star, streak, smoke, dust, shard, crack, wisp }`
  Stock Roblox textures used when no file is configured (and when runtime drawing fails).
- `Tex.noise(x: number, y: number, seed: number?, octaves: number?): number`
- `Tex.alpha(name: string, u: number, v: number, opts: Options?, frame: number?): number`
  Alpha (0..1) of texture `name` at u, v in -1..1. `frame` (0..1) animates flipbook textures.
- `Tex.get(name: string, opts: Options?): any`
  The drawn texture as Content, or nil when runtime images are unavailable here.
- `Tex.apply(target: Instance, name: string, opts: Options?)`
  Puts texture `name` on a ParticleEmitter, Beam, Trail, ImageLabel/ImageButton or Decal.
  Falls back to a stock Roblox texture where runtime images are unavailable.
- `Tex.clear()`
  Drops cached textures (call when leaving a scene that used many).

## Geo
`local Geo = require(ReplicatedStorage.Kit.Geo)` — client or server (runtime meshes don't replicate)

> Geo: procedural meshes from Luau (EditableMesh → MeshPart), for props, architecture and effect shapes
> that parts can't make (rings, domes, lathed vases, tubes, extruded silhouettes). No Blender, no upload.
>
> local ring = Geo.cached("Ring", function(b) b:torus(4, 0.5, 48, 12) end)   -- built once, then cloned
> local part = ring:Clone() ; part.Material = Enum.Material.Neon ; part.Parent = workspace
> local vase = Geo.build(function(b)
> b:setColor(Color3.fromRGB(180, 90, 60))
> b:lathe({ Vector2.new(0, 0), Vector2.new(1.4, 0.2), Vector2.new(0.9, 2), Vector2.new(1.2, 3) }, 24)
> end)
>
> Shared vertices shade smoothly (Roblox computes normals); `b.flat = true` before building gives hard
> facets. Runtime meshes don't save with the place or replicate: build them where they are seen (client
> for effects; the server for world props that need collisions only replicates when Roblox supports it,
> so verify in a playtest). Published games need Game Settings → Security → "Allow Mesh & Image APIs".
> Approach adapted from RoClicks meshlab's lathe/tube/loft helpers (MIT); written for strict Luau here.

```lua
export type Builder = {
	mesh: EditableMesh,
	flat: boolean,
	vertex: (self: Builder, p: Vector3) -> number,
	tri: (self: Builder, a: number, b: number, c: number) -> (),
	quad: (self: Builder, a: number, b: number, c: number, d: number) -> (),
	setColor: (self: Builder, color: Color3?) -> (),
	grid: (self: Builder, rows: { { Vector3 } }, closed: boolean?) -> (),
	lathe: (
		self: Builder,
		profile: { Vector2 },
		segments: number,
		cf: CFrame?,
		radiusAt: ((number, number) -> number)?
	) -> (),
	torus: (self: Builder, radius: number, thickness: number, segments: number?, sides: number?, cf: CFrame?) -> (),
	tube: (self: Builder, path: { Vector3 }, radius: number | { number }, sides: number?) -> (),
	box: (self: Builder, cf: CFrame, size: Vector3) -> (),
	extrude: (self: Builder, outline: { Vector2 }, height: number, cf: CFrame?) -> (),
	sphere: (self: Builder, radius: number, rings: number?, segments: number?, cf: CFrame?) -> (),
	displace: (self: Builder, fn: (Vector3) -> Vector3) -> (),
	count: (self: Builder) -> number,
}
export type PartOptions = {
	name: string?,
	material: Enum.Material?,
	color: Color3?,
	anchored: boolean?,
	collision: boolean?,
}
```

- `Geo.new(): Builder`
- `Geo.toPart(builder: Builder, opts: PartOptions?): MeshPart`
  Turns a builder into a MeshPart, centred on its bounds (yields). Model space stays world space:
  the part is placed where the mesh was built around the origin.
- `Geo.build(fn: (Builder) -> (), opts: PartOptions?): MeshPart`
  Builds a MeshPart in one call (yields).
- `Geo.cached(key: string, fn: (Builder) -> (), opts: PartOptions?): MeshPart`
  A template MeshPart built once per key; Clone() it for each use (clones share the mesh data).
- `Geo.unitTorus(thickness: number?): MeshPart`
  Unit shapes used by Fx mesh layers (size 1 along each axis after Fx scales them).

## Scheduler
`local Scheduler = require(ReplicatedStorage.Kit.Scheduler)` — both

> Scheduler: one shared frame loop for Fx, Motion and Pose, instead of one connection per effect.
> Jobs are functions `step(dt) -> boolean`; returning true finishes the job. Errors are reported once
> and the job is dropped, so one broken effect never stops the others.
>
> local stop = Scheduler.every(function(dt) ... return done end)            -- Heartbeat
> local stop = Scheduler.every(fn, "PreSimulation")                         -- before physics (poses)

```lua
export type Phase = "Heartbeat" | "PreSimulation"
```

- `Scheduler.every(step: (number) -> boolean, phase: Phase?): () -> ()`
  Runs `step(dt)` every frame until it returns true or the returned function is called.
- `Scheduler.setTimeScale(scale: number)`
  Global time scale for every job: 0 freezes Fx/Pose/Motion (frame captures), 0.2 is slow motion.
- `Scheduler.getTimeScale(): number`
- `Scheduler.count(phase: Phase?): number`
  Number of live jobs (for tests and leak checks).
- `Scheduler.advance(dt: number, phase: Phase?)`
  Advances every job by `dt` without waiting for a frame. Deterministic tests and frame captures use this.
