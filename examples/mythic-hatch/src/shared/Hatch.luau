--!strict
-- Mythic Hatch: the rules (rarity odds, roll, timeline) and the hatch effects, shared by server and
-- client. The server rolls; clients only present what the server decided.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Fx = require(Kit:WaitForChild("Fx"))

local Hatch = {}

export type Rarity = string -- "Common" | "Rare" | "Mythic" (keys of Hatch.looks)
export type Look = {
	name: string,
	weight: number,
	palette: { [string]: Color3 },
	shell: Color3,
	speckle: Color3,
	wing: Color3,
	wingTip: Color3,
	glow: { number }, -- creature glow stat range
	wobbles: number,
	confetti: number,
	title: string,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Hatch.order = { "Common", "Rare", "Mythic" } :: { Rarity }

-- Each rarity has its own palette and how much ceremony it gets: more wobbles, more confetti.
Hatch.looks = {
	Common = {
		name = "Common",
		weight = 70,
		palette = { core = rgb(240, 255, 236), glow = rgb(170, 220, 180), accent = rgb(120, 190, 150), spark = rgb(220, 250, 220), dark = rgb(40, 60, 50) },
		shell = rgb(212, 220, 198),
		speckle = rgb(92, 148, 102),
		wing = rgb(186, 226, 196),
		wingTip = rgb(120, 186, 150),
		glow = { 10, 40 },
		wobbles = 2,
		confetti = 30,
		title = "Common",
	},
	Rare = {
		name = "Rare",
		weight = 25,
		palette = { core = rgb(255, 250, 230), glow = rgb(255, 196, 96), accent = rgb(255, 150, 70), spark = rgb(255, 230, 160), dark = rgb(70, 40, 20) },
		shell = rgb(236, 210, 164),
		speckle = rgb(196, 116, 40),
		wing = rgb(255, 212, 130),
		wingTip = rgb(240, 140, 60),
		glow = { 40, 75 },
		wobbles = 3,
		confetti = 60,
		title = "Rare",
	},
	Mythic = {
		name = "Mythic",
		weight = 5,
		palette = { core = rgb(255, 246, 255), glow = rgb(250, 120, 200), accent = rgb(110, 220, 255), spark = rgb(255, 220, 250), dark = rgb(40, 20, 60) },
		shell = rgb(222, 204, 242),
		speckle = rgb(116, 70, 196),
		wing = rgb(140, 220, 255),
		wingTip = rgb(250, 120, 200),
		glow = { 75, 100 },
		wobbles = 4,
		confetti = 110,
		title = "Mythic",
	},
} :: { [Rarity]: Look }

-- Picks a rarity from a uniform number in [0, 1) (pure; the server passes a server-side RNG value).
function Hatch.roll(u: number): Rarity
	local total = 0
	for _, rarity in Hatch.order do
		total += Hatch.looks[rarity].weight
	end
	local pick = math.clamp(u, 0, 0.999999) * total
	for _, rarity in Hatch.order do
		pick -= Hatch.looks[rarity].weight
		if pick < 0 then
			return rarity
		end
	end
	return Hatch.order[#Hatch.order]
end

-- Glow stat inside the rarity's range (pure).
function Hatch.glowFor(rarity: Rarity, u: number): number
	local range = Hatch.looks[rarity].glow
	return math.floor(range[1] + (range[2] - range[1]) * math.clamp(u, 0, 1) + 0.5)
end

export type Timeline = { wobble: number, burst: number, reveal: number, card: number, done: number }

-- Seconds from the start of a hatch (pure). Rarer eggs wobble longer before they burst.
function Hatch.timeline(rarity: Rarity): Timeline
	local wobbles = Hatch.looks[rarity].wobbles
	local burst = 0.5 + wobbles * 0.55
	return { wobble = 0.5, burst = burst, reveal = burst + 0.15, card = burst + 0.9, done = burst + 2.4 }
end

-- The burst at the egg's base: flash, a soft ring, light, confetti in the rarity's colours, a chime.
function Hatch.burst(rarity: Rarity): Fx.Definition
	local look = Hatch.looks[rarity]
	local layers: { Fx.Layer } = {
		{ kind = "event", at = 0, name = "burst" },
		{ kind = "sound", at = 0, id = "rbxasset://sounds/moonbrick/fanfare.wav", volume = 0.8 },
		{ kind = "camera", at = 0, fov = { 6, 0.4 }, flash = { color = "core", time = 0.25 }, shake = { 0.25, 0.6 } },
		{ kind = "light", at = 0, color = "glow", range = 16, lightKeys = { { 0, 2.4 }, { 0.4, 1 }, { 2.2, 0 } } },
		{
			kind = "mesh",
			name = "Flash",
			shape = "ball",
			material = "Neon",
			color = "core",
			offset = CFrame.new(0, 2.2, 0),
			keys = {
				{ t = 0, size = 0.8, transparency = 0.2 },
				{ t = 0.08, size = 2.6, transparency = 0.6, ease = "expoOut" },
				{ t = 0.22, size = 3, transparency = 1 },
			},
		},
		{
			kind = "mesh",
			name = "Ring",
			shape = "torus",
			material = "Neon",
			color = "glow",
			offset = CFrame.new(0, 0.6, 0),
			keys = {
				{ t = 0, size = Vector3.new(2, 0.4, 2), transparency = 0.1 },
				{ t = 0.8, size = Vector3.new(16, 0.15, 16), transparency = 1, ease = "expoOut" },
			},
		},
		{
			kind = "particles",
			name = "Confetti",
			texture = "star",
			count = look.confetti,
			offset = CFrame.new(0, 2.4, 0),
			speed = { 14, 26 },
			drag = 2.5,
			acceleration = Vector3.new(0, -9, 0),
			spread = 70,
			lifetime = { 1.4, 2.4 },
			size = { { 0, 0.5 }, { 1, 0.15 } },
			color = { "glow", "accent", "spark" },
			rotSpeed = { -260, 260 },
		},
		{
			kind = "particles",
			name = "Puff",
			texture = "smoke",
			count = 8,
			offset = CFrame.new(0, 1.6, 0),
			speed = { 3, 6 },
			drag = 2,
			lifetime = { 0.8, 1.2 },
			size = { { 0, 2 }, { 1, 5 } },
			transparency = { { 0, 0.4 }, { 1, 1 } },
			color = "core",
			lightEmission = 0.3,
			minQuality = "Medium",
		},
	}
	return Fx.define({ name = rarity .. "Burst", palette = look.palette, layers = layers })
end

-- The rarity aura that settles under the newborn creature and keeps glowing for a while.
function Hatch.aura(rarity: Rarity): Fx.Definition
	local look = Hatch.looks[rarity]
	return Fx.define({
		name = rarity .. "Aura",
		palette = look.palette,
		layers = {
			{
				kind = "mesh",
				name = "Halo",
				shape = "torus",
				material = "Neon",
				color = "glow",
				offset = CFrame.new(0, 0.5, 0),
				spin = 50,
				spinAxis = Vector3.yAxis,
				keys = {
					{ t = 0, size = Vector3.new(0.5, 0.25, 0.5), transparency = 1 },
					{ t = 0.5, size = Vector3.new(4.8, 0.25, 4.8), transparency = 0.5, ease = "backOut" },
					{ t = 5.5, size = Vector3.new(5.2, 0.25, 5.2), transparency = 0.65 },
					{ t = 6.5, size = Vector3.new(5.8, 0.25, 5.8), transparency = 1 },
				},
			},
			{
				kind = "particles",
				name = "Motes",
				texture = "glow",
				rate = 12,
				duration = 6,
				shape = "Disc",
				shapeSize = 2.6,
				direction = Vector3.yAxis,
				speed = { 1.5, 3 },
				lifetime = { 1.6, 2.4 },
				size = { { 0, 0.35 }, { 1, 0 } },
				color = { "glow", "accent" },
			},
		},
	})
end

return Hatch
