--!strict
-- Fx: composable effects. An effect is a list of timed layers (particles, growing/shrinking meshes,
-- beams, lights, debris, sound, camera, markers) that one shared scheduler plays together.
--
--   local Burst = Fx.define({ name = "Burst", layers = {
--       { kind = "mesh", shape = "ball", material = "Neon", color = "core",
--         keys = { { t = 0, size = 1 }, { t = 0.15, size = 8, ease = "expoOut" }, { t = 0.4, size = 9, transparency = 1 } } },
--       { kind = "particles", at = 0.02, texture = "spark", count = 30, color = "glow", speed = { 30, 60 } },
--       { kind = "sound", at = 0, id = Audio.Builtin.explosion },
--       { kind = "camera", at = 0, shake = { 0.4, 1.2 } },
--       { kind = "event", at = 0.05, name = "impact" },
--   } })
--   local handle = Fx.play(Burst, CFrame.new(position), { scale = 1.5, palette = { core = Color3.new(1, 0.4, 0.1) } })
--   handle:on("impact", function() ... end) ; handle:freeze(0.08) -- hitstop
--
-- Colours can be role names ("core", "glow", "accent", "dark", "smoke", "spark") resolved from the
-- options palette, then the definition's palette, then `Fx.Palette`, so one definition restyles per game.
-- Play effects on CLIENTS (presentation); keep damage and rules on the server and broadcast with Net.
-- `Fx.emit` also plays editor-authored instance effects (EmitDelay/EmitCount/EmitDuration attributes).
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Audio = require(script.Parent.Audio)
local Motion = require(script.Parent.Motion)
local Scheduler = require(script.Parent.Scheduler)
local Tex = require(script.Parent.Tex)

local Fx = {}

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

-- Default palette roles. Games override per effect or globally (`Fx.Palette.core = ...`).
Fx.Palette = {
	core = Color3.fromRGB(255, 244, 214),
	glow = Color3.fromRGB(255, 200, 40),
	accent = Color3.fromRGB(170, 90, 255),
	dark = Color3.fromRGB(28, 18, 40),
	smoke = Color3.fromRGB(70, 64, 80),
	spark = Color3.fromRGB(255, 236, 170),
} :: { [string]: Color3 }

local QUALITY_RANK: { [string]: number } = { Low = 1, Medium = 2, High = 3 }
local QUALITY_COUNT: { [string]: number } = { Low = 0.35, Medium = 0.65, High = 1 }
local MAX_EMIT = 400
local MAX_SECONDS = 20
local POOL_SIZE = 4

local defaultQuality: Quality? = nil

-- Current global quality. Defaults from the player's graphics setting on clients, High on servers.
function Fx.getQuality(): Quality
	if defaultQuality then
		return defaultQuality
	end
	local quality: Quality = "High"
	if RunService:IsClient() then
		local ok, level = pcall(function()
			return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
		end)
		if ok and type(level) == "number" and level > 0 then
			quality = if level <= 3 then "Low" elseif level <= 7 then "Medium" else "High"
		else
			quality = "Medium"
		end
	end
	return quality
end

function Fx.setQuality(quality: Quality?)
	defaultQuality = quality
end

-- Particle count after the quality multiplier (pure; tested).
function Fx.countFor(count: number, quality: Quality, scale: number?): number
	local n = count * (QUALITY_COUNT[quality] or 1) * math.clamp(scale or 1, 0.25, 4)
	return math.clamp(math.floor(n + 0.5), if count > 0 then 1 else 0, MAX_EMIT)
end

-- Whether a layer runs at `quality` (pure; tested).
function Fx.allowed(layer: Layer, quality: Quality): boolean
	return layer.minQuality == nil or (QUALITY_RANK[quality] or 3) >= (QUALITY_RANK[layer.minQuality] or 1)
end

local function resolveColor(spec: any, palette: { [string]: Color3 }): Color3
	if typeof(spec) == "Color3" then
		return spec
	elseif type(spec) == "string" then
		return palette[spec] or Fx.Palette[spec] or Color3.new(1, 1, 1)
	end
	return Color3.new(1, 1, 1)
end

-- ColorSpec → ColorSequence using the palette (pure).
function Fx.colorSequence(spec: ColorSpec?, palette: { [string]: Color3 }?): ColorSequence
	local p = palette or Fx.Palette
	if typeof(spec) == "ColorSequence" then
		return spec
	elseif type(spec) == "table" then
		local list = spec :: { any }
		if #list == 1 then
			return ColorSequence.new(resolveColor(list[1], p))
		end
		local points = {}
		for i, entry in list do
			table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#list - 1), resolveColor(entry, p)))
		end
		return ColorSequence.new(points)
	end
	return ColorSequence.new(resolveColor(spec or "glow", p))
end

-- NumberKeys → NumberSequence, multiplied by `scale` (pure).
function Fx.numberSequence(keys: NumberKeys?, default: number, scale: number?): NumberSequence
	local s = scale or 1
	if type(keys) == "table" then
		local points = {}
		for _, key in keys :: { any } do
			table.insert(points, NumberSequenceKeypoint.new(key[1], key[2] * s, (key[3] or 0) * s))
		end
		return NumberSequence.new(points)
	end
	return NumberSequence.new((if type(keys) == "number" then keys else default) * s)
