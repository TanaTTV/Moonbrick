--!strict
-- The Moonlit Grove's props: shapes for Geo.dress. The world file holds plain parts ("spots") with a
-- `GeoShape` attribute; this client gives each one its generated mesh. Coloured shapes paint
-- themselves (vertexColors); the rest take the spot's colour and material.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Geo = require(Kit:WaitForChild("Geo"))
local Tex = require(Kit:WaitForChild("Tex"))

local Grove = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STONE, STONE_DARK, MOSS = rgb(150, 150, 158), rgb(96, 98, 112), rgb(86, 130, 96)

-- Carved plinth: a wide foot, a slim waist and a shallow dish on top; moss creeps up from the ground.
Geo.register("Pedestal", function(b)
	b.colorAt = function(p: Vector3): Color3
		local n = Tex.noise(p.X * 4 + 2, p.Z * 4 + p.Y * 3, 3, 3)
		-- A gilded band under the dish, weathered stone elsewhere.
		return if math.abs(p.Y - 0.32) < 0.04 then rgb(196, 160, 96) else rgb(112, 112, 124):Lerp(rgb(74, 74, 90), n)
	end
	b:lathe({
		Vector2.new(0.001, -0.5),
		Vector2.new(0.5, -0.5),
		Vector2.new(0.5, -0.38),
		Vector2.new(0.4, -0.3),
		Vector2.new(0.3, -0.1),
		Vector2.new(0.28, 0.2),
		Vector2.new(0.36, 0.3),
		Vector2.new(0.46, 0.36),
		Vector2.new(0.46, 0.46),
		Vector2.new(0.36, 0.5),
		Vector2.new(0.001, 0.46),
	}, 32)
end, { vertexColors = true })

-- Toadstool: a curved stem and a domed cap with pale spots. `Hue` (0..1) picks the cap colour.
Geo.register("Mushroom", function(b, params)
	local hue = if type(params.Hue) == "number" then params.Hue else 0.55
	local cap = Color3.fromHSV(hue, 0.55, 0.85)
	b.colorAt = function(p: Vector3): Color3
		if p.Y < 0.12 then
			return rgb(236, 226, 206)
		end
		local n = Tex.noise(p.X * 5 + 3, p.Z * 5 + p.Y * 3, 9, 2)
		return if n > 0.68 then rgb(250, 246, 236) else cap
	end
	local stem = {}
	for i = 0, 6 do
		local t = i / 6
		table.insert(stem, Vector3.new(0.06 * math.sin(t * 2.5), -0.5 + t * 0.62, 0))
	end
	b:tube(stem, { 0.12, 0.1, 0.085, 0.08, 0.08, 0.085, 0.09 }, 10)
	b:lathe({
		Vector2.new(0.001, 0.06),
		Vector2.new(0.38, 0.08),
		Vector2.new(0.5, 0.12),
		Vector2.new(0.46, 0.26),
		Vector2.new(0.3, 0.42),
		Vector2.new(0.001, 0.5),
	}, 20, CFrame.new(0.06 * math.sin(2.5), 0, 0))
end, { vertexColors = true })

