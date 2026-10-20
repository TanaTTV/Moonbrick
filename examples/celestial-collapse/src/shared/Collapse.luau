--!strict
-- Celestial Collapse: one reusable ability composition, restyled by data.
-- A style changes palette, textures, timing, silhouettes (sphere vs shard cluster, dome vs spires),
-- materials, camera weight and sounds; the phases, timeline and gameplay stay the same.
--
--   local plan = Collapse.build(Collapse.styles.Celestial)
--   plan.timeline.impact   -- seconds from cast start to impact (the server uses the same numbers)
--   plan.orb / plan.impact -- Fx definitions; plan.poses.gather / rise / throw / recover -- Pose clips
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Fx = require(Kit:WaitForChild("Fx"))
local Pose = require(Kit:WaitForChild("Pose"))

local Collapse = {}

export type Style = {
	name: string,
	palette: { [string]: Color3 },
	timing: { gather: number, rise: number, flight: number, implode: number, aftermath: number, hitstop: number },
	orb: { form: "sphere" | "shards", material: string, size: number, spin: number },
	blast: { form: "dome" | "spires", radius: number },
	textures: { mote: string, spark: string, smoke: string, streak: string, scar: string },
	camera: { shake: number, fov: number },
	sounds: { charge: string, hum: string, whoosh: string, implode: string, boom: string },
	motion: { grow: string, implode: string, blast: string, throw: string },
}

local function sound(name: string): string
	-- Original sounds from `scripts/sfx.py` (local Studio preview). Swap in your uploaded ids to ship.
	return "rbxasset://sounds/moonbrick/" .. name .. ".wav"
end

Collapse.styles = {} :: { [string]: Style }

-- Sun-bleached sky magic: a star forms, swells overhead, falls, collapses to a point and detonates
-- as a clean white-gold dome with cyan rings. Fast, bright, round silhouettes.
Collapse.styles.Celestial = {
	name = "Celestial",
	palette = {
		core = Color3.fromRGB(255, 252, 240),
		glow = Color3.fromRGB(255, 196, 92),
		accent = Color3.fromRGB(96, 214, 255),
		dark = Color3.fromRGB(58, 36, 26),
		smoke = Color3.fromRGB(214, 190, 162),
		spark = Color3.fromRGB(255, 236, 180),
		ground = Color3.fromRGB(120, 86, 60),
	},
	timing = { gather = 0.85, rise = 0.7, flight = 0.45, implode = 0.28, aftermath = 3.2, hitstop = 0.06 },
	orb = { form = "sphere", material = "Neon", size = 3.2, spin = 140 },
	blast = { form = "dome", radius = 18 },
	textures = { mote = "glow", spark = "star", smoke = "smoke", streak = "streak", scar = "crack" },
	camera = { shake = 2.2, fov = 10 },
	sounds = {
		charge = sound("charge"),
		hum = sound("hum"),
		whoosh = sound("whoosh"),
		implode = sound("implode"),
		boom = sound("boom"),
	},
	motion = { grow = "backOut", implode = "backIn", blast = "expoOut", throw = "quadIn" },
}

-- Ink from the deep: a cluster of black shards gathers slowly, a heavy pause, then the ground erupts
-- in jagged spires under a sickly green light. Slow, heavy, angular silhouettes; dark layers dominate.
Collapse.styles.Abyssal = {
	name = "Abyssal",
	palette = {
		core = Color3.fromRGB(196, 255, 170),
		glow = Color3.fromRGB(86, 210, 120),
		accent = Color3.fromRGB(40, 120, 90),
		dark = Color3.fromRGB(8, 10, 12),
		smoke = Color3.fromRGB(20, 26, 24),
		spark = Color3.fromRGB(170, 255, 150),
		ground = Color3.fromRGB(30, 34, 30),
	},
	timing = { gather = 1.35, rise = 0.9, flight = 0.6, implode = 0.55, aftermath = 4.2, hitstop = 0.16 },
	orb = { form = "shards", material = "Glass", size = 3.6, spin = -60 },
	blast = { form = "spires", radius = 15 },
	textures = { mote = "wisp", spark = "shard", smoke = "smoke", streak = "shard", scar = "crack" },
	camera = { shake = 3.0, fov = 4 },
	sounds = {
		charge = sound("hum"),
		hum = sound("hum"),
		whoosh = sound("whoosh"),
		implode = sound("implode"),
		boom = sound("boom"),
	},
	motion = { grow = "anticipate", implode = "expoIn", blast = "backOut", throw = "anticipate" },
}

