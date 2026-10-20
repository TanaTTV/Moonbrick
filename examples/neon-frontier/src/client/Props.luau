--!strict
-- Neon Frontier props for Geo.dress: frontier shapes with a wired-up twist (neon-veined cacti, a water
-- tower with a status ring, a hoverbike). Each shape builds around the origin; the spot's size scales it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Geo = require(Kit:WaitForChild("Geo"))
local Tex = require(Kit:WaitForChild("Tex"))

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local CYAN, MAGENTA = rgb(60, 240, 255), rgb(255, 70, 190)

-- Saguaro: a ribbed trunk with two arms; thin glowing veins run up the ribs.
Geo.register("Cactus", function(b, params)
	local seed = if type(params.Seed) == "number" then params.Seed else 1
	b.colorAt = function(p: Vector3): Color3
		local angle = math.atan2(p.Z, p.X)
		local rib = math.abs(math.cos(angle * 8))
		if rib > 0.97 and (seed + math.floor(p.Y * 6)) % 3 == 0 then
			return if seed == 2 then MAGENTA else CYAN
		end
		local n = Tex.noise(p.X * 5 + seed, p.Y * 5, 4, 2)
		return rgb(58, 104, 74):Lerp(rgb(96, 140, 92), n * 0.6 + rib * 0.2)
	end
	local function ribbed(angle: number): number
		return 1 - 0.1 * math.abs(math.sin(angle * 4))
	end
	b:lathe({
		Vector2.new(0.001, -0.5),
		Vector2.new(0.16, -0.5),
		Vector2.new(0.17, 0.3),
		Vector2.new(0.14, 0.44),
		Vector2.new(0.001, 0.5),
	}, 16, nil, ribbed)
	-- Arms: an elbow out, then up.
	for k, side in { -1, 1 } do
		local base = -0.05 + 0.12 * ((seed + k) % 3)
		local path = {
			Vector3.new(0, base, 0),
			Vector3.new(side * 0.22, base + 0.02, 0),
			Vector3.new(side * 0.3, base + 0.12, 0),
			Vector3.new(side * 0.31, base + 0.3, 0),
		}
		b:tube(path, { 0.09, 0.09, 0.085, 0.07 }, 10)
	end
end, { vertexColors = true })

-- Water tower: a banded wooden tank on four legs with a conical roof and a glowing status ring.
Geo.register("WaterTower", function(b)
	b.colorAt = function(p: Vector3): Color3
		if p.Y > 0.02 and p.Y < 0.06 then
			return CYAN
		end
		if p.Y > 0.32 then
			return rgb(70, 60, 66) -- roof
		end
		if p.Y > -0.12 then
			local band = (p.Y * 20) % 1 < 0.12
			return if band then rgb(40, 38, 44) else rgb(122, 82, 58)
		end
		return rgb(52, 44, 42) -- legs
	end
	b:lathe({
		Vector2.new(0.001, -0.1),
		Vector2.new(0.42, -0.1),
		Vector2.new(0.45, 0.04),
		Vector2.new(0.42, 0.32),
		Vector2.new(0.48, 0.32),
		Vector2.new(0.001, 0.5),
	}, 24)
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		local top = corner * 0.28 + Vector3.new(0, -0.1, 0)
		local foot = corner * 0.38 + Vector3.new(0, -0.5, 0)
		b:tube({ foot, top }, 0.025, 6)
	end
	-- Cross bracing between the legs.
	b:tube({ Vector3.new(0.36, -0.42, 0.36), Vector3.new(-0.3, -0.16, 0.3) }, 0.012, 4)
	b:tube({ Vector3.new(-0.36, -0.42, -0.36), Vector3.new(0.3, -0.16, -0.3) }, 0.012, 4)
end, { vertexColors = true })