-- Paper lantern: a ribbed, rounded body with a cap and foot (glows with the spot's Neon material).
Geo.register("Lantern", function(b)
	local profile = {}
	for i = 0, 10 do
		local y = -0.5 + i / 10
		table.insert(profile, Vector2.new(0.001 + 0.5 * math.sin(math.pi * (i / 10)) ^ 0.7, y))
	end
	b:lathe(profile, 12, nil, function(angle: number): number
		return 1 - 0.06 * math.abs(math.cos(angle * 6))
	end)
end)

-- Twisted tree: a leaning trunk and a lumpy, two-tone canopy built from overlapping blobs.
Geo.register("Tree", function(b, params)
	local seed = if type(params.Seed) == "number" then params.Seed else 1
	local leaf = Color3.fromHSV(({ 0.46, 0.5, 0.53 })[(seed - 1) % 3 + 1], 0.45, 0.42)
	b.colorAt = function(p: Vector3): Color3
		if p.Y < 0.05 and math.abs(p.X) < 0.2 and math.abs(p.Z) < 0.2 then
			return rgb(72, 56, 52)
		end
		local n = Tex.noise(p.X * 4 + seed, p.Y * 4 + p.Z * 2, 5, 3)
		-- Tops catch the moonlight.
		return leaf:Lerp(rgb(132, 186, 170), math.clamp((p.Y - 0.15) * 1.4 + (n - 0.5) * 0.5, 0, 0.6))
	end
	local trunk = {}
	for i = 0, 8 do
		local t = i / 8
		table.insert(trunk, Vector3.new(math.sin(t * 2 + seed) * 0.06, -0.5 + t * 0.6, math.cos(t * 3 + seed) * 0.04))
	end
	b:tube(trunk, { 0.1, 0.075, 0.06, 0.055, 0.05, 0.05, 0.045, 0.04, 0.03 }, 8)
	local rng = Random.new(seed)
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local r = if i == 7 then 0 else rng:NextNumber(0.14, 0.26)
		local centre = Vector3.new(math.cos(a) * r, 0.18 + rng:NextNumber(0, 0.16) + (if i == 7 then 0.14 else 0), math.sin(a) * r)
		b:sphere(rng:NextNumber(0.16, 0.24), 6, 10, CFrame.new(centre))
	end
end, { vertexColors = true })

-- Boulder: a noisy, faceted lump with moss on the top faces.
Geo.register("Stone", function(b, params)
	local seed = if type(params.Seed) == "number" then params.Seed else 1
	b.flat = true
	b.colorAt = function(p: Vector3): Color3
		local n = Tex.noise(p.X * 3 + seed, p.Z * 3, 4, 2)
		return if p.Y > 0.18 + n * 0.2 then MOSS:Lerp(rgb(120, 160, 112), n) else STONE:Lerp(STONE_DARK, n)
	end
	b:sphere(0.5, 6, 9)
	b:displace(function(p: Vector3): Vector3
		local n = Tex.noise(p.X * 2 + seed, p.Y * 2 + p.Z * 2, 3, 2)
		return p * (0.4 * n - 0.2)
	end)
end, { vertexColors = true })

-- Fern: arching tapered fronds in a ring.
Geo.register("Fern", function(b)
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local path = {}
		for k = 0, 6 do
			local t = k / 6
			local reach = 0.48 * t
			table.insert(path, Vector3.new(math.cos(a) * reach, -0.5 + math.sin(t * 2.4) * 0.8, math.sin(a) * reach))
		end
		b:tube(path, { 0.05, 0.06, 0.06, 0.05, 0.04, 0.025, 0.01 }, 5)
	end
end)

-- Dresses the grove, then adds fireflies drifting over it. Returns how many props were dressed.
function Grove.dress(root: Instance): number
	local count = Geo.dress(root)
	local field = Instance.new("Part")
	field.Name = "Fireflies"
	field.Anchored, field.CanCollide, field.CanQuery, field.CanTouch = true, false, false, false
	field.Transparency = 1
	field.Size = Vector3.new(60, 6, 60)
	field.CFrame = CFrame.new(0, 5, 0)
	local flies = Instance.new("ParticleEmitter")
	flies.Shape = Enum.ParticleEmitterShape.Box
	flies.Rate = 14
	flies.Lifetime = NumberRange.new(4, 7)
	flies.Speed = NumberRange.new(0.3, 0.8)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.28),
		NumberSequenceKeypoint.new(0.8, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	flies.Color = ColorSequence.new(rgb(220, 255, 170), rgb(150, 240, 220))
	flies.LightEmission = 1
	flies.Brightness = 3
	flies.RotSpeed = NumberRange.new(-40, 40)
	Tex.apply(flies, "glow")
	flies.Parent = field
	field.Parent = workspace
	return count
end

return Grove