export type Timeline = { gather: number, rise: number, throw: number, impact: number, blast: number, finish: number }

-- Cast timeline in seconds from the cast (pure; the server schedules damage at `blast`).
function Collapse.timeline(style: Style): Timeline
	local t = style.timing
	local rise = t.gather
	local throw = rise + t.rise
	local impact = throw + t.flight
	local blast = impact + t.implode
	return { gather = 0, rise = rise, throw = throw, impact = impact, blast = blast, finish = blast + t.aftermath }
end

-- Orb meshes: one sphere, or a ring of six shards around the centre.
local function orbLayers(style: Style, keys: { Fx.MeshKey }): { Fx.Layer }
	local layers: { Fx.Layer } = {}
	if style.orb.form == "sphere" then
		-- A small white-hot core inside a gold glass body reads as a forming star, not a flat white ball.
		local core, body = {}, {}
		for _, k in keys do
			local size = if type(k.size) == "number" then k.size else nil
			table.insert(core, Fx.key(k.t, { size = if size then size * 0.55 else nil, ease = k.ease }))
			table.insert(
				body,
				Fx.key(k.t, { size = size, transparency = math.max(k.transparency or 0, 0.35), ease = k.ease })
			)
		end
		table.insert(
			layers,
			{ kind = "mesh", name = "OrbCore", shape = "ball", material = "Neon", color = "core", keys = core }
		)
		table.insert(layers, {
			kind = "mesh",
			name = "OrbBody",
			shape = "ball",
			material = style.orb.material,
			color = "glow",
			keys = body,
		})
		local halo = {}
		for i, k in keys do
			local size = if type(k.size) == "number" then k.size * 1.45 else nil
			-- A soft shell around the core: hidden on the first key, translucent afterwards.
			table.insert(halo, {
				t = k.t,
				size = size,
				transparency = if i == 1 then 1 else math.max(k.transparency or 0, 0.6),
				ease = k.ease,
			})
		end
		table.insert(
			layers,
			{ kind = "mesh", name = "OrbHalo", shape = "ball", material = "ForceField", color = "glow", keys = halo }
		)
	else
		for i = 1, 6 do
			local angle = (i - 1) * math.pi / 3
			local shard = {}
			for _, k in keys do
				local s = if type(k.size) == "number" then k.size else 1
				table.insert(shard, {
					t = k.t,
					size = Vector3.new(s * 0.32, s * 0.9, s * 0.32),
					transparency = k.transparency,
					offset = CFrame.Angles(0, angle, 0)
						* CFrame.new(0, 0, -s * 0.3)
						* CFrame.Angles(math.rad(28), 0, 0),
					ease = k.ease,
				})
			end
			table.insert(layers, {
				kind = "mesh",
				name = `Shard{i}`,
				shape = "wedge",
				material = style.orb.material,
				color = if i % 2 == 0 then "dark" else "accent",
				keys = shard,
				spin = style.orb.spin,
			})
		end
		table.insert(layers, {
			kind = "mesh",
			name = "OrbHeart",
			shape = "ball",
			material = "Neon",
			color = "glow",
			keys = { { t = 0, size = 0.1 }, { t = keys[#keys].t, size = style.orb.size * 0.35, ease = "quadOut" } },
		})
	end
	return layers
end

-- The orb from the first glimmer in the hand to impact. Play it on a carrier part the caster script
-- moves (hand → overhead → arc to the target); `impact` fires when it lands.
local function orbDefinition(style: Style, timeline: Timeline): Fx.Definition
	local size = style.orb.size
	local layers: { Fx.Layer } = orbLayers(style, {
		{ t = 0, size = 0.15, transparency = 0.2 },
		{ t = timeline.rise, size = size * 0.36, ease = style.motion.grow :: any },
		{ t = timeline.throw, size = size, ease = style.motion.grow :: any },
		{ t = timeline.impact, size = size * 1.05 },
	})
	local function add(layer: Fx.Layer)
		table.insert(layers, layer)
	end
	-- Gather: motes stream in from a sphere around the hand.
	add({
		kind = "particles",
		name = "Gather",
		at = 0,
		texture = style.textures.mote,
		rate = 140,
		duration = timeline.rise,
		shape = "Sphere",
		shapeSize = 3.2,
		inward = true,
		speed = { 4, 7 },
		lifetime = { 0.35, 0.55 },
		size = { { 0, 0.6 }, { 1, 1.1 } },
		transparency = { { 0, 1 }, { 0.3, 0.2 }, { 1, 0 } },
		color = { "accent", "core" },
		lightEmission = 1,
	})
	add({
		kind = "particles",
		name = "GatherStreaks",
		at = 0,
		texture = style.textures.streak,
		rate = 50,
		duration = timeline.rise,
		shape = "Sphere",
		shapeSize = 4.5,
		inward = true,
		speed = { 8, 12 },
		lifetime = { 0.3, 0.45 },
		orientation = "VelocityParallel",
		size = { { 0, 0.25 }, { 1, 0.1 } },
		squash = { { 0, 3 }, { 1, 1 } },
		color = "spark",
		minQuality = "Medium",
	})
	add({ kind = "light", at = 0, color = "glow", range = 10, lightKeys = { { 0, 0 }, { timeline.impact, 2.2 } } })
	add({
		kind = "particles",
		name = "StarFlare",
		at = timeline.rise * 0.4,
		texture = style.textures.spark,
		rate = 8,
		duration = timeline.impact - timeline.rise * 0.4,
		locked = true,
		speed = { 0, 0 },
		lifetime = { 0.35, 0.5 },
		size = { { 0, size * 0.9 }, { 0.5, size * 1.4 }, { 1, size * 0.6 } },
		transparency = { { 0, 1 }, { 0.3, 0.15 }, { 1, 1 } },
		rotation = { 0, 90 },
		rotSpeed = { -40, 40 },
		color = "core",
		zOffset = 1,
	})
	add({ kind = "sound", at = 0, id = style.sounds.charge, volume = 0.7 })
	-- Rise: a ring orbits the swollen orb; sparks shed off it.
	add({
		kind = "mesh",
		name = "OrbRing",
		at = timeline.rise,
		shape = "torus",
		material = "Neon",
		color = "accent",
		offset = CFrame.Angles(math.rad(28), 0, math.rad(12)),
		spin = style.orb.spin * 4,
		keys = {
			{ t = 0, size = 0.5, transparency = 1 },
			{ t = timeline.throw - timeline.rise, size = size * 2.2, transparency = 0.25, ease = "backOut" },
			{ t = timeline.impact - timeline.rise, size = size * 1.6, transparency = 0.6 },
		},
	})
	add({
		kind = "particles",
		name = "Shed",
		at = timeline.rise,
		texture = style.textures.spark,
		rate = 40,
		duration = timeline.impact - timeline.rise,
		speed = { 2, 6 },
		lifetime = { 0.4, 0.8 },
		size = { { 0, 0.5 }, { 1, 0 } },
		color = "spark",
		spread = 180,
		rotSpeed = { -120, 120 },
	})
	add({ kind = "sound", at = timeline.rise, id = style.sounds.hum, volume = 0.45 })
	-- Flight: a streaking trail and a whoosh.
	add({
		kind = "particles",
		name = "Trail",
		at = timeline.throw,
		texture = style.textures.streak,
		rate = 120,
		duration = timeline.impact - timeline.throw,
		speed = { 0, 1 },
		lifetime = { 0.25, 0.4 },
		size = { { 0, size * 0.55 }, { 1, 0 } },
		transparency = { { 0, 0.1 }, { 1, 1 } },
		color = { "core", "accent" },
		minQuality = "Medium",
	})
	add({ kind = "sound", at = timeline.throw, id = style.sounds.whoosh })
	add({ kind = "event", at = timeline.impact, name = "impact" })
	return Fx.define({
		name = style.name .. "Orb",
		palette = style.palette,
		layers = layers,
		duration = timeline.impact,
	})
end

-- Implosion → explosion → aftermath, at the impact point (origin on the ground, Y up).
local function impactDefinition(style: Style): Fx.Definition
	local t = style.timing
	local blast = t.implode
	local radius = style.blast.radius
	local layers: { Fx.Layer } = {}
	local function add(layer: Fx.Layer)
		table.insert(layers, layer)
	end
	-- Implosion: the orb collapses to a point while light and air are pulled in.
	for _, layer in
		orbLayers(style, {
			{ t = 0, size = style.orb.size * 1.05 },
			{ t = blast, size = 0.25, ease = style.motion.implode :: any },
		})
	do
		layer.offset = CFrame.new(0, 2, 0)
		add(layer)
	end
	add({
		kind = "mesh",
		name = "Pull",
		shape = "torus",
		material = "Neon",
		color = "dark",
		offset = CFrame.new(0, 0.3, 0),
		keys = {
			{ t = 0, size = radius * 1.4, transparency = 0.6 },
			{ t = blast, size = 0.5, transparency = 0, ease = "expoIn" },
		},
	})
	add({
		kind = "particles",
		name = "Inrush",
		texture = style.textures.streak,
		count = 50,
		shape = "Sphere",
		shapeSize = radius * 0.7,
		inward = true,
		offset = CFrame.new(0, 2, 0),
		speed = { radius * 1.8, radius * 2.4 },
		lifetime = { blast * 0.9, blast },
		orientation = "VelocityParallel",
		size = { { 0, 0.3 }, { 1, 0.1 } },
		squash = { { 0, 2.5 }, { 1, 1 } },
		color = "accent",
	})
	add({ kind = "sound", at = 0, id = style.sounds.implode })
	add({ kind = "event", at = 0, name = "implode" })
	-- Detonation.
	add({ kind = "event", at = blast, name = "blast" })
	add({ kind = "sound", at = blast, id = style.sounds.boom })
	add({
		kind = "camera",
		at = blast,
		shake = { 0.8, style.camera.shake },
		fov = { style.camera.fov, 0.5 },
		flash = { color = "core", time = 0.18 },
		-- The deep presses on the whole world: Abyssal drains colour for a moment; Celestial stays warm.
		grade = if style.blast.form == "spires"
			then { color = "glow", contrast = 0.35, saturation = -0.7, time = 2.4 }
			else { color = "glow", contrast = 0.1, saturation = 0.15, time = 0.8 },
	})
	add({
		kind = "light",
		at = blast,
		color = "core",
		range = radius * 1.1,
		lightKeys = { { 0, 3 }, { 0.15, 1.5 }, { 0.9, 0 } },
	})
	if style.blast.form == "dome" then
		add({
			kind = "mesh",
			name = "Flash",
			at = blast,
			shape = "ball",
			material = "Neon",
			color = "core",
			offset = CFrame.new(0, 2, 0),
			keys = {
				{ t = 0, size = 1, transparency = 0, color = "core" },
				{ t = 0.08, size = radius * 0.5, transparency = 0.15, color = "core", ease = "expoOut" },
				{ t = 0.3, size = radius * 0.6, transparency = 1, color = "glow" },
			},
		})
		add({
			kind = "mesh",
			name = "Shell",
			at = blast,
			shape = "ball",
			material = "ForceField",
			color = "glow",
			keys = {
				{ t = 0, size = 2, transparency = 0.25 },
				{ t = 0.35, size = radius * 1.2, transparency = 0.55, ease = style.motion.blast :: any },
				{ t = 0.7, size = radius * 1.35, transparency = 1 },
			},
		})
		for i, delay in { 0, 0.09 } do
			add({
				kind = "mesh",
				name = `Wave{i}`,
				at = blast + delay,
				shape = "torus",
				material = "Neon",
				color = if i == 1 then "accent" else "glow",
				offset = CFrame.new(0, 0.4, 0),
				keys = {
					{ t = 0, size = 2, transparency = 0 },
					{ t = 0.7, size = radius * (2.6 - i * 0.5), transparency = 1, ease = "expoOut" },
				},
			})
		end
		add({
			kind = "mesh",
			name = "Pillar",
			at = blast,
			shape = "cylinder",
			material = "Neon",
			color = "glow",
			offset = CFrame.new(0, 12, 0),
			keys = {
				{ t = 0, size = Vector3.new(22, 0.5, 0.5), transparency = 0.55 },
				{ t = 0.45, size = Vector3.new(26, 0.1, 0.1), transparency = 1, ease = "quadIn" },
			},
		})
	else
		-- Spires: jagged shards erupt from the ground in a ring and sink back.
		for i = 1, 9 do
			local angle = (i - 1) * math.pi * 2 / 9 + (if i % 2 == 0 then 0.2 else 0)
			local distance = radius * (if i % 2 == 0 then 0.35 else 0.6)
			local height = radius * (if i % 2 == 0 then 0.9 else 0.6)
			local base = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -distance) * CFrame.Angles(math.rad(-14), 0, 0)
			add({
				kind = "mesh",
				name = `Spire{i}`,
				at = blast + (i % 3) * 0.04,
				shape = "shard",
				material = "Glass",
				color = if i % 3 == 0 then "accent" else "dark",
				keys = {
					Fx.key(
						0,
						{ size = Vector3.new(1.5, 0.2, 1.5), offset = base * CFrame.new(0, -1, 0), transparency = 0 }
					),
					Fx.key(0.22, {
						size = Vector3.new(2.4, height, 2.4),
						offset = base * CFrame.new(0, height / 2, 0),
						ease = "backOut",
					}),
					Fx.key(1.8, { size = Vector3.new(2.4, height, 2.4), offset = base * CFrame.new(0, height / 2, 0) }),
					Fx.key(2.6, {
						size = Vector3.new(2, height * 0.2, 2),
						offset = base * CFrame.new(0, -height * 0.2, 0),
						transparency = 1,
						ease = "quadIn",
					}),
				},
			})
		end
		add({
			kind = "mesh",
			name = "Wave",
			at = blast,
			shape = "torus",
			material = "Neon",
			color = "glow",
			offset = CFrame.new(0, 0.4, 0),
			keys = {
				{ t = 0, size = 2, transparency = 0.2 },
				{ t = 0.9, size = radius * 2.2, transparency = 1, ease = "expoOut" },
			},
		})
	end
	-- Shared aftermath layers: sparks, embers, smoke with a dark under-layer, debris, the scar.
	add({
		kind = "particles",
		name = "Sparks",
		at = blast,
		texture = style.textures.spark,
		count = 70,
		offset = CFrame.new(0, 2, 0),
		speed = { radius * 3, radius * 6 },
		drag = 4,
		spread = 180,
		lifetime = { 0.5, 1.1 },
		size = { { 0, 1.1 }, { 1, 0 } },
		color = { "core", "spark", "glow" },
		rotSpeed = { -200, 200 },
	})
	add({
		kind = "particles",
		name = "SmokeDark",
		at = blast + 0.03,
		texture = style.textures.smoke,
		flipbook = 4,
		count = 14,
		shape = "Sphere",
		shapeSize = radius * 0.22,
		spread = 60,
		direction = Vector3.yAxis,
		speed = { 6, 14 },
		drag = 1.2,
		acceleration = Vector3.new(0, 2, 0),
		lifetime = { 1.8, 2.8 },
		size = { { 0, radius * 0.25 }, { 1, radius * 0.55 } },
		transparency = { { 0, 0.15 }, { 1, 1 } },
		color = "dark",
		lightEmission = 0,
		rotSpeed = { -30, 30 },
		zOffset = -1,
	})
	add({
		kind = "particles",
		name = "SmokeLight",
		at = blast + 0.08,
		texture = style.textures.smoke,
		flipbook = 4,
		count = 10,
		shape = "Disc",
		shapeSize = radius * 0.3,
		direction = Vector3.yAxis,
		speed = { 8, 16 },
		drag = 1.2,
		acceleration = Vector3.new(0, 3, 0),
		lifetime = { 1.6, 2.4 },
		size = { { 0, radius * 0.2 }, { 1, radius * 0.45 } },
		transparency = { { 0, 0.4 }, { 1, 1 } },
		color = "smoke",
		lightEmission = 0.2,
		rotSpeed = { -30, 30 },
		minQuality = "Medium",
	})
	add({
		kind = "particles",
		name = "Embers",
		at = blast + 0.1,
		texture = style.textures.mote,
		rate = 35,
		duration = t.aftermath * 0.6,
		shape = "Disc",
		shapeSize = radius * 0.5,
		direction = Vector3.yAxis,
		speed = { 2, 5 },
		acceleration = Vector3.new(0, 1.5, 0),
		lifetime = { 1.5, 2.5 },
		size = { { 0, 0.3 }, { 1, 0 } },
		color = "glow",
		minQuality = "Medium",
	})
	add({
		kind = "debris",
		at = blast,
		count = 14,
		sizeRange = { 0.5, 1.4 },
		speed = { radius * 1.6, radius * 2.6 },
		lifetime = { 1.6, 2.6 },
		material = "Slate",
		color = "ground",
	})
	add({
		kind = "mesh",
		name = "Scar",
		at = blast,
		shape = "block",
		material = "SmoothPlastic",
		decal = style.textures.scar,
		color = "glow",
		offset = CFrame.new(0, 0.06, 0),
		keys = {
			Fx.key(0, { size = Vector3.new(radius * 1.6, 0.1, radius * 1.6), transparency = 0 }),
			Fx.key(0.8, { transparency = 0.1 }),
			Fx.key(t.aftermath, { transparency = 1, ease = "quadIn" }),
		},
	})
	return Fx.define({ name = style.name .. "Impact", palette = style.palette, layers = layers })
end

-- R15 pose clips (axes measured in Studio: shoulder X+ raises forward, waist X+ leans back).
local function poses(style: Style, timeline: Timeline): { [string]: Pose.Clip }
	local r = math.rad
	local heavy = if style.orb.form == "shards" then 1.25 else 1
	return {
		gather = Pose.clip({
			name = "Gather",
			rig = "R15",
			length = timeline.rise,
			keys = {
				{ t = 0, joints = {} },
				{
					t = timeline.rise * 0.35,
					ease = "quadOut",
					joints = {
						RightShoulder = CFrame.Angles(r(80), 0, r(15)),
						RightElbow = CFrame.Angles(r(35), 0, 0),
						LeftShoulder = CFrame.Angles(r(25), 0, r(-25)),
						Waist = CFrame.Angles(r(-6), r(-10), 0),
						Neck = CFrame.Angles(r(-8), r(-8), 0),
						RightHip = CFrame.Angles(r(-10), 0, 0),
						LeftHip = CFrame.Angles(r(12), 0, 0),
					},
				},
				{
					t = timeline.rise,
					ease = "sineInOut",
					joints = {
						RightShoulder = CFrame.Angles(r(95), 0, r(10)),
						RightElbow = CFrame.Angles(r(20), 0, 0),
						LeftShoulder = CFrame.Angles(r(35), 0, r(-30)),
						Waist = CFrame.Angles(r(-4), r(-12), 0),
						Neck = CFrame.Angles(r(-4), r(-10), 0),
						RightHip = CFrame.Angles(r(-10), 0, 0),
						LeftHip = CFrame.Angles(r(12), 0, 0),
					},
				},
			},
		}),
		rise = Pose.clip({
			name = "Rise",
			rig = "R15",
			length = timeline.throw - timeline.rise,
			keys = {
				{
					t = 0,
					joints = {
						RightShoulder = CFrame.Angles(r(95), 0, r(10)),
						RightElbow = CFrame.Angles(r(20), 0, 0),
						LeftShoulder = CFrame.Angles(r(35), 0, r(-30)),
						Waist = CFrame.Angles(r(-4), r(-12), 0),
					},
				},
				{
					t = (timeline.throw - timeline.rise) * 0.6,
					ease = "backOut",
					joints = {
						RightShoulder = CFrame.Angles(r(165), 0, r(-10)),
						LeftShoulder = CFrame.Angles(r(165), 0, r(10)),
						RightElbow = CFrame.Angles(r(15), 0, 0),
						LeftElbow = CFrame.Angles(r(15), 0, 0),
						Waist = CFrame.Angles(r(14 * heavy), 0, 0),
						Neck = CFrame.Angles(r(25), 0, 0),
						RightHip = CFrame.Angles(r(-6), 0, 0),
						LeftHip = CFrame.Angles(r(6), 0, 0),
					},
				},
				{
					t = timeline.throw - timeline.rise,
					ease = "sineInOut",
					joints = {
						RightShoulder = CFrame.Angles(r(170), 0, r(-6)),
						LeftShoulder = CFrame.Angles(r(170), 0, r(6)),
						RightElbow = CFrame.Angles(r(10), 0, 0),
						LeftElbow = CFrame.Angles(r(10), 0, 0),
						Waist = CFrame.Angles(r(18 * heavy), 0, 0),
						Neck = CFrame.Angles(r(28), 0, 0),
						RightHip = CFrame.Angles(r(-6), 0, 0),
						LeftHip = CFrame.Angles(r(6), 0, 0),
					},
				},
			},
		}),
		throw = Pose.clip({
			name = "Throw",
			rig = "R15",
			length = 0.7,
			keys = {
				{
					t = 0,
					joints = {
						RightShoulder = CFrame.Angles(r(170), 0, r(-6)),
						LeftShoulder = CFrame.Angles(r(170), 0, r(6)),
						Waist = CFrame.Angles(r(18 * heavy), 0, 0),
						Neck = CFrame.Angles(r(28), 0, 0),
					},
				},
				{
					t = 0.18,
					ease = style.motion.throw :: any,
					joints = {
						RightShoulder = CFrame.Angles(r(40), 0, r(-6)),
						LeftShoulder = CFrame.Angles(r(30), 0, r(6)),
						RightElbow = CFrame.Angles(r(10), 0, 0),
						Waist = CFrame.Angles(r(-24 * heavy), 0, 0),
						Neck = CFrame.Angles(r(-12), 0, 0),
						RightHip = CFrame.Angles(r(-28), 0, 0),
						RightKnee = CFrame.Angles(r(-30), 0, 0),
						LeftHip = CFrame.Angles(r(22), 0, 0),
					},
				},
				{
					t = 0.7,
					ease = "quadOut",
					joints = {
						RightShoulder = CFrame.Angles(r(20), 0, r(10)),
						LeftShoulder = CFrame.Angles(r(10), 0, r(-10)),
						Waist = CFrame.Angles(r(-10 * heavy), 0, 0),
						RightHip = CFrame.Angles(r(-14), 0, 0),
						RightKnee = CFrame.Angles(r(-14), 0, 0),
						LeftHip = CFrame.Angles(r(10), 0, 0),
					},
				},
			},
			markers = { { t = 0.12, name = "release" } },
		}),
		recover = Pose.clip({
			name = "Recover",
			rig = "R15",
			length = 0.9,
			keys = {
				{
					t = 0,
					joints = {
						RightShoulder = CFrame.Angles(r(20), 0, r(10)),
						LeftShoulder = CFrame.Angles(r(10), 0, r(-10)),
						Waist = CFrame.Angles(r(-10 * heavy), 0, 0),
					},
				},
				{ t = 0.9, ease = "sineInOut", joints = {} },
			},
		}),
	}
end

export type Plan = {
	style: Style,
	timeline: Timeline,
	orb: Fx.Definition,
	impact: Fx.Definition,
	poses: { [string]: Pose.Clip },
}

local cache: { [string]: Plan } = {}

-- Every definition and pose for a style (cached per style name).
function Collapse.build(style: Style): Plan
	local cached = cache[style.name]
	if cached and cached.style == style then
		return cached
	end
	local timeline = Collapse.timeline(style)
	local plan: Plan = {
		style = style,
		timeline = timeline,
		orb = orbDefinition(style, timeline),
		impact = impactDefinition(style),
		poses = poses(style, timeline),
	}
	cache[style.name] = plan
	return plan
end

-- Where the orb flies: a parabolic arc from `from` to `to`, `alpha` in 0..1 (pure; tested).
function Collapse.arc(from: Vector3, to: Vector3, height: number, alpha: number): Vector3
	local a = math.clamp(alpha, 0, 1)
	local flat = from:Lerp(to, a)
	return flat + Vector3.new(0, 4 * height * a * (1 - a), 0)
end

-- Gameplay: who is hit and how hard (pure; the server is the only caller that applies it).
function Collapse.damageAt(distance: number, radius: number): number
	if distance ~= distance or distance > radius then
		return 0
	end
	local falloff = 1 - math.clamp(distance / radius, 0, 1)
	return math.floor(25 + 55 * falloff * falloff + 0.5)
end

return Collapse
