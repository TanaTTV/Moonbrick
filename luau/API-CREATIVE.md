# Moonbrick Kit API: creative and world modules (Fx, Motion, Pose, Audio, Tex, Geo, Scene, GeoShapes, Scatter, Camera)

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
-- A colour, a palette role, a ColorSequence, or a list of colours/roles spread evenly over the lifetime.
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
	shape: string?, -- mesh: ball, block, cylinder, ring, torus, shard, wedge. Particles: Box, Sphere, Cylinder, Disc
	shapeSize: (number | Vector3)?,
	direction: Vector3?,
	orientation: string?,
	locked: boolean?,
	squash: NumberKeys?,
	inward: boolean?, -- with `shape`: particles start on the shape and travel to its centre
	-- mesh
	material: string?,
	keys: { any }?, -- MeshKey tables: { t, size?, transparency?, color?, offset?, ease? }
	spin: number?, -- degrees per second about spinAxis
	spinAxis: Vector3?, -- default X (tumble); Vector3.yAxis turns a flat ring in place
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
-- A persistent emitter layer in a `Fx.Ambience` preset. `density` is live particles per 1000 cubic studs;
-- `budget` caps them at High quality.
export type AmbienceLayer = {
	texture: string,
	density: number,
	budget: number?,
	lifetime: { number },
	size: NumberKeys,
	transparency: NumberKeys,
	color: ColorSpec,
	speed: { number }?,
	acceleration: Vector3?,
	drag: number?,
	lightEmission: number?,
	rotSpeed: { number }?,
	minQuality: Quality?,
}
export type AmbienceOptions = {
	palette: { [string]: Color3 }?,
	parent: Instance?,
	follow: (BasePart | Camera)?, -- the region keeps centred on this
	density: number?, -- multiplies every layer
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
- `Fx.preload(): boolean`
  Builds Geo's unit torus and shard now (yields) so the first effect using them doesn't stall.
  Call once from a client startup script. Returns false when meshes can't be made here.
- `Fx.setGlobalTimeScale(scale: number)`
  Global time scale for every playing effect and the shared scheduler (0 freezes a frame for review).
- `Fx.Ambience = { dust, texture, density, budget, lifetime, size, transparency, color, speed, acceleration, lightEmission, rotSpeed, fog, texture, density, budget, lifetime, size, transparency, color, speed, acceleration, lightEmission, rotSpeed, texture, density, budget, lifetime, size, transparency, color, speed, rotSpeed, minQuality, fireflies, texture, density, budget, lifetime, size, transparency, color, speed, drag, lightEmission, embers, texture, density, budget, lifetime, size, transparency, color, speed, acceleration, lightEmission, rotSpeed }`
  Ambience presets. Add your own: `Fx.Ambience.pollen = { { texture = "dust", ... } }`.
- `Fx.ambienceRate(layer: AmbienceLayer, volume: number, quality: Quality, density: number?): number`
  Emitter rate holding a layer's live particle count in a volume (pure; tested): density, then the
  budget, then the quality multiplier. Zero when the layer's minQuality rules it out.
- `Fx.ambience(region: BasePart | { center: Vector3, size: Vector3 }, preset: string, opts: AmbienceOptions?): (number?) -> ()`
  Starts a persistent particle layer in a box and returns `stop(fade)`. `region` is a part (its
  CFrame and size are read once) or { center, size }; `preset` is a `Fx.Ambience` name. It runs until
  stopped: no watchdog applies, quality changes adjust it and a global freeze holds it. Fog needs
  `Tex.usePreview` or uploaded files to look its best. Client-side; don't parent it where it replicates.
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
-- Easing names: linear, quadIn, quadOut, quadInOut, cubicOut, expoIn, expoOut, backIn, backOut,
-- elasticOut, sineInOut, anticipate. Typed as string so data tables stay easy to write; `Motion.isEase`
-- checks a name.
export type Ease = string
export type Key<T> = { t: number, v: T, ease: Ease? }
export type Spring = { value: number, velocity: number, target: number, speed: number, damping: number }
export type TweenOptions = { time: number?, ease: Ease?, delay: number?, onDone: (() -> ())? }
```

- `Motion.isEase(name: string): boolean`
- `Motion.ease(name: Ease?, x: number): number`
  Eased progress for `x` in 0..1 (clamped). Unknown names fall back to linear.
- `Motion.sample<T>(keys: { Key<T> }, t: number): T`
  Value of a keyframe track at time `t`; each key's `ease` shapes the segment that ends at it.
- `Motion.length<T>(keys: { Key<T> }): number`
  Length of a key track in seconds.
- `Motion.springStep(s: Spring, dt: number)`
  Advances a damped spring by `dt` (semi-implicit Euler, sub-stepped for stability).
- `Motion.spring(initial: number, opts: { speed: number?, damping: number? }?): Spring & { stop: () -> () }`
  A spring driven by the shared scheduler until `stop` is called. Read `value`, set `target`.
- `Motion.to(inst: Instance, props: { [string]: any }, opts: TweenOptions?): () -> ()`
  Tweens properties of `inst` on the shared scheduler. Returns a cancel function.
- `Motion.keys<T>(inst: Instance, property: string, keys: { Key<T> }, opts: { onDone: (() -> ())? }?): () -> ()`
  Plays a keyframe track on one property of `inst`. Returns a cancel function.

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

- `Pose.R15 = { Root, Waist, Neck, LeftShoulder, LeftElbow, LeftWrist, RightShoulder, RightElbow, RightWrist, LeftHip, LeftKnee, LeftAnkle, RightHip, RightKnee, RightAnkle }`
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
- `Audio.lifetime(length: number, speed: number, delay: number?): number`
  Seconds to keep a loaded one-shot before cleanup, when `Ended` never fires (pure; tested). Before
  it loads a Sound reports TimeLength 0, so only call this once it has loaded.
- `Audio.play(nameOrId: string, where: Where?, opts: PlayOptions?): Sound`
  Plays a cue (or a raw sound id) once. Returns the Sound, which cleans itself up when it ends. A cue
  with `looped = true` never ends: it plays until you destroy the Sound (prefer `Audio.loop`).
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
export type Name = "glow" | "core" | "ring" | "spark" | "star" | "streak" | "smoke" | "dust" | "shard" | "crack" | "wisp"
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
- `Tex.resetFiles()`
  Forgets `useFiles` and `usePreview`: back to stock textures. (Tests and scene changes.)
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
`local Geo = require(ReplicatedStorage.Kit.Geo)` — client (server-made meshes don't render)

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
> facets. Runtime meshes don't save with the place and DON'T render when made on the server (verified in
> Studio 0.743: clients see a "missing mesh" checker). Build them on clients: for world props, put
> ordinary parts ("spots") with a `GeoShape` attribute in the world (they save, collide and replicate)
> and call `Geo.watch(workspace)` from a client script; each spot gets its mesh and turns invisible.
> Clients allow few live growable EditableMeshes (8 in Studio 0.743), so each build is baked into a
> fixed-size copy (hundreds allowed) and the builder freed. Still prefer few distinct shapes and many
> clones: clones share one mesh.
> Published games need Game Settings → Security → "Allow Mesh & Image APIs".
> Approach adapted from RoClicks meshlab's lathe/tube/loft helpers and its "shape spot" idea (MIT).

```lua
export type Builder = {
	mesh: EditableMesh,
	flat: boolean,
	-- Per-face colour from the triangle's centre (speckles, gradients, AO); overrides setColor.
	colorAt: ((Vector3) -> Color3)?,
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
	volume: (self: Builder) -> number,
	count: (self: Builder) -> number,
}
-- A seeded random stream: `rng()` in 0..1, `rng(a, b)` between a and b.
export type Random = (number?, number?) -> number
export type PartOptions = {
	name: string?,
	material: Enum.Material?,
	color: Color3?,
	anchored: boolean?,
	collision: boolean?,
}
```

- `Geo.rng(seed: number): Random`
  A seeded random stream (pure): the same seed gives the same numbers on every client and in tests.
- `Geo.new(): Builder`
- `Geo.toPart(builder: Builder, opts: PartOptions?): MeshPart`
  Turns a builder into a MeshPart, centred on its bounds (yields). The builder can't be used afterwards. Model space stays world space:
  the part is placed where the mesh was built around the origin.
- `Geo.decode(text: string): buffer`
  Decodes base64 text into a buffer (pure).
- `Geo.unpack(part: { [string]: any }, unit: number): ({ Vector3 }, { Vector3 }, { Color3 }, { number })`
  One part of a `scripts/blender/geo_export.py` module as plain arrays (pure): positions in studs,
  normals, colours, and triangle indices (1-based).
- `Geo.model(data: { [string]: any }, opts: PartOptions?): Model`
  Rebuilds a Blender export as a Model of MeshParts, one per material, with its exact normals and
  vertex colours. Client only (yields). No upload: it shows in Studio, and in published games that allow
  Mesh & Image APIs. Parts don't collide, so pair them with invisible server Parts. `Clone()` it for
  repeats; clones share the meshes.
- `Geo.free(part: MeshPart)`
  Destroys a part from `Geo.build` and frees its mesh now. Only for parts that were never cloned: it
  blanks clones. Plain `Destroy` is enough otherwise; the mesh then goes with its last clone.
- `Geo.build(fn: (Builder) -> (), opts: PartOptions?): MeshPart`
  Builds a MeshPart in one call (yields).
- `Geo.cached(key: string, fn: (Builder) -> (), opts: PartOptions?): MeshPart`
  A template MeshPart built once per key; Clone() it for each use (clones share the mesh data).
  Yields on the first build; concurrent callers for the same key wait for that one build.
- `Geo.unitTorus(thickness: number?): MeshPart`
  Unit shapes used by Fx mesh layers (size 1 along each axis after Fx scales them).
- `Geo.unitShard(): MeshPart`
  A faceted crystal shard 1 stud wide and tall, pointing up (+Y), base at the bottom.
- `Geo.register(name: string, build: (Builder, { [string]: any }) -> (), opts: { vertexColors: boolean? }?)`
  Adds a shape `Geo.dress` and `Geo.watch` can build for spots with `GeoShape = name`. `build(b, params)`
  makes it around the origin; the mesh is then stretched to the spot's size. `params` are the spot's
  attributes. `vertexColors = true`: the shape paints itself (setColor/colorAt), else it takes the spot's Color.
- `Geo.SpotTag = "GeoSpot"`
  Tag for spots that gain a `GeoShape` after they are parented; `Geo.watch` picks these up too.
- `Geo.dress(root: Instance): number`
  Client: gives every BasePart under `root` that has a `GeoShape` attribute its generated mesh, sized
  to the part. The part stays as an invisible collision/hit proxy, and a mesh copies the spot's
  Transparency once, when dressed. Yields; returns how many were dressed. One pass over what exists now:
  with streaming on, or for maps loaded later, use `Geo.watch`.
- `Geo.watch(root: Instance): () -> ()`
  Client: dresses `root` now and keeps dressing spots that appear under it later (streamed in, or
  loaded with a map), also ones tagged `Geo.SpotTag`. Doesn't yield. Returns a function that stops
  watching; dressed spots keep their meshes. A spot that streams out and back is a new instance, so it
  is dressed again.

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
- `Scheduler.onTimeScale(fn: (number) -> ())`
  Calls `fn(scale)` after every time scale change (Fx uses it to hold its particle emitters).
- `Scheduler.getTimeScale(): number`
- `Scheduler.count(phase: Phase?): number`
  Number of live jobs (for tests and leak checks).
- `Scheduler.advance(dt: number, phase: Phase?)`
  Advances jobs by `dt` without waiting for a frame (default: both phases, physics phase first), for
  deterministic tests and frame captures. `dt` follows the time scale, except while frozen (scale 0),
  when it applies as given: that is how a capture steps a frozen frame.

## Scene
`local Scene = require(ReplicatedStorage.Kit.Scene)` — both (server look replicates; terrain: server or Edit; zones: client)

> Scene: a persistent look for a place, plus terrain. Nothing here runs by itself: a script must call
> `Scene.apply`, `Scene.follow` or a terrain helper. Scripts that want a world rebuilt from git call
> these from a server script; `ArtStyle.applyScene()` applies the look in art.json the same way.
>
> Scene.apply({
> lighting = { ClockTime = 17.5, Brightness = 2, Ambient = Color3.fromHex("#2A2F45") },
> atmosphere = { Density = 0.35, Haze = 1.5, Color = Color3.fromHex("#C8B8A0") },
> bloom = { Intensity = 0.4, Size = 24, Threshold = 1.1 },
> })
> Scene.zone("Cave", workspace.World.CaveVolume, { lighting = { Brightness = 0.4 } }, { edge = 12 })
> local stop = Scene.follow()                                   -- client: blends zones around the camera
>
> Scene.sculpt({ center = Vector3.zero, size = Vector3.new(512, 128, 512) }, {
> noise = { seed = 7, scale = 180, amplitude = 36, base = 20 },
> biomes = { { material = Enum.Material.Rock, minSlope = 40 },
> { material = Enum.Material.Sand, maxHeight = 6 }, { material = Enum.Material.Grass } },
> water = 4,
> })
>
> Look sections use the engine's property names; `Scene.Schema` lists them with their ranges. A section
> you leave out is left alone, and `false` removes that object. Lighting.Technology can't be set from
> scripts: pick it in Studio. Applied on the server a look reaches everyone; on a client, that player.
> Terrain must run on the server (or in Edit mode) to replicate and save; helpers yield between chunks.

```lua
export type Section = { [string]: any }
export type Look = {
	lighting: Section?,
	atmosphere: (Section | false)?,
	sky: (Section | false)?,
	colorCorrection: (Section | false)?,
	bloom: (Section | false)?,
	sunRays: (Section | false)?,
}
-- A BasePart, or a box or ball in world space.
export type ZoneShape = BasePart | { center: Vector3, size: Vector3 } | { center: Vector3, radius: number }
export type ZoneOptions = {
	edge: number?, -- studs outside the shape over which the mood fades, default 8
	fade: number?, -- seconds a mood takes to come in or go, default 0.6
	priority: number?, -- higher zones blend over lower ones
}
export type Noise = {
	seed: number,
	scale: number, -- studs per noise cell: broad hills are 150+, lumps 30
	amplitude: number, -- studs up and down from `base`
	base: number?, -- mean height (world Y), default 0
	octaves: number?, -- default 4
	persistence: number?, -- amplitude kept per octave, default 0.5
	ridged: boolean?, -- sharp crests instead of round hills
	terrace: number?, -- snaps heights to steps this many studs tall
	plateaus: { Plateau }?, -- flat play areas
}
export type Plateau = { x: number, z: number, radius: number, blend: number?, height: number? }
export type Biome = {
	material: Enum.Material,
	minHeight: number?,
	maxHeight: number?,
	minSlope: number?, -- degrees
	maxSlope: number?,
	chance: number?, -- 0..1: patchy cover
}
export type Region = { center: Vector3, size: Vector3 }
export type Sculpt = {
	noise: Noise,
	biomes: { Biome }?, -- first match wins per column; default Grass
	water: number?, -- world Y of a water surface
	under: Enum.Material?, -- below the surface layer, default Rock
	surface: number?, -- studs of biome material on top, default 8
	dither: number?, -- studs of noise on biome height bounds, default 3
	chunk: number?, -- studs per chunk (multiple of 4), default 64
}
```

- `Scene.Schema = { lighting, Ambient, OutdoorAmbient, ColorShift_Top, ColorShift_Bottom, FogColor, ClockTime, Brightness, ExposureCompensation, ShadowSoftness, EnvironmentDiffuseScale, EnvironmentSpecularScale, GeographicLatitude, FogStart, FogEnd, GlobalShadows, atmosphere, Density, Offset, Glare, Haze, Color, Decay, sky, CelestialBodiesShown, StarCount, SunAngularSize, MoonAngularSize, SkyboxBk, SkyboxDn, SkyboxFt, SkyboxLf, SkyboxRt, SkyboxUp, SunTextureId, MoonTextureId, colorCorrection, Brightness, Contrast, Saturation, TintColor, bloom, sunRays }`
  Every property a look may set: { min, max }, or "color", "asset" or "boolean".
- `Scene.validate(look: Look): (boolean, string?)`
  Checks a look against `Scene.Schema` (pure). Returns false and a reason naming the bad property.
- `Scene.flatten(look: Look): { [string]: any }`
  `{ "lighting.ClockTime" = 14, ... }`: one value per property, the form zones blend (pure).
- `Scene.apply(look: Look)`
  Makes a look permanent (until the next call). Errors, naming the property, on a look `validate` refuses.
- `Scene.zoneWeight(shape: ZoneShape, position: Vector3, edge: number?): number`
  How much of a zone's mood applies at `position`: 1 inside, 0 beyond `edge` studs outside (pure).
- `Scene.mix(base: { [string]: any }, layers: { { values: { [string]: any }, weight: number } }): { [string]: any }`
  `base` with each layer blended over it in order (pure). Layers are { values, weight }; keys a layer
  doesn't name keep what the layers under it left.
- `Scene.zone(name: string, shape: ZoneShape, look: Look, opts: ZoneOptions?): () -> ()`
  Registers a named mood for an area, replacing any zone with that name. Does nothing until
  `Scene.follow` runs. Sky can't blend, so a zone's look can't set it. A section with no object yet (an
  Atmosphere, say) has nothing to fade from: apply one first for a smooth blend. Returns a function that
  removes the zone.
- `Scene.follow(focus: (() -> Vector3)?): () -> ()`
  Client: blends every zone around `focus()` (default: the camera, so a tour sees each mood) until the
  returned function is called, then restores the applied look. Runs on the Scheduler, so a freeze holds it.
- `Scene.height(x: number, z: number, noise: Noise): number`
  World height of a seeded landscape at x, z (pure and deterministic: same noise, same world).
- `Scene.slope(heightAt: (number, number) -> number, x: number, z: number, step: number?): number`
  Slope in degrees of `heightAt(x, z)` at a point (pure).
- `Scene.biomeAt(biomes: { Biome }, height: number, slope: number, roll: number, jitter: number?): Enum.Material`
  The first biome whose bounds hold (pure). `roll` (0..1) decides `chance`; `jitter` shifts height bounds.
- `Scene.chunks(min: Vector3, max: Vector3, chunk: number?): { { min: Vector3, max: Vector3 } }`
  A chunk grid over min..max (pure): aligned to the 4-stud voxel grid and tiled in X and Z, so
  `WriteVoxels` regions never overlap.
- `Scene.voxels(chunk: { min: Vector3, max: Vector3 }, spec: Sculpt): ({ { { Enum.Material } } }, { { { number } } })`
  Materials and occupancies for one chunk (pure), indexed [x][y][z] for `Terrain:WriteVoxels`.
- `Scene.sculpt(region: Region, spec: Sculpt)`
  Replaces terrain in `region` with a seeded landscape, one chunk per frame (yields).
- `Scene.repaint(materials: { { { Enum.Material } } }, occupancy: { { { number } } }, min: Vector3, biomes: { Biome }, surface: number?, seed: number?): { { { Enum.Material } } }`
  Repaints one chunk's surface in place (pure): cells within `surface` studs of each column's top get the
  biome for that column's height and slope. Air and water stay. Returns a new table.
- `Scene.paint(region: Region, biomes: { Biome }, opts: { surface: number?, seed: number?, chunk: number? }?)`
  Repaints existing terrain in `region` by height and slope, one chunk per frame (yields).
- `Scene.fillBox(cframe: CFrame, size: Vector3, material: Enum.Material, chunk: number?)`
  Fills a box of terrain, in chunks so a huge fill can't stall a frame (yields).
- `Scene.fillBall(center: Vector3, radius: number, material: Enum.Material)`
  Fills a ball of terrain. One engine call: keep radii under a few hundred studs.

## GeoShapes
`local GeoShapes = require(ReplicatedStorage.Kit.GeoShapes)` — both (register on clients; spots anywhere)

> GeoShapes: ten built-in stylized props for Geo: rock, tree, pine, bush, crystal, mushroom, fence, lantern,
> barrel, crate. Flat facets and banded colour, so a scene reads as one low-poly style at any size.
>
> GeoShapes.register()                                       -- client, before Geo.watch(workspace)
> Geo.watch(workspace)
> GeoShapes.spot("pine", CFrame.new(10, 0, 4), { seed = 3, parent = workspace.World }) -- any side
>
> A spot is an ordinary Part with `GeoShape` and `Seed` attributes, so spots made on the server (or by
> hand in Studio) save and replicate. Attributes are the parameters: `Seed` picks the variation, and an
> attribute named after a `GeoShapes.Palette` key with a Color3 value recolours that part (`leaf` on a
> tree). Each distinct set of attributes is one more mesh, so use a few seeds across many spots.

```lua
export type SpotOptions = {
	seed: number?,
	scale: number?,
	parent: Instance?,
	attributes: { [string]: any }?, -- palette overrides and shape parameters such as `Posts` on a fence
	name: string?,
}
```

- `GeoShapes.Palette = { bark, leaf, needle, berry, stone, crystal, stem, cap, spots, wood, trim, iron, flame }`
  Shared colours; every shape reads them here unless a spot attribute overrides one.
- `GeoShapes.Sizes = { rock, tree, pine, bush, crystal, mushroom, fence, lantern, barrel, crate }`
  Studs for a spot at scale 1, width and depth matching each mesh's proportions.
- `GeoShapes.Builders = { rock, tree, pine, bush, crystal, mushroom, fence, lantern, barrel, crate }`
  Every built-in shape by name, for `Geo.register` or your own wrappers.
- `GeoShapes.register()`
  Makes every built-in shape available to `Geo.dress` and `Geo.watch`. Call once on each client.
- `GeoShapes.spot(shape: string, cframe: CFrame, opts: SpotOptions?): Part`
  A Part spot standing on `cframe` (the point on the ground, its up axis up). Works on any side; the
  mesh appears on clients running `Geo.watch`. Lanterns carry their own light.

## Scatter
`local Scatter = require(ReplicatedStorage.Kit.Scatter)` — both (plan is pure; place on the server or in Edit)

> Scatter: seeded prop placement over a region or terrain. `Scatter.plan` decides where things go and
> touches no instances (same seed, same layout), and `Scatter.place` makes them.
>
> local plan = Scatter.plan({
> seed = 11, spacing = 14, count = 120,
> region = { center = Vector3.new(0, 0, 0), size = Vector3.new(400, 0, 400) },
> sample = Scatter.ground({ top = 300 }),                  -- raycast down onto terrain or parts
> slopeMax = 28, density = { inner = 60, outer = 200 },    -- thicker at the centre
> avoid = Scatter.around(workspace.World.Roads, 6),
> scale = { 0.8, 1.4 }, tilt = 4, align = 0.6, variants = 3,
> })
> Scatter.place(plan, { "pine", "tree" }, { parent = workspace.World })   -- GeoShapes spots
>
> `what` can be a GeoShapes name, a list of them (picked per placement), a Model or BasePart to clone,
> or a function(placement) returning an instance. Spots made on the server replicate, spots made in
> Edit mode save, and clients need `Geo.watch` either way. A Model's pivot should sit at its base.

```lua
-- A box (its Y ignored) or circle on the ground plane.
export type Region = { center: Vector3, size: Vector3 } | { center: Vector3, radius: number }
-- 1 inside `inner` studs of `center`, falling to 0 at `outer`; `power` above 1 thins the rim faster.
export type Falloff = { center: Vector3?, inner: number, outer: number, power: number? }
export type Avoid = { position: Vector3, radius: number }
export type Hit = { position: Vector3, normal: Vector3, material: Enum.Material? }
export type Options = {
	seed: number,
	region: Region,
	spacing: number, -- minimum studs between placements
	count: number?, -- stop after this many
	density: (number | Falloff | ((number, number) -> number))?, -- chance to keep a point, 0..1
	avoid: { Avoid }?,
	sample: ((number, number) -> Hit?)?, -- ground under x, z; default: flat at the region's Y
	slopeMax: number?, -- degrees
	materials: { Enum.Material }?, -- keep only these ground materials
	scale: { number }?, -- { min, max }
	yaw: { number }?, -- degrees { min, max }, default a full turn
	tilt: number?, -- random lean in degrees
	align: number?, -- 0 stands upright, 1 follows the ground normal
	variants: number?, -- placement.variant runs 1..variants (GeoShapes seeds: keep it small)
	chunk: number?, -- yield every this many samples; leave nil for pure, non-yielding use
}
export type Placement = {
	position: Vector3,
	normal: Vector3,
	scale: number,
	cframe: CFrame,
	variant: number,
	index: number,
}
export type PlaceOptions = { parent: Instance?, name: string?, chunk: number? }
export type Target = string | { string } | Model | BasePart | ((Placement) -> Instance?)
```

- `Scatter.points(region: Region, spacing: number, seed: number, limit: number?): { Vector2 }`
  Poisson-disc points (pure; Bridson's algorithm): every pair is at least `spacing` apart and the
  gaps stay even, with none of the clumps plain random placement gives.
- `Scatter.densityAt(density: (number | Falloff | ((number, number) -> number))?, x: number, z: number): number`
  Chance to keep a point at x, z under a density setting (pure).
- `Scatter.plan(opts: Options): { Placement }`
  Where everything goes (pure unless `opts.sample` raycasts; yields only with `opts.chunk`).
- `Scatter.ground(opts: { top: number, depth: number?, exclude: { Instance }? }): (number, number) -> Hit?`
  A `sample` function that raycasts straight down. `top` is the Y to start from; `depth` how far to
  look (default twice `top`, at least 1000); `exclude` skips instances, such as already scattered props.
- `Scatter.around(root: Instance | { Instance }, pad: number?): { Avoid }`
  An `avoid` list from instances: each part or model keeps props `pad` studs clear of its bounds.
- `Scatter.place(plan: { Placement }, what: Target, opts: PlaceOptions?): Folder`
  Makes a plan real in a new Folder, `chunk` instances per frame (default 64; yields). Returns the folder.

## Camera
`local Camera = require(ReplicatedStorage.Kit.Camera)` — client

> Camera: scripted camera rigs for the local player. One rig runs at a time; a new one replaces it.
> Client-only. Rig maths are pure functions, so framing is unit tested.
>
> Camera.follow(nil, { distance = 16, height = 6 })           -- default target: the local character
> Camera.topDown(nil, { height = 60, tilt = 20 })
> Camera.shoulder()                                           -- mouse, thumbstick or touch drag to aim
> local stop = Camera.path({
> { t = 0, at = CFrame.lookAt(a, focus), fov = 50 },
> { t = 3, at = CFrame.lookAt(b, focus), fov = 40, ease = "sineInOut" },
> }, { onDone = function() print("cut") end })
> Camera.stop()                                               -- back to the default Roblox camera
>
> Rigs render at Camera + 1, so `K.cam` (Camera + 10) still wins during captures. Paths run on the
> Scheduler: `Fx.setGlobalTimeScale` slows or freezes a cutscene with the effects in it.

```lua
-- What a rig watches: a part, a model, a function, or nil for the local character.
export type Target = BasePart | Model | (() -> Vector3)
export type FollowOptions = {
	distance: number?, -- studs behind, default 16
	height: number?, -- studs above the target, default 5
	yaw: number?, -- degrees, default 0
	pitch: number?, -- degrees below level, default 15
	stiffness: number?, -- spring speed, default 8
	collide: boolean?, -- pull in rather than clip through walls, default on
	fov: number?,
}
export type TopDownOptions = {
	height: number?, -- studs above, default 50
	tilt: number?, -- degrees off straight down, default 15
	yaw: number?,
	stiffness: number?,
	fov: number?,
}
export type ShoulderOptions = {
	offset: Vector3?, -- right, up, back in studs, default (2, 2, 8)
	sensitivity: number?, -- degrees per pixel, default 0.25
	pitchLimit: number?, -- degrees, default 70
	collide: boolean?,
	fov: number?,
}
export type PathKey = { t: number, at: CFrame, fov: number?, ease: Motion.Ease? }
export type PathOptions = { onDone: (() -> ())?, hold: boolean? } -- hold: stay on the last frame
```

- `Camera.followFrame(focus: Vector3, yaw: number, pitch: number, distance: number): CFrame`
  Camera behind and above `focus` (pure). Yaw turns around the world up axis.
- `Camera.topDownFrame(focus: Vector3, height: number, tilt: number, yaw: number?): CFrame`
  Camera above `focus`, leaning `tilt` degrees off vertical (pure).
- `Camera.shoulderFrame(focus: Vector3, yaw: number, pitch: number, offset: Vector3): CFrame`
  Over-the-shoulder view: `offset` is right, up, back from `focus` along the aim (pure).
- `Camera.clip(focus: Vector3, wanted: Vector3, hitDistance: number?): Vector3`
  Where a camera may sit on the line from `focus` to `wanted` when a wall is `hitDistance` along it (pure).
- `Camera.pathFrame(keys: { PathKey }, t: number): (CFrame, number?)`
  The frame and field of view of a keyframed path at time `t` (pure). Keys without `fov` keep the last one.
- `Camera.checkPath(keys: { PathKey }): { PathKey }`
  Validates and returns a path: at least one key, times in order, CFrames in `at` (pure).
- `Camera.stop()`
  Ends the running rig and hands the camera back to Roblox.
- `Camera.active(): boolean`
  Whether a rig is running.
- `Camera.follow(target: Target?, opts: FollowOptions?)`
  Third-person chase camera. Waits on the last good focus while the target is missing (respawns).
- `Camera.topDown(target: Target?, opts: TopDownOptions?)`
  Fixed-angle view from above, for strategy and arcade games.
- `Camera.shoulder(opts: ShoulderOptions?)`
  Over-the-shoulder aim for the local character: locks the mouse, and turns the character with the view.
- `Camera.path(keys: { PathKey }, opts: PathOptions?): () -> ()`
  Plays a keyframed camera move on Motion curves. Returns a function that ends it early. Ends by handing
  the camera back, or stays on the last frame with `hold` until `Camera.stop`.