end

-- Seconds until a layer has fully finished (pure; tested): start + active time + longest lifetime.
function Fx.layerEnd(layer: Layer): number
	local at = layer.at or 0
	if layer.kind == "particles" then
		local lifetime = if layer.lifetime then layer.lifetime[2] or layer.lifetime[1] else 1
		return at + (layer.duration or 0) + lifetime
	elseif layer.kind == "mesh" then
		local keys = layer.keys or {}
		return at + (if #keys > 0 then keys[#keys].t else 0.4)
	elseif layer.kind == "beam" or layer.kind == "light" then
		local keys = if layer.kind == "beam" then layer.width else layer.lightKeys
		local last = if keys and #keys > 0 then keys[#keys][1] else 0
		return at + math.max(layer.duration or 0, last)
	elseif layer.kind == "debris" then
		return at + (if layer.lifetime then layer.lifetime[2] or layer.lifetime[1] else 2)
	elseif layer.kind == "camera" then
		return at + (if layer.shake then layer.shake[1] else 0)
	end
	return at
end

-- Total length of a definition in seconds (pure).
function Fx.length(def: Definition): number
	if def.duration then
		return def.duration
	end
	local finish = 0
	for _, layer in def.layers do
		finish = math.max(finish, Fx.layerEnd(layer))
	end
	return math.min(finish, MAX_SECONDS)
end

-- A mesh keyframe. Use it when the keys of one layer set different fields: Luau infers a list literal's
-- element type from its first entry, so `{ { t = 0, size = 1 }, { t = 0.3, transparency = 1 } }` fails
-- strict checking while `{ Fx.key(0, { size = 1 }), Fx.key(0.3, { transparency = 1 }) }` passes.
type KeyFields = {
	size: (number | Vector3)?,
	transparency: number?,
	color: (Color3 | string)?,
	offset: CFrame?,
	ease: string?,
}
function Fx.key(t: number, fields: KeyFields?): MeshKey
	local f: KeyFields = fields or {}
	return { t = t, size = f.size, transparency = f.transparency, color = f.color, offset = f.offset, ease = f.ease }
end

local KINDS = {
	particles = true,
	mesh = true,
	beam = true,
	light = true,
	sound = true,
	camera = true,
	debris = true,
	event = true,
}

-- Validates and returns a definition (errors name the bad layer).
function Fx.define(def: Definition): Definition
	assert(type(def.name) == "string" and def.name ~= "", "Fx.define needs a name")
	assert(type(def.layers) == "table" and #def.layers > 0, `Fx '{def.name}' has no layers`)
	for i, layer in def.layers do
		local label = `Fx '{def.name}' layer {i} ({layer.name or layer.kind})`
		assert(KINDS[layer.kind], `{label}: unknown kind '{tostring(layer.kind)}'`)
		assert((layer.at or 0) >= 0 and (layer.at or 0) <= MAX_SECONDS, `{label}: 'at' must be 0..{MAX_SECONDS}`)
		if layer.kind == "particles" then
			assert(layer.count or (layer.rate and layer.duration), `{label}: needs count, or rate + duration`)
		elseif layer.kind == "mesh" then
			assert(layer.keys and #layer.keys > 0, `{label}: needs keys`)
			local previous = -1
			for k, key in layer.keys do
				assert(
					type(key.t) == "number" and key.t >= previous,
					`{label}: key {k} needs a time 't' after the previous key`
				)
				previous = key.t
				if key.ease and not Motion.isEase(key.ease) then
					warn(`{label}: unknown ease '{key.ease}' (linear used)`)
				end
			end
		elseif layer.kind == "sound" then
			assert(type(layer.id) == "string", `{label}: needs id`)
		elseif layer.kind == "event" then
			assert(type(layer.name) == "string", `{label}: needs name`)
		end
	end
	return def
end

----------------------------------------------------------------------------------------------------
-- Handle

export type Handle = {
	time: number,
	finished: boolean,
	root: Model,
	on: (self: Handle, name: string, fn: () -> ()) -> Handle,
	setTimeScale: (self: Handle, scale: number) -> (),
	freeze: (self: Handle, seconds: number) -> (),
	stop: (self: Handle) -> (),
}

type Event = { at: number, run: () -> () }
type Track = { from: number, seconds: number, step: (number) -> () }
type Internal = Handle & {
	_scale: number,
	_events: { Event },
	_tracks: { Track },
	_emitters: { ParticleEmitter },
	_authoredScale: { [ParticleEmitter]: number },
	_ending: number,
	_listeners: { [string]: { () -> () } },
	_stopJob: (() -> ())?,
	_onDone: (() -> ())?,
	_release: (Model) -> (),
	_follow: (BasePart | Attachment)?,
	_anchor: BasePart,
	_origin: CFrame,
	_attached: { { part: BasePart, offset: CFrame } },
}

local handles: { [any]: boolean } = {}

local Handle = {}
Handle.__index = Handle

function Handle.on(self: Internal, name: string, fn: () -> ()): Handle
	local list = self._listeners[name]
	if not list then
		list = {}
		self._listeners[name] = list
	end
	table.insert(list, fn)
	return self
end

function Handle.setTimeScale(self: Internal, scale: number)
	if self.finished then
		return
	end
	self._scale = math.clamp(scale, 0, 4)
	local global = Scheduler.getTimeScale()
	for _, emitter in self._emitters do
		emitter.TimeScale = math.clamp((self._authoredScale[emitter] or 1) * self._scale * global, 0, 1)
	end
end

-- Hitstop: holds particles, meshes and lights for `seconds` of real time.
function Handle.freeze(self: Internal, seconds: number)
	local resume = self._scale
	Handle.setTimeScale(self, 0)
	task.delay(seconds, function()
		if not self.finished then
			Handle.setTimeScale(self, resume)
		end
	end)
end

function Handle.stop(self: Internal)
	if self.finished then
		return
	end
	self.finished = true
	handles[self] = nil
	if self._stopJob then
		self._stopJob()
	end
	self._release(self.root)
	if self._onDone then
		task.spawn(self._onDone)
	end
end

local function fire(self: Internal, name: string)
	local list = self._listeners[name]
	if list then
		for _, fn in list do
			task.spawn(fn)
		end
	end
end

local function step(self: Internal, dt: number): boolean
	if self.finished then
		return true
	end
	if self._follow and self._follow.Parent then
		local target = self._follow
		local cf = if target:IsA("Attachment") then target.WorldCFrame else (target :: BasePart).CFrame
		self._anchor.CFrame = cf
		for _, entry in self._attached do
			entry.part.CFrame = cf * entry.offset
		end
	end
	self.time += dt * self._scale
	local now = self.time
	local pending = {}
	for _, event in self._events do
		if event.at <= now then
			xpcall(event.run, function(err)
				warn(`Fx: layer failed: {err}`)
			end)
		else
			table.insert(pending, event)
		end
	end
	self._events = pending
	local running = {}
	for _, track in self._tracks do
		if now >= track.from then
			local alpha = math.min((now - track.from) / track.seconds, 1)
			track.step(alpha)
			if alpha < 1 then
				table.insert(running, track)
			end
		else
			table.insert(running, track)
		end
	end
	self._tracks = running
	if now >= self._ending and #self._events == 0 and #self._tracks == 0 then
		Handle.stop(self)
		return true
	end
	return false
end

local function newHandle(
	root: Model,
	anchor: BasePart,
	origin: CFrame,
	release: (Model) -> (),
	opts: PlayOptions
): Internal
	local self = setmetatable({
		time = 0,
		finished = false,
		root = root,
		_scale = 1,
		_events = {},
		_tracks = {},
		_emitters = {},
		_authoredScale = {},
		_ending = 0,
		_listeners = {},
		_onDone = opts.onDone,
		_release = release,
		_follow = opts.follow,
		_anchor = anchor,
		_origin = origin,
		_attached = {},
	}, Handle) :: any
	handles[self] = true
	return self
end

local function at(self: Internal, time: number, run: () -> ())
	table.insert(self._events, { at = time, run = run })
	self._ending = math.max(self._ending, time)
end

local function over(self: Internal, from: number, seconds: number, run: (number) -> ())
	table.insert(self._tracks, { from = from, seconds = math.max(seconds, 1e-3), step = run })
	self._ending = math.max(self._ending, from + seconds)
end

----------------------------------------------------------------------------------------------------
-- Building layers

local GeoModule: any = nil

local function effectPart(name: string, shape: string?, material: string?): BasePart
	local part: BasePart
	if shape == "torus" or shape == "shard" then
		-- Real rings and faceted shards (Geo builds each unit shape once per client and clones it).
		if not GeoModule then
			GeoModule = require(script.Parent.Geo)
		end
		part = (if shape == "torus" then GeoModule.unitTorus() else GeoModule.unitShard()):Clone()
	elseif shape == "wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if shape == "ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "cylinder" or shape == "ring" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Material = (Enum.Material :: any)[material or "Neon"] or Enum.Material.Neon
	part.Transparency = 1
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return part
end

local function scaledCFrame(cf: CFrame?, scale: number): CFrame
	if not cf then
		return CFrame.identity
	end
	return CFrame.new(cf.Position * scale) * cf.Rotation
end

type Ctx = {
	handle: Internal,
	root: Model,
	anchor: BasePart,
	scale: number,
	palette: { [string]: Color3 },
	quality: Quality,
	opts: PlayOptions,
}

local function attachmentFor(ctx: Ctx, layer: Layer, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = scaledCFrame(layer.offset, ctx.scale)
	attachment.Parent = ctx.anchor
	return attachment
end

local function buildParticles(ctx: Ctx, layer: Layer, index: number)
	local attachment = attachmentFor(ctx, layer, `L{index}`)
	local e = Instance.new("ParticleEmitter")
	e.Name = layer.name or "Particles"
	e.Enabled = false
	e.Rate = layer.rate or 0
	local life = layer.lifetime or { 0.4, 0.8 }
	e.Lifetime = NumberRange.new(life[1], life[2] or life[1])
	local speed = layer.speed or { 0, 0 }
	e.Speed = NumberRange.new(speed[1] * ctx.scale, (speed[2] or speed[1]) * ctx.scale)
	local spread = layer.spread or 180
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Drag = layer.drag or 0
	e.Acceleration = (layer.acceleration or Vector3.zero) * ctx.scale
	e.Size = Fx.numberSequence(layer.size, 1, ctx.scale)
	e.Transparency = Fx.numberSequence(layer.transparency, 0)
	e.Color = Fx.colorSequence(layer.color, ctx.palette)
	e.LightEmission = layer.lightEmission or 1
	e.LightInfluence = 0
	e.Brightness = layer.brightness or 1
	local rotation = layer.rotation or { 0, 360 }
	e.Rotation = NumberRange.new(rotation[1], rotation[2] or rotation[1])
	local rotSpeed = layer.rotSpeed or { 0, 0 }
	e.RotSpeed = NumberRange.new(rotSpeed[1], rotSpeed[2] or rotSpeed[1])
	e.ZOffset = layer.zOffset or 0
	e.LockedToPart = layer.locked == true
	e.EmissionDirection = Enum.NormalId.Top
	if layer.squash then
		e.Squash = Fx.numberSequence(layer.squash, 0)
	end
	if layer.orientation then
		e.Orientation = (Enum.ParticleOrientation :: any)[layer.orientation]
	end
	if layer.shape then
		e.Shape = (Enum.ParticleEmitterShape :: any)[layer.shape]
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = if layer.inward
			then Enum.ParticleEmitterShapeInOut.Inward
			else Enum.ParticleEmitterShapeInOut.Outward
		local size = layer.shapeSize or 1
		-- The emitter shape follows its parent's size; an attachment can't carry one, so use a part.
		local holder = effectPart(`L{index}Shape`, "block", "SmoothPlastic")
		holder.Size = (if typeof(size) == "Vector3" then size else Vector3.one * (size :: number) * 2) * ctx.scale
		holder.CFrame = ctx.anchor.CFrame * attachment.CFrame
		holder.Parent = ctx.root
		e.Parent = holder
		attachment:Destroy()
	else
		e.Parent = attachment
	end
	if layer.direction then
		-- Point the emission direction: rotate the holder so +Y faces `direction`.
		local parent = e.Parent :: Instance
		local up = layer.direction.Unit
		local right = if math.abs(up.Y) > 0.99 then Vector3.xAxis else up:Cross(Vector3.yAxis).Unit
		local rotation3 = CFrame.fromMatrix(Vector3.zero, right, up)
		if parent:IsA("Attachment") then
			parent.CFrame = CFrame.new(parent.CFrame.Position) * rotation3
		elseif parent:IsA("BasePart") then
			parent.CFrame = CFrame.new(parent.Position) * rotation3
		end
	end
	local holderPart = e.Parent
	if holderPart and holderPart:IsA("BasePart") then
		-- Shape holders are separate parts: they must follow a moving anchor too.
		table.insert(
			ctx.handle._attached,
			{ part = holderPart, offset = ctx.anchor.CFrame:ToObjectSpace(holderPart.CFrame) }
		)
	end
	Tex.apply(e, layer.texture or "glow", { flipbook = layer.flipbook })
	local authored = e.TimeScale
	ctx.handle._authoredScale[e] = authored
	table.insert(ctx.handle._emitters, e)
	local start = layer.at or 0
	if layer.count then
		local count = Fx.countFor(layer.count, ctx.quality, ctx.scale)
		at(ctx.handle, start, function()
			e:Emit(count)
		end)
	end
	if layer.rate and layer.duration then
		e.Rate = layer.rate * (QUALITY_COUNT[ctx.quality] or 1)
		at(ctx.handle, start, function()
			e.Enabled = true
		end)
		at(ctx.handle, start + layer.duration, function()
			e.Enabled = false
		end)
	end
	ctx.handle._ending = math.max(ctx.handle._ending, Fx.layerEnd(layer))
end

local function sizeOf(value: (number | Vector3)?, shape: string?, scale: number): Vector3
	local v: Vector3 = if typeof(value) == "Vector3"
		then value
		elseif type(value) == "number" then Vector3.one * value
		else Vector3.one
	if shape == "ring" then
		-- A flat disc: thin along X (cylinder axis), wide in Y/Z.
		v = Vector3.new(math.max(v.X * 0.04, 0.05), v.Y, v.Z)
	elseif shape == "torus" and typeof(value) ~= "Vector3" then
		-- A uniform number keeps the unit torus's proportions (tube = 12% of the diameter).
		v = Vector3.new(v.X, v.X * 0.12, v.Z)
	end
	return v * scale
end

local function buildMesh(ctx: Ctx, layer: Layer, index: number)
	local keys = layer.keys :: { MeshKey }
	local part = effectPart(layer.name or `L{index}Mesh`, layer.shape, layer.material)
	local base = scaledCFrame(layer.offset, ctx.scale)
	if layer.shape == "ring" or layer.shape == "cylinder" then
		base *= CFrame.Angles(0, 0, math.rad(90)) -- lie flat: the cylinder axis points up
	end
	part.Parent = ctx.root
	-- Resolve each key once, filling unspecified fields from the previous key.
	local resolved = {}
	local last = {
		size = sizeOf(1, layer.shape, ctx.scale),
		transparency = 0,
		color = resolveColor(layer.color or "glow", ctx.palette),
		offset = CFrame.identity,
	}
	for _, key in keys do
		local entry = {
			t = key.t,
			ease = key.ease,
			size = if key.size ~= nil then sizeOf(key.size, layer.shape, ctx.scale) else last.size,
			transparency = if key.transparency ~= nil then key.transparency else last.transparency,
			color = if key.color ~= nil then resolveColor(key.color, ctx.palette) else last.color,
			offset = if key.offset ~= nil then scaledCFrame(key.offset, ctx.scale) else last.offset,
		}
		table.insert(resolved, entry)
		last = entry
	end
	local function track(field: string): { Motion.Key<any> }
		local list = {}
		for _, entry in resolved do
			table.insert(list, { t = entry.t, v = (entry :: any)[field], ease = entry.ease })
		end
		return list
	end
	local sizes, alphas, colors, offsets = track("size"), track("transparency"), track("color"), track("offset")
	local length = math.max(resolved[#resolved].t, 1e-3)
	local spin = math.rad(layer.spin or 0)
	local start = layer.at or 0
	local decal: Decal? = nil
	if layer.decal then
		local d = Instance.new("Decal")
		d.Face = Enum.NormalId.Top
		d.Color3 = resolveColor(layer.color or "glow", ctx.palette)
		Tex.apply(d, layer.decal)
		d.Parent = part
		decal = d
	end
	local function apply(t: number)
		part.Size = Motion.sample(sizes, t)
		local alpha = Motion.sample(alphas, t)
		if decal then
			-- The part stays invisible; only its decal shows, fading with the keys.
			decal.Transparency = alpha
			part.Transparency = 1
		else
			part.Transparency = alpha
		end
		part.Color = Motion.sample(colors, t)
		part.CFrame = ctx.anchor.CFrame * base * Motion.sample(offsets, t) * CFrame.Angles(spin * t, 0, 0)
	end
	over(ctx.handle, start, length, function(alpha)
		apply(alpha * length)
	end)
	at(ctx.handle, start + length, function()
		part.Transparency = 1
		if decal then
			decal.Transparency = 1
		end
	end)
end

local function buildBeam(ctx: Ctx, layer: Layer, index: number)
	local a0 = Instance.new("Attachment")
	a0.Name = `L{index}A0`
	a0.Position = (layer.from or Vector3.zero) * ctx.scale
	a0.Parent = ctx.anchor
	local a1 = Instance.new("Attachment")
	a1.Name = `L{index}A1`
	a1.Position = (layer.to or Vector3.new(0, 10, 0)) * ctx.scale
	a1.Parent = ctx.anchor
	local beam = Instance.new("Beam")
	beam.Name = layer.name or "Beam"
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = Fx.colorSequence(layer.color, ctx.palette)
	beam.LightEmission = layer.lightEmission or 1
	beam.LightInfluence = 0
	beam.Brightness = layer.brightness or 1
	beam.FaceCamera = true
	beam.Segments = layer.segments or 10
	beam.CurveSize0 = (layer.curve or 0) * ctx.scale
	beam.CurveSize1 = -(layer.curve or 0) * ctx.scale
	beam.Transparency = Fx.numberSequence(layer.transparency, 0)
	beam.Enabled = false
	Tex.apply(beam, layer.texture or "streak", { flipbook = nil })
	beam.Parent = ctx.anchor
	local width: { Motion.Key<number> } = {}
	local widthKeys: { { number } } = layer.width or { { 0, 1 }, { 0.3, 0 } }
	for _, key in widthKeys do
		table.insert(width, { t = key[1], v = key[2] * ctx.scale, ease = "quadOut" })
	end
	local length = math.max(Motion.length(width), layer.duration or 0, 1e-3)
	local start = layer.at or 0
	at(ctx.handle, start, function()
		beam.Enabled = true
	end)
	over(ctx.handle, start, length, function(alpha)
		local w = Motion.sample(width, alpha * length)
		beam.Width0, beam.Width1 = w, w * 0.6
	end)
	at(ctx.handle, start + length, function()
		beam.Enabled = false
	end)
end

local function buildLight(ctx: Ctx, layer: Layer, index: number)
	local attachment = attachmentFor(ctx, layer, `L{index}Light`)
	local light = Instance.new("PointLight")
	light.Name = layer.name or "Light"
	light.Color = resolveColor(layer.color or "glow", ctx.palette)
	light.Range = math.min((layer.range or 16) * ctx.scale, 60)
	light.Shadows = false
	light.Brightness = 0
	light.Parent = attachment
	local keys: { Motion.Key<number> } = {}
	local lightKeys: { { number } } = layer.lightKeys or { { 0, layer.brightness or 3 }, { 0.4, 0 } }
	for _, key in lightKeys do
		table.insert(keys, { t = key[1], v = key[2], ease = "quadOut" })
	end
	local length = math.max(Motion.length(keys), 1e-3)
	over(ctx.handle, layer.at or 0, length, function(alpha)
		light.Brightness = Motion.sample(keys, alpha * length)
	end)
end

local function worldPosition(ctx: Ctx, layer: Layer): Vector3
	return (ctx.anchor.CFrame * scaledCFrame(layer.offset, ctx.scale)).Position
end

local function buildSound(ctx: Ctx, layer: Layer)
	if ctx.opts.sound == false then
		return
	end
	at(ctx.handle, layer.at or 0, function()
		Audio.play(layer.id :: string, worldPosition(ctx, layer), { volume = layer.volume })
	end)
end

local VFXModule: any = nil
local function vfx(): any
	if not VFXModule then
		VFXModule = require(script.Parent.VFX)
	end
	return VFXModule
end

local function buildCamera(ctx: Ctx, layer: Layer)
	if ctx.opts.camera == false or not RunService:IsClient() then
		return
	end
	at(ctx.handle, layer.at or 0, function()
		local camera = workspace.CurrentCamera
		local distance = if camera then (camera.CFrame.Position - worldPosition(ctx, layer)).Magnitude else 0
		local falloff = math.clamp(1 - (distance - 40 * ctx.scale) / (160 * ctx.scale), 0, 1)
		if falloff <= 0 then
			return
		end
		if layer.shake then
			vfx().shake(layer.shake[1], layer.shake[2] * falloff)
		end
		if layer.fov then
			vfx().fovPunch(layer.fov[1] * falloff, layer.fov[2])
		end
		if layer.flash then
			local flash = layer.flash :: { color: (Color3 | string)?, time: number? }
			vfx().flash({ color = resolveColor(flash.color or "core", ctx.palette), time = flash.time })
		end
		if layer.grade then
			local grade =
				layer.grade :: { color: (Color3 | string)?, contrast: number?, saturation: number?, time: number? }
			vfx().grade({
				color = if grade.color then resolveColor(grade.color, ctx.palette) else nil,
				contrast = grade.contrast,
				saturation = grade.saturation,
				time = grade.time,
				bloom = 0,
			})
		end
	end)
end

local function buildDebris(ctx: Ctx, layer: Layer)
	local count = Fx.countFor(layer.count or 8, ctx.quality, 1)
	local sizes = layer.sizeRange or { 0.4, 1.2 }
	local speed = layer.speed or { 20, 45 }
	local life = layer.lifetime or { 1.6, 2.4 }
	at(ctx.handle, layer.at or 0, function()
		local origin = worldPosition(ctx, layer)
		local rng = Random.new()
		for _ = 1, count do
			local chunk = Instance.new("Part")
			chunk.Name = "Debris"
			local s = rng:NextNumber(sizes[1], sizes[2] or sizes[1]) * ctx.scale
			chunk.Size = Vector3.new(s, s * rng:NextNumber(0.5, 1), s * rng:NextNumber(0.6, 1.2))
			chunk.Material = (Enum.Material :: any)[layer.material or "Slate"] or Enum.Material.Slate
			chunk.Color = resolveColor(layer.color or "dark", ctx.palette)
			chunk.CanQuery, chunk.CanTouch, chunk.CastShadow = false, false, true
			chunk.CFrame = CFrame.new(origin + Vector3.new(0, s, 0))
				* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
			local angle = rng:NextNumber(0, math.pi * 2)
			local up = rng:NextNumber(0.6, 1.2)
			local v = rng:NextNumber(speed[1], speed[2] or speed[1]) * ctx.scale
			chunk.AssemblyLinearVelocity = Vector3.new(math.cos(angle), up, math.sin(angle)).Unit * v
			chunk.AssemblyAngularVelocity =
				Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
			chunk.Parent = ctx.root
			local lifetime = rng:NextNumber(life[1], life[2] or life[1])
			Motion.to(
				chunk,
				{ Size = chunk.Size * 0.1, Transparency = 1 },
				{ time = 0.5, delay = lifetime - 0.5, ease = "quadIn" }
			)
			Debris:AddItem(chunk, lifetime + 0.1)
		end
	end)
	ctx.handle._ending = math.max(ctx.handle._ending, Fx.layerEnd(layer))
end

local function buildEvent(ctx: Ctx, layer: Layer)
	local name = layer.name :: string
	at(ctx.handle, layer.at or 0, function()
		fire(ctx.handle, name)
	end)
end

----------------------------------------------------------------------------------------------------
-- Playing

local pools: { [string]: { Model } } = {}
local live = 0

-- Global time scale for every playing effect and the shared scheduler (0 freezes a frame for review).
function Fx.setGlobalTimeScale(scale: number)
	Scheduler.setTimeScale(scale)
	for handle in handles do
		Handle.setTimeScale(handle, handle._scale)
	end
end

-- Live effect count (for leak tests and budgets).
function Fx.live(): number
	return live
end

local function originOf(origin: CFrame | BasePart | Attachment): CFrame
	if typeof(origin) == "CFrame" then
		return origin
	elseif origin:IsA("Attachment") then
		return origin.WorldCFrame
	end
	return (origin :: BasePart).CFrame
end

-- Plays a definition at `origin` (a CFrame, or a part/attachment it starts from). Returns a Handle.
function Fx.play(def: Definition, origin: CFrame | BasePart | Attachment, opts: PlayOptions?): Handle
	local o: PlayOptions = opts or {}
	local quality: Quality = o.quality or Fx.getQuality()
	local scale = math.clamp(o.scale or 1, 0.05, 20)
	local palette: { [string]: Color3 } = table.clone(Fx.Palette)
	local definitionPalette: { [string]: Color3 } = def.palette or {}
	for role, color in definitionPalette do
		palette[role] = color
	end
	local optionPalette: { [string]: Color3 } = o.palette or {}
	for role, color in optionPalette do
		palette[role] = color
	end
	local cf = originOf(origin)
	local root = Instance.new("Model")
	root.Name = "Fx_" .. def.name
	local anchor = effectPart("Anchor", "block", "SmoothPlastic")
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = cf
	anchor.Parent = root
	root.PrimaryPart = anchor
	live += 1
	local function release(model: Model)
		live -= 1
		model:Destroy()
	end
	local handle = newHandle(root, anchor, cf, release, o)
	if typeof(origin) ~= "CFrame" and o.follow == nil then
		handle._follow = origin :: any
	end
	local ctx: Ctx =
		{ handle = handle, root = root, anchor = anchor, scale = scale, palette = palette, quality = quality, opts = o }
	for index, layer in def.layers do
		if Fx.allowed(layer, quality) then
			local kind = layer.kind
			if kind == "particles" then
				buildParticles(ctx, layer, index)
			elseif kind == "mesh" then
				buildMesh(ctx, layer, index)
			elseif kind == "beam" then
				buildBeam(ctx, layer, index)
			elseif kind == "light" then
				buildLight(ctx, layer, index)
			elseif kind == "sound" then
				buildSound(ctx, layer)
			elseif kind == "camera" then
				buildCamera(ctx, layer)
			elseif kind == "debris" then
				buildDebris(ctx, layer)
			elseif kind == "event" then
				buildEvent(ctx, layer)
			end
		end
	end
	if def.duration then
		handle._ending = def.duration
	end
	handle._ending = math.min(handle._ending, MAX_SECONDS)
	root.Parent = o.parent or workspace
	Handle.setTimeScale(handle, o.timeScale or 1)
	handle._stopJob = Scheduler.every(function(dt)
		return step(handle, dt)
	end)
	step(handle, 0)
	return handle
end

----------------------------------------------------------------------------------------------------
-- Editor-authored effects (instances with attributes).
-- Adapted from RoClicks `roblox-vfx/templates/Emit.luau` (MIT, © 2026 RoClicks), itself adapted from
-- Roqer's roblox-animation-vfx emit.lua (MIT, © 2026 TabooHarmony). See THIRD_PARTY_NOTICES.md.
-- Changes: strict types, the shared scheduler, pooling of played copies, quality filtering
-- (`MinQuality` attribute), Sound children (`EmitDelay`), palette-free.
--
-- Attributes: ParticleEmitter EmitDelay, EmitCount (burst) or EmitDuration (Rate for that long);
-- Beam/Trail EmitDelay, EmitDuration; PointLight/SpotLight/SurfaceLight EmitDelay, EmitDuration
-- (Brightness fades to 0); Sound EmitDelay; any instance MinQuality ("Medium"/"High");
-- a Model/Folder holding parts named Start and End tweens Start to End over Duration (Easing,
-- EasingDirection, Spin degrees); the root's EffectDuration overrides the end.

local function numberAttr(inst: Instance, name: string, default: number?): number?
	local value = inst:GetAttribute(name)
	if typeof(value) == "number" and value == value then
		return value
	end
	return default
end

local function emitCollect(self: Internal, root: Instance, quality: Quality, playSound: boolean)
	local everything = root:GetDescendants()
	table.insert(everything, root)
	local meshes: { { container: Instance, start: BasePart, finish: BasePart } } = {}
	for _, inst in everything do
		local minimum = inst:GetAttribute("MinQuality")
		if type(minimum) == "string" and (QUALITY_RANK[quality] or 3) < (QUALITY_RANK[minimum] or 1) then
			if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Light") then
				(inst :: any).Enabled = false
			end
			continue
		end
		local delay = numberAttr(inst, "EmitDelay", 0) :: number
		if inst:IsA("BasePart") then
			inst.Anchored, inst.CanCollide, inst.CanQuery, inst.CanTouch, inst.CastShadow =
				true, false, false, false, false
		end
		if inst:IsA("ParticleEmitter") then
			local count = numberAttr(inst, "EmitCount", nil)
			local duration = numberAttr(inst, "EmitDuration", nil)
			if count == nil and duration == nil then
				continue
			end
			table.insert(self._emitters, inst)
			self._authoredScale[inst] = inst.TimeScale
			inst.Enabled = false
			local lifetime = inst.Lifetime.Max / math.max(inst.TimeScale, 0.05)
			if count then
				local n = Fx.countFor(count, quality, 1)
				at(self, delay, function()
					inst:Emit(n)
				end)
				self._ending = math.max(self._ending, delay + lifetime)
			end
			if duration then
				at(self, delay, function()
					inst.Enabled = true
				end)
				at(self, delay + duration, function()
					inst.Enabled = false
				end)
				self._ending = math.max(self._ending, delay + duration + lifetime)
			end
		elseif inst:IsA("Beam") or inst:IsA("Trail") then
			local duration = numberAttr(inst, "EmitDuration", nil)
			local ribbon = inst :: any
			if duration then
				ribbon.Enabled = false
				at(self, delay, function()
					ribbon.Enabled = true
				end)
				at(self, delay + duration, function()
					ribbon.Enabled = false
				end)
				if inst:IsA("Trail") then
					self._ending = math.max(self._ending, delay + duration + inst.Lifetime)
				end
			end
		elseif inst:IsA("Light") then
			local duration = numberAttr(inst, "EmitDuration", nil)
			if duration then
				-- Pooled copies reuse lights that already faded: keep the authored brightness.
				local stored = inst:GetAttribute("FxBrightness")
				local brightness = if type(stored) == "number" then stored else inst.Brightness
				inst:SetAttribute("FxBrightness", brightness)
				inst.Brightness = brightness
				inst.Enabled = false
				at(self, delay, function()
					inst.Enabled = true
				end)
				over(self, delay, duration, function(alpha)
					inst.Brightness = brightness * (1 - Motion.ease("quadOut", alpha))
				end)
			end
		elseif inst:IsA("Sound") then
			if playSound and inst:GetAttribute("EmitDelay") ~= nil then
				at(self, delay, function()
					inst:Play()
				end)
			end
		elseif inst:IsA("Model") or inst:IsA("Folder") then
			local start, finish = inst:FindFirstChild("Start"), inst:FindFirstChild("End")
			if start and finish and start:IsA("BasePart") and finish:IsA("BasePart") then
				table.insert(meshes, { container = inst :: Instance, start = start, finish = finish })
			end
		end
	end
	for _, entry in meshes do
		local container, start, finish = entry.container, entry.start, entry.finish
		local delay = numberAttr(container, "EmitDelay", 0) :: number
		local duration = numberAttr(container, "Duration", 0.4) :: number
		local styleName = container:GetAttribute("Easing")
		local ease: Motion.Ease = if styleName == "Linear"
			then "linear"
			elseif styleName == "Back" then "backOut"
			elseif styleName == "Exponential" then "expoOut"
			else "quadOut"
		local spin = math.rad(numberAttr(container, "Spin", 0) :: number)
		local from = { cf = start.CFrame, size = start.Size, alpha = start.Transparency, color = start.Color }
		local to = { cf = finish.CFrame, size = finish.Size, alpha = finish.Transparency, color = finish.Color }
		finish:Destroy()
		start.Transparency = 1
		over(self, delay, duration, function(alpha)
			local e = Motion.ease(ease, alpha)
			start.CFrame = from.cf:Lerp(to.cf, e) * CFrame.Angles(0, spin * e, 0)
			start.Size = from.size:Lerp(to.size, e)
			start.Transparency = from.alpha + (to.alpha - from.alpha) * e
			start.Color = from.color:Lerp(to.color, e)
		end)
		at(self, delay + duration, function()
			start.Transparency = 1
		end)
	end
end

-- Plays a copy of an editor-authored effect (a Model or BasePart) at `cframe`; copies are pooled.
function Fx.emit(template: Model | BasePart, cframe: CFrame, opts: PlayOptions?): Handle
	local o: PlayOptions = opts or {}
	local quality: Quality = o.quality or Fx.getQuality()
	local key = template:GetFullName()
	local pool = pools[key]
	local copy: Instance? = if pool and #pool > 0 then table.remove(pool) else nil
	local fresh = copy or template:Clone()
	local root: Model
	if fresh:IsA("Model") then
		root = fresh
		root:PivotTo(cframe)
	else
		root = Instance.new("Model")
		root.Name = template.Name
		local part = fresh :: BasePart
		part.CFrame = cframe
		part.Parent = root
	end
	local anchor = root.PrimaryPart or root:FindFirstChildWhichIsA("BasePart", true)
	assert(anchor, `Fx.emit: {template:GetFullName()} has no part to anchor to`)
	live += 1
	local function release(model: Model)
		live -= 1
		model.Parent = nil
		-- Start/End meshes are consumed, so only effects without them are reused.
		local reusable = model:FindFirstChild("Start", true) == nil
		local list = pools[key] or {}
		pools[key] = list
		if reusable and #list < POOL_SIZE then
			for _, d in model:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d:Clear()
				end
			end
			table.insert(list, model)
		else
			model:Destroy()
		end
	end
	local handle = newHandle(root, anchor :: BasePart, cframe, release, o)
	emitCollect(handle, root, quality, o.sound ~= false)
	local override = numberAttr(root, "EffectDuration", nil)
	if override then
		handle._ending = override
	end
	handle._ending = math.min(handle._ending, MAX_SECONDS)
	root.Parent = o.parent or workspace
	Handle.setTimeScale(handle, o.timeScale or 1)
	handle._stopJob = Scheduler.every(function(dt)
		return step(handle, dt)
	end)
	step(handle, 0)
	return handle
end

return Fx