-- Barrel: staves bulge in the middle; two dark hoops.
Geo.register("Barrel", function(b)
	local profile = {}
	for i = 0, 10 do
		local y = -0.5 + i / 10
		table.insert(profile, Vector2.new(0.4 + 0.08 * math.cos(y * math.pi), y))
	end
	table.insert(profile, 1, Vector2.new(0.001, -0.5))
	table.insert(profile, Vector2.new(0.001, 0.5))
	b:lathe(profile, 18)
	b:torus(0.47, 0.025, 18, 4, CFrame.new(0, 0.28, 0))
	b:torus(0.47, 0.025, 18, 4, CFrame.new(0, -0.28, 0))
end)

-- Hoverbike: a teardrop hull with a saddle, handlebars and two glowing thruster rings (faces -Z).
Geo.register("Hoverbike", function(b)
	b.colorAt = function(p: Vector3): Color3
		if math.abs(p.Z - 0.42) < 0.06 or math.abs(p.Z + 0.36) < 0.05 then
			return MAGENTA
		end
		if p.Y > 0.12 and math.abs(p.Z) < 0.15 then
			return rgb(30, 26, 32) -- saddle
		end
		return if p.X > 0 then rgb(214, 212, 220) else rgb(190, 188, 200)
	end
	b:lathe({
		Vector2.new(0.001, -0.5),
		Vector2.new(0.16, -0.38),
		Vector2.new(0.22, -0.05),
		Vector2.new(0.2, 0.25),
		Vector2.new(0.1, 0.45),
		Vector2.new(0.001, 0.5),
	}, 14, CFrame.Angles(math.rad(-90), 0, 0))
	b:box(CFrame.new(0, 0.2, 0.05), Vector3.new(0.2, 0.08, 0.32))
	b:tube({ Vector3.new(-0.2, 0.28, -0.32), Vector3.new(0, 0.22, -0.28), Vector3.new(0.2, 0.28, -0.32) }, 0.025, 6)
	b:torus(0.17, 0.04, 16, 6, CFrame.new(0, -0.05, 0.42) * CFrame.Angles(math.rad(90), 0, 0))
	b:torus(0.15, 0.035, 16, 6, CFrame.new(0, -0.08, -0.36) * CFrame.Angles(math.rad(90), 0, 0))
end, { vertexColors = true })

-- Power pylon: an A-frame lattice with a crossarm.
Geo.register("Pylon", function(b)
	local legs = { Vector3.new(-0.45, -0.5, 0), Vector3.new(0.45, -0.5, 0) }
	local apex = Vector3.new(0, 0.5, 0)
	for _, foot in legs do
		b:tube({ foot, apex }, 0.04, 6)
	end
	for i = 1, 5 do
		local y = -0.5 + i / 6
		local half = 0.45 * (1 - (y + 0.5))
		b:tube({ Vector3.new(-half, y, 0), Vector3.new(half, y + 0.08, 0) }, 0.02, 4)
	end
	b:box(CFrame.new(0, 0.36, 0), Vector3.new(1, 0.04, 0.3))
end)

-- Satellite dish: a shallow bowl with a feed arm.
Geo.register("Dish", function(b)
	local profile = {}
	for i = 0, 8 do
		local r = i / 8 * 0.5
		table.insert(profile, Vector2.new(math.max(r, 0.001), -0.2 + r * r * 1.2))
	end
	b:lathe(profile, 24)
	-- An open bowl needs its inside too: the same surface with the profile reversed faces the other way.
	local inside = {}
	for i = #profile, 1, -1 do
		table.insert(inside, profile[i] + Vector2.new(0, 0.01))
	end
	b:lathe(inside, 24)
	b:tube({ Vector3.new(0, -0.2, 0), Vector3.new(0, 0.3, 0) }, 0.02, 6)
	b:sphere(0.05, 4, 8, CFrame.new(0, 0.32, 0))
	b:tube({ Vector3.new(0, -0.2, 0), Vector3.new(0, -0.5, 0.1) }, 0.04, 6)
end)

-- Hanging lamp: a cone shade (glows with the spot's Neon material).
Geo.register("Lamp", function(b)
	b:lathe({ Vector2.new(0.001, -0.5), Vector2.new(0.5, -0.5), Vector2.new(0.2, 0.3), Vector2.new(0.001, 0.5) }, 12)
end)

return {}
