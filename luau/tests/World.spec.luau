-- World building and interface logic: Scene, Scatter, GeoShapes, Camera, Fx.ambience and UI layout.
-- Runs in Studio (K.test) and headless in CI. The parts that need engine stand-ins follow `t.fixtures`.
return function(t: any)
	local Kit = game:GetService("ReplicatedStorage").Kit
	local Scene = t.require(Kit.Scene)
	local Scatter = t.require(Kit.Scatter)
	local Geo = t.require(Kit.Geo)
	local GeoShapes = t.require(Kit.GeoShapes)
	local Camera = t.require(Kit.Camera)
	local Fx = t.require(Kit.Fx)
	local UI = t.require(Kit.UI)
	local Scheduler = t.require(Kit.Scheduler)

	local function near(a: number, b: number, eps: number?): boolean
		return math.abs(a - b) <= (eps or 1e-6)
	end

	t.test("Geo.decode and Geo.unpack read a Blender export exactly", function()
		local bytes = Geo.decode("AQID")
		t.eq(buffer.len(bytes), 3)
		t.eq(buffer.readu8(bytes, 2), 3)
		t.eq(buffer.len(Geo.decode("AQ==")), 1)
		-- One triangle: x positions 0, 2, 0 with unit 0.5, colour (10, 20, 30), up normals.
		local part = {
			verts = 3,
			tris = 1,
			pos = "AAAAAAAABAAAAAAAAAAAAAQA",
			nrm = "AH8AAH8AAH8A",
			col = "ChQeChQeChQe",
			idx = "AAABAAIA",
		}
		local positions, normals, colors, indices = Geo.unpack(part, 0.5)
		t.eq(positions[2].X, 2)
		t.eq(positions[3].Z, 2)
		t.eq(normals[1].Y, 1)
		t.ok(math.abs(colors[1].G - 20 / 255) < 1e-6)
		t.eq(indices[3], 3)
	end)

	t.test("Scene.validate accepts a real look and names what is wrong with a bad one", function()
		t.ok(Scene.validate({
			lighting = { ClockTime = 14, Ambient = Color3.new(0, 0, 0), GlobalShadows = true },
			atmosphere = { Density = 0.3 },
			sky = false,
			bloom = { Intensity = 1, Size = 20, Threshold = 2 },
		}))
		local function reason(look: any): string
			local ok, why = Scene.validate(look)
			t.eq(ok, false)
			return why
		end
		t.ok(string.find(reason({ lighting = { Technology = "Future" } }), "choose it in Studio", 1, true))
		t.ok(string.find(reason({ lighting = { ClockTime = 25 } }), "lighting.ClockTime", 1, true))
		t.ok(string.find(reason({ lighting = { Ambient = "#ffffff" } }), "Color3", 1, true))
		t.ok(string.find(reason({ atmosphere = { Fog = 1 } }), "not a look property", 1, true))
		t.ok(string.find(reason({ weather = {} }), "unknown look section", 1, true))
		t.ok(string.find(reason({ lighting = false }), "must be a table", 1, true))
		t.ok(string.find(reason({ sky = { SkyboxUp = "nope" } }), "rbxassetid", 1, true))
	end)

	t.test("zones weigh 1 inside, fade across the edge and reach 0 beyond it", function()
		local box = { center = Vector3.new(10, 0, 0), size = Vector3.new(10, 10, 10) }
		t.eq(Scene.zoneWeight(box, Vector3.new(12, 1, 1), 8), 1)
		t.ok(near(Scene.zoneWeight(box, Vector3.new(19, 0, 0), 8), 0.5))
		t.eq(Scene.zoneWeight(box, Vector3.new(30, 0, 0), 8), 0)
		local ball = { center = Vector3.zero, radius = 5 }
		t.ok(near(Scene.zoneWeight(ball, Vector3.new(0, 7, 0), 4), 0.5))
		t.eq(Scene.zoneWeight(ball, Vector3.new(0, 6, 0), 0), 0, "a hard edge")
	end)

	t.test("mix blends numbers and colours in layer order and takes the short way around the clock", function()
		local layers: { any } = {}
		table.insert(layers, { values = { ["lighting.Brightness"] = 0, ["lighting.ClockTime"] = 1 }, weight = 0.5 })
		table.insert(layers, { values = { ["atmosphere.Density"] = 0.4 }, weight = 0.25 })
		table.insert(layers, { values = { ["lighting.Brightness"] = 10 }, weight = 0 })
		local out = Scene.mix({ ["lighting.Brightness"] = 2, ["lighting.ClockTime"] = 23 }, layers)
		t.ok(near(out["lighting.Brightness"], 1))
		t.ok(near(out["lighting.ClockTime"], 0), "midnight, not noon")
		t.eq(out["atmosphere.Density"], 0.4, "no base value to blend from")
		local warm = Scene.mix({ ["lighting.Ambient"] = Color3.new(0, 0, 0) }, {
			{ values = { ["lighting.Ambient"] = Color3.new(1, 0, 0) }, weight = 0.5 },
		})
		t.ok(near(warm["lighting.Ambient"].R, 0.5))
	end)

	local hills = { seed = 7, scale = 120, amplitude = 30, base = 20 }

	t.test("the landscape is seeded, bounded and honours terraces and plateaus", function()
		local sum, same = 0, 0
		for i = 1, 80 do
			local x, z = i * 37.3, i * -19.1
			local h = Scene.height(x, z, hills)
			t.eq(h, Scene.height(x, z, hills), "deterministic")
			t.ok(h >= -10 and h <= 50, "stays within amplitude of base: " .. h)
			sum += h
			if h == Scene.height(x, z, { seed = 8, scale = 120, amplitude = 30, base = 20 }) then
				same += 1
			end
		end
		t.ok(same < 5, "a different seed is a different world")
		t.ok(math.abs(sum / 80 - 20) < 15, "centred on base")
		local stepped = { seed = 7, scale = 120, amplitude = 30, terrace = 5 }
		t.eq(Scene.height(33, 91, stepped) % 5, 0)
		local camp = {
			seed = 7,
			scale = 120,
			amplitude = 30,
			plateaus = { { x = 100, z = 50, radius = 20, height = 12 } },
		}
		t.eq(Scene.height(105, 55, camp), 12, "flat inside")
		t.ok(Scene.slope(function(x, z)
			return Scene.height(x, z, camp)
		end, 100, 50) < 1e-6, "no slope on a plateau")
		t.ok(
			near(
				Scene.slope(function(x)
					return x
				end, 0, 0),
				45
			),
			"a 1:1 ramp is 45 degrees"
		)
	end)

	t.test("biomes match in list order on height and slope, with chance and a fallback", function()
		local biomes: { any } = {}
		table.insert(biomes, { material = "Rock", minSlope = 40 })
		table.insert(biomes, { material = "Sand", maxHeight = 5 })
		table.insert(biomes, { material = "Snow", minHeight = 60, chance = 0.5 })
		table.insert(biomes, { material = "Grass" })
		t.eq(Scene.biomeAt(biomes, 3, 50, 0.5), "Rock", "cliffs beat beaches")
		t.eq(Scene.biomeAt(biomes, 3, 5, 0.5), "Sand")
		t.eq(Scene.biomeAt(biomes, 70, 5, 0.4), "Snow")
		t.eq(Scene.biomeAt(biomes, 70, 5, 0.9), "Grass", "patchy cover")
		t.eq(Scene.biomeAt(biomes, 6, 5, 0.5, -2), "Sand", "dither moves the bound")
		t.eq(Scene.biomeAt({ { material = "Mud", maxHeight = 0 } }, 9, 0, 0), "Mud", "nothing matched: the last one")
	end)

	t.test("terrain chunks tile the region on the voxel grid", function()
		local chunks = Scene.chunks(Vector3.new(-30, -6, -10), Vector3.new(50, 41, 10), 32)
		local area = 0
		for _, chunk in chunks do
			t.eq(chunk.min.X % 4, 0)
			t.eq(chunk.max.Z % 4, 0)
			t.eq(chunk.min.Y, -8, "rounded out")
			t.eq(chunk.max.Y, 44)
			t.ok(chunk.max.X - chunk.min.X <= 32)
			area += (chunk.max.X - chunk.min.X) * (chunk.max.Z - chunk.min.Z)
		end
		t.eq(area, 84 * 24, "covers the aligned region once")
	end)

	t.test("voxels fill to the height, paint the surface, keep rock under it and flood below the water", function()
		local flat = { seed = 1, scale = 100, amplitude = 0, base = 10 }
		local chunk = { min = Vector3.new(0, 0, 0), max = Vector3.new(8, 24, 4) }
		local materials, occupancy = Scene.voxels(chunk, {
			noise = flat,
			biomes = { { material = Enum.Material.Grass } },
			under = Enum.Material.Rock,
			surface = 8,
			water = 18,
		})
		t.eq(#materials, 2)
		t.eq(#materials[1], 6)
		t.eq(#materials[1][1], 1)
		t.eq(materials[1][1][1], Enum.Material.Rock, "deep: under material")
		t.eq(materials[1][2][1], Enum.Material.Grass, "4..8 sits within `surface` of the top")
		t.eq(occupancy[1][3][1], 0.5, "the top cell holds half: 8..12 filled to 10")
		t.eq(materials[1][4][1], Enum.Material.Water, "air under the water line floods")
		t.eq(occupancy[1][4][1], 1)
		t.eq(materials[1][6][1], Enum.Material.Air)
		t.eq(occupancy[1][6][1], 0)
	end)

	t.test("repaint changes the surface only and leaves air, water and depth alone", function()
		local air, water, rock = Enum.Material.Air, Enum.Material.Water, Enum.Material.Rock
		local materials = { { { rock }, { rock }, { rock }, { air } }, { { rock }, { rock }, { water }, { air } } }
		local occupancy = { { { 1 }, { 1 }, { 1 }, { 0 } }, { { 1 }, { 1 }, { 1 }, { 0 } } }
		local painted = Scene.repaint(materials, occupancy, Vector3.zero, { { material = Enum.Material.Grass } }, 4)
		t.eq(painted[1][3][1], Enum.Material.Grass, "column top")
		t.eq(painted[1][2][1], rock, "below the surface depth")
		t.eq(painted[2][3][1], water, "water stays")
		t.eq(painted[2][2][1], Enum.Material.Grass, "the seabed is that column's top")
		t.eq(materials[1][3][1], rock, "input untouched")
	end)

	t.test("Geo.rng is a seeded stream in range", function()
		local a, b, other = Geo.rng(42), Geo.rng(42), Geo.rng(43)
		local different = 0
		for _ = 1, 50 do
			local value = a()
			t.eq(value, b())
			t.ok(value >= 0 and value < 1)
			if value ~= other() then
				different += 1
			end
			local ranged = a(5, 6)
			b(5, 6)
			other()
			t.ok(ranged >= 5 and ranged <= 6)
		end
		t.ok(different > 45, "neighbouring seeds differ")
	end)

	local field = { center = Vector3.new(50, 3, -20), size = Vector3.new(200, 0, 120) }

	t.test("Poisson points keep their spacing, stay inside, fill the region and repeat by seed", function()
		local points = Scatter.points(field, 12, 5)
		t.ok(#points > 200 * 120 / (12 * 12 * 2.5), "dense: " .. #points)
		for i, p in points do
			t.ok(math.abs(p.X - 50) <= 100 and math.abs(p.Y + 20) <= 60, "inside")
			for j = i + 1, #points do
				t.ok((p - points[j]).Magnitude >= 12 - 1e-9, "spacing")
			end
		end
		local again = Scatter.points(field, 12, 5)
		t.eq(#again, #points)
		t.eq(again[#again].X, points[#points].X)
		t.ok(Scatter.points(field, 12, 6)[3].X ~= points[3].X)
		for _, p in Scatter.points({ center = Vector3.zero, radius = 40 }, 8, 2) do
			t.ok(p.Magnitude <= 40, "circle")
		end
		t.eq(#Scatter.points(field, 12, 5, 10), 10, "limit")
	end)

	t.test("density falls off from the centre and takes numbers and functions", function()
		local falloff = { inner = 10, outer = 30 }
		t.eq(Scatter.densityAt(falloff, 5, 0), 1)
		t.ok(near(Scatter.densityAt(falloff, 20, 0), 0.5))
		t.eq(Scatter.densityAt(falloff, 40, 0), 0)
		t.ok(near(Scatter.densityAt({ inner = 10, outer = 30, power = 2 }, 20, 0), 0.25))
		t.eq(Scatter.densityAt(0.3, 1, 1), 0.3)
		t.eq(Scatter.densityAt(nil, 1, 1), 1)
		t.eq(
			Scatter.densityAt(function(x: number)
				return x / 10
			end, 5, 0),
			0.5
		)
	end)

	t.test("plan rejects steep, avoided and wrong-ground points without shifting the rest", function()
		local base = { seed = 3, region = field, spacing = 10 }
		local flat = Scatter.plan(base)
		t.ok(#flat > 50)
		t.eq(flat[1].position.Y, 3, "default ground is the region's height")
		t.eq(flat[1].normal, Vector3.yAxis)

		local steep = Vector3.new(0.8, 0.6, 0)
		local sloped = Scatter.plan({
			seed = 3,
			region = field,
			spacing = 10,
			slopeMax = 30,
			sample = function(x, z)
				return { position = Vector3.new(x, 0, z), normal = if x > 50 then steep else Vector3.yAxis }
			end,
		})
		t.ok(#sloped > 0 and #sloped < #flat)
		for _, placement in sloped do
			t.ok(placement.position.X <= 50, "steep side empty")
		end

		local keepOut = { position = Vector3.new(50, 0, -20), radius = 40 }
		local avoided = Scatter.plan({ seed = 3, region = field, spacing = 10, avoid = { keepOut } })
		t.ok(#avoided < #flat)
		local kept: { [number]: boolean } = {}
		for _, placement in flat do
			kept[placement.position.X] = true
			local d = Vector2.new(placement.position.X - 50, placement.position.Z + 20).Magnitude
			if d >= 40 then
				kept[placement.position.X] = false
			end
		end
		for _, placement in avoided do
			t.ok(kept[placement.position.X] == false, "the survivors are the same points as before")
		end

		local water = Scatter.plan({
			seed = 3,
			region = field,
			spacing = 10,
			sample = function(x, z)
				local material = if x > 50 then Enum.Material.Water else Enum.Material.Grass
				return { position = Vector3.new(x, 0, z), normal = Vector3.yAxis, material = material }
			end,
		})
		for _, placement in water do
			t.ok(placement.position.X <= 50, "nothing grows on water")
		end
		local onlyRock = Scatter.plan({
			seed = 3,
			region = field,
			spacing = 10,
			materials = { Enum.Material.Rock },
			sample = function(x, z)
				return { position = Vector3.new(x, 0, z), normal = Vector3.yAxis, material = Enum.Material.Grass }
			end,
		})
		t.eq(#onlyRock, 0)
		t.eq(#Scatter.plan({ seed = 3, region = field, spacing = 10, count = 7 }), 7)
		t.eq(#Scatter.plan({
			seed = 3,
			region = field,
			spacing = 10,
			sample = function()
				return nil
			end,
		}), 0, "a raycast miss places nothing")
	end)

	t.test("plan jitters scale, yaw, lean and variant, and aligns to the ground on request", function()
		local plan = Scatter.plan({
			seed = 9,
			region = field,
			spacing = 15,
			scale = { 0.5, 2 },
			tilt = 10,
			variants = 3,
		})
		local variants: { [number]: boolean } = {}
		local lowest, highest = math.huge, -math.huge
		for _, placement in plan do
			t.ok(placement.scale >= 0.5 and placement.scale <= 2)
			lowest, highest = math.min(lowest, placement.scale), math.max(highest, placement.scale)
			variants[placement.variant] = true
			t.ok(placement.cframe.UpVector.Y >= math.cos(math.rad(15)), "lean stays small")
			t.ok((placement.cframe.Position - placement.position).Magnitude < 1e-9)
		end
		t.ok(highest - lowest > 0.8, "scale varies")
		t.ok(variants[1] and variants[2] and variants[3], "every variant turns up")

		local normal = Vector3.new(0.6, 0.8, 0)
		local leaning = Scatter.plan({
			seed = 9,
			region = field,
			spacing = 40,
			align = 1,
			sample = function(x, z)
				return { position = Vector3.new(x, 0, z), normal = normal }
			end,
		})
		t.ok(#leaning > 0)
		t.ok((leaning[1].cframe.UpVector - normal).Magnitude < 1e-6, "follows the normal")
	end)

	t.test("every built-in shape is registered with a size", function()
		t.eq(#(function()
			local names = {}
			for name, build in GeoShapes.Builders do
				t.ok(type(build) == "function")
				t.ok(GeoShapes.Sizes[name], name .. " has a size")
				table.insert(names, name)
			end
			return names
		end)(), 10)
	end)

	t.test("GeoShapes.spot stands on the ground with its attributes", function()
		local spot = GeoShapes.spot(
			"crate",
			CFrame.new(1, 2, 3),
			{ seed = 4, scale = 2, attributes = { wood = Color3.new(1, 0, 0) } }
		)
		t.eq(spot:GetAttribute("GeoShape"), "crate")
		t.eq(spot:GetAttribute("Seed"), 4)
		t.eq(spot:GetAttribute("wood"), Color3.new(1, 0, 0))
		t.eq(spot.Size, GeoShapes.Sizes.crate * 2)
		t.ok(near(spot.Position.Y - spot.Size.Y / 2, 2), "base on the ground")
		t.eq(spot.CanCollide, true)
		t.eq(GeoShapes.spot("tree", CFrame.identity).CanCollide, false, "walk through foliage")
		t.ok(GeoShapes.spot("lantern", CFrame.identity):FindFirstChildOfClass("PointLight"), "lanterns light up")
		t.fails(function()
			GeoShapes.spot("castle", CFrame.identity)
		end, "unknown shape")
	end)

	t.test("camera rigs frame their target", function()
		local behind = Camera.followFrame(Vector3.new(0, 5, 0), 0, 0, 10)
		t.ok((behind.Position - Vector3.new(0, 5, 10)).Magnitude < 1e-6, "yaw 0 sits behind on +Z")
		t.ok((behind.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-6)
		local above = Camera.followFrame(Vector3.zero, 0, 30, 10)
		t.ok(near(above.Position.Y, 5, 1e-6), "pitch lifts the camera")
		t.ok(above.LookVector.Y < 0, "and looks down")
		local top = Camera.topDownFrame(Vector3.zero, 50, 0)
		t.ok(near(top.Position.Y, 50, 1e-6) and near(top.LookVector.Y, -1, 1e-6), "straight down")
		local shoulder = Camera.shoulderFrame(Vector3.zero, 0, 0, Vector3.new(2, 2, 8))
		t.ok((shoulder.Position - Vector3.new(2, 2, 8)).Magnitude < 1e-6)
		local turned = Camera.shoulderFrame(Vector3.zero, 90, 0, Vector3.new(0, 0, 8))
		t.ok(near(turned.Position.X, 8, 1e-6), "yaw swings it around")
	end)

	t.test("camera clipping pulls in front of walls, never past the focus", function()
		local wanted = Vector3.new(0, 0, 20)
		t.eq(Camera.clip(Vector3.zero, wanted, nil), wanted)
		t.ok(near(Camera.clip(Vector3.zero, wanted, 10).Z, 9.4))
		t.ok(near(Camera.clip(Vector3.zero, wanted, 0.1).Z, 0.6), "a wall at the focus keeps a margin")
		t.eq(Camera.clip(Vector3.zero, wanted, 500).Z, 20)
	end)

	t.test("camera paths sample position and fov on Motion curves and refuse bad keys", function()
		local a, b = CFrame.new(0, 0, 0), CFrame.new(10, 0, 0)
		local keys: any = { { t = 0, at = a, fov = 70 }, { t = 2, at = b, fov = 30 } }
		local frame, fov = Camera.pathFrame(keys, 1)
		t.ok(near(frame.Position.X, 5, 1e-6))
		t.ok(near(fov, 50, 1e-6))
		local eased = Camera.pathFrame({ keys[1], { t = 2, at = b, ease = "expoOut" } } :: any, 1)
		t.ok(eased.Position.X > 9, "eases")
		local _, none = Camera.pathFrame({ { t = 0, at = a } }, 0)
		t.eq(none, nil)
		t.fails(function()
			Camera.checkPath({})
		end, "at least one key")
		t.fails(function()
			Camera.checkPath({ { t = 2, at = a }, { t = 1, at = b } })
		end, "after the previous key")
		t.fails(function()
			Camera.checkPath({ { t = 0, at = Vector3.zero } })
		end, "CFrame")
	end)

	t.test("ambience rates follow density and quality, within a budget", function()
		local layer = {
			texture = "dust",
			density = 1,
			budget = 100,
			lifetime = { 4, 6 },
			size = 1,
			transparency = 0,
			color = "core",
		}
		t.ok(near(Fx.ambienceRate(layer, 50000, "High"), 10), "50 alive over a 5 s life")
		t.ok(near(Fx.ambienceRate(layer, 500000, "High"), 20), "capped by the budget")
		t.ok(near(Fx.ambienceRate(layer, 50000, "Low"), 3.5))
		t.ok(near(Fx.ambienceRate(layer, 50000, "High", 2), 20), "a density multiplier")
		layer.minQuality = "High"
		t.eq(Fx.ambienceRate(layer, 50000, "Medium"), 0)
		for _, name in { "dust", "fog", "fireflies", "embers" } do
			t.ok(Fx.Ambience[name], name .. " preset")
		end
	end)

	t.test("UI layout helpers", function()
		local position, point = UI.anchorFor("topRight", 10)
		t.eq(point, Vector2.new(1, 0))
		t.eq(position.X.Scale, 1)
		t.eq(position.X.Offset, -10)
		t.eq(position.Y.Offset, 10)
		local centre = UI.anchorFor("center", 10)
		t.eq(centre.X.Offset, 0)
		t.fails(function()
			UI.anchorFor("middle")
		end, "unknown corner")
		t.eq(UI.viewScale(Vector2.new(1280, 720)), 1)
		t.eq(UI.viewScale(Vector2.new(640, 720)), 0.6, "phones clamp up to the floor")
		t.eq(UI.viewScale(Vector2.new(3840, 2160)), 1.5, "and 4K to the ceiling")
		t.eq(UI.barFill(5, 10), 0.5)
		t.eq(UI.barFill(20, 10), 1)
		t.eq(UI.barFill(-1, 10), 0)
		t.eq(UI.barFill(1, 0), 0)
		local cell = UI.gridCell(4, 90, 8)
		t.eq(cell.X.Scale, 0.25)
		t.eq(cell.X.Offset, -6, "four cells and three gaps fill the row")
		t.eq(cell.Y.Offset, 90)
	end)

	if not t.fixtures then
		return
	end

	local services = t.fixtures.services
	local world: any = workspace -- the stand-in lets tests swap the camera
	local runtime = t.fixtures.runtime

	t.test("Scene.apply sets Lighting, reuses objects, owns its effects and removes on false", function()
		local lighting = services.Lighting
		local authored = Instance.new("ColorCorrectionEffect")
		authored.Name = "GameGrade"
		authored.Parent = lighting
		local sky = Instance.new("Sky")
		sky.Parent = lighting
		Scene.apply({
			lighting = { ClockTime = 6, Ambient = Color3.new(0, 0, 1) },
			atmosphere = { Density = 0.4 },
			sky = { StarCount = 100 },
			colorCorrection = { Saturation = -0.2 },
			bloom = { Intensity = 1 },
			sunRays = { Spread = 0.3 },
		})
		t.eq(lighting.ClockTime, 6)
		t.eq(lighting:FindFirstChildOfClass("Atmosphere").Density, 0.4)
		t.eq(sky.StarCount, 100, "an existing Sky is reused")
		t.eq(lighting:FindFirstChild("MoonbrickGrade").Saturation, -0.2)
		t.eq(authored.Saturation, nil, "a game's own effect is left alone")
		Scene.apply({ bloom = { Intensity = 2 } })
		t.eq(lighting:FindFirstChild("MoonbrickBloom").Intensity, 2)
		local count = 0
		for _, child in lighting:GetChildren() do
			if child.ClassName == "BloomEffect" then
				count += 1
			end
		end
		t.eq(count, 1, "applying again updates, it doesn't stack")
		Scene.apply({ atmosphere = false, sunRays = false })
		t.eq(lighting:FindFirstChildOfClass("Atmosphere"), nil)
		t.eq(lighting:FindFirstChild("MoonbrickSunRays"), nil)
		t.fails(function()
			Scene.apply({ lighting = { Technology = "Future" } } :: any)
		end, "choose it in Studio")
		lighting:ClearAllChildren()
	end)

	t.test("zones do nothing until followed, blend with the camera, and restore the look", function()
		local lighting = services.Lighting
		local camera: any = Instance.new("Folder")
		camera.CFrame = CFrame.new(100, 0, 0)
		world.CurrentCamera = camera
		Scene.apply({ lighting = { Brightness = 2 } })
		local remove = Scene.zone("Cave", { center = Vector3.zero, radius = 10 }, {
			lighting = { Brightness = 0 },
			atmosphere = { Density = 0.5 },
		}, { fade = 1, edge = 0 })
		Scheduler.advance(0.1)
		t.eq(lighting.Brightness, 2, "registering a zone changes nothing")
		t.fails(function()
			Scene.zone("Bad", { center = Vector3.zero, radius = 1 }, { sky = { StarCount = 1 } })
		end, "can't change the Sky")

		local stop = Scene.follow()
		Scheduler.advance(0.5)
		t.eq(lighting.Brightness, 2, "outside the zone")
		camera.CFrame = CFrame.new(0, 0, 0)
		Scheduler.advance(0.5)
		t.ok(near(lighting.Brightness, 1), "half way through the fade")
		Scheduler.advance(0.6)
		t.eq(lighting.Brightness, 0, "fully in")
		t.eq(lighting:FindFirstChildOfClass("Atmosphere").Density, 0.5)
		camera.CFrame = CFrame.new(100, 0, 0)
		Scheduler.advance(0.5)
		t.ok(near(lighting.Brightness, 1), "fading back out")
		stop()
		t.eq(lighting.Brightness, 2, "stopping restores the look")
		remove()
		Scheduler.advance(0)
		lighting:ClearAllChildren()
		world.CurrentCamera = nil
	end)

	local function built(shape: string, seed: number): any
		local b = Geo.new()
		GeoShapes.Builders[shape](b, { Seed = seed })
		return b
	end

	local function signature(b: any): string
		local parts = {}
		local mesh = b.mesh
		for _, id in mesh:GetVertices() do
			local p = mesh:GetPosition(id)
			table.insert(parts, string.format("%.4f,%.4f,%.4f", p.X, p.Y, p.Z))
		end
		return table.concat(parts, ";")
	end

	t.test("built-in shapes face outward, stay low-poly and repeat by seed", function()
		for name in GeoShapes.Builders do
			local b = built(name, 2)
			t.ok(b:volume() > 0, name .. " is inside-out")
			t.ok(b:count() > 8 and b:count() < 1500, name .. " triangles: " .. b:count())
			t.eq(signature(b), signature(built(name, 2)), name .. " is not deterministic")
		end
		for _, name in { "rock", "tree", "pine", "bush", "crystal", "mushroom", "fence", "crate" } do
			t.ok(signature(built(name, 2)) ~= signature(built(name, 3)), name .. " ignores its seed")
		end
	end)

	t.test("spot sizes match each mesh, so nothing stretches out of proportion", function()
		local bad = {}
		for name in GeoShapes.Builders do
			local b = built(name, 1)
			local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
			for _, id in b.mesh:GetVertices() do
				local p = b.mesh:GetPosition(id)
				lo, hi = lo:Min(p), hi:Max(p)
			end
			local mesh, size = hi - lo, GeoShapes.Sizes[name]
			local wide = (size.X / size.Y) / (mesh.X / mesh.Y)
			local deep = (size.Z / size.Y) / (mesh.Z / mesh.Y)
			if wide < 0.75 or wide > 1.33 or deep < 0.75 or deep > 1.33 then
				table.insert(bad, string.format("%s mesh %.2f,%.2f,%.2f", name, mesh.X, mesh.Y, mesh.Z))
			end
		end
		t.eq(table.concat(bad, "; "), "")
	end)

	t.test("a scattered shape dresses end to end, and Scatter.place clones models and calls functions", function()
		GeoShapes.register()
		local root = Instance.new("Folder")
		local plan = Scatter.plan({ seed = 1, region = field, spacing = 40, count = 6, variants = 2 })
		local folder = Scatter.place(plan, { "barrel", "crate" }, { parent = root, name = "Props" })
		t.eq(#folder:GetChildren(), 6)
		t.eq(Geo.dress(root), 6)
		local spot = folder:GetChildren()[1]
		t.ok(spot:FindFirstChildWhichIsA("MeshPart") ~= nil, "mesh child")
		t.eq(spot.Transparency, 1)

		local template = Instance.new("Part")
		template.Size = Vector3.new(2, 4, 2)
		local parts = Scatter.place({ plan[1] }, template, { parent = root })
		t.eq(#parts:GetChildren(), 1)
		t.ok(near(parts:GetChildren()[1].Position.Y - plan[1].position.Y, 2), "parts stand on the ground")
		local seen = {}
		Scatter.place(plan, function(placement)
			table.insert(seen, placement.index)
			return nil
		end, { parent = root })
		t.eq(#seen, 6)
		root:Destroy()
	end)

	t.test("Camera.path plays on the Scheduler, freezes with it and hands the camera back", function()
		local camera: any = Instance.new("Folder")
		camera.CFrame = CFrame.new()
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		world.CurrentCamera = camera
		runtime.client = true
		local done = false
		Camera.path({
			{ t = 0, at = CFrame.new(0, 0, 0), fov = 40 },
			{ t = 1, at = CFrame.new(10, 0, 0), fov = 60 },
		}, {
			onDone = function()
				done = true
			end,
		})
		t.ok(Camera.active())
		local run = services.RunService
		Scheduler.advance(0.5)
		run.bound.MoonbrickCameraRig(1 / 60)
		t.eq(camera.CameraType, Enum.CameraType.Scriptable)
		t.ok(near(camera.CFrame.Position.X, 5, 1e-6))
		t.eq(camera.FieldOfView, 50)
		local scale = Scheduler.getTimeScale()
		Scheduler.setTimeScale(0)
		run.bound.MoonbrickCameraRig(1)
		t.ok(near(camera.CFrame.Position.X, 5, 1e-6), "a global freeze holds the cutscene")
		Scheduler.setTimeScale(scale)
		Scheduler.advance(0.6)
		t.ok(done, "onDone ran")
		t.ok(not Camera.active())
		t.eq(camera.CameraType, Enum.CameraType.Custom, "camera handed back")
		t.eq(camera.FieldOfView, 70)
		runtime.client = false
		world.CurrentCamera = nil
	end)

	t.test("ambience outlives the effect watchdog, obeys freezes and quality, and cleans up", function()
		local live = Fx.live()
		local stop = Fx.ambience({ center = Vector3.zero, size = Vector3.new(80, 20, 80) }, "fog", { density = 2 })
		local holder = workspace:FindFirstChild("Ambience_fog")
		t.ok(holder ~= nil, "a holder part")
		t.eq(holder.Size, Vector3.new(80, 20, 80))
		t.eq(Fx.live(), live, "ambience isn't a timed effect")
		local emitters = holder:GetChildren()
		t.eq(#emitters, 2)
		Fx.setQuality("High")
		t.ok(emitters[2].Enabled, "second layer at High")
		local rate = emitters[1].Rate
		Fx.setQuality("Low")
		t.ok(emitters[1].Rate < rate, "quality scales it live")
		t.eq(emitters[2].Enabled, false, "High-only layer drops out")
		Fx.setQuality(nil)
		task.wait(200)
		t.ok(holder.Parent ~= nil, "still there after 200 s")
		Fx.setGlobalTimeScale(0)
		t.eq(emitters[1].TimeScale, 0)
		Fx.setGlobalTimeScale(1)
		t.eq(emitters[1].TimeScale, 1)
		stop()
		t.eq(emitters[1].Enabled, false)
		t.ok(holder.Parent ~= nil, "live particles finish first")
		task.wait(30)
		t.eq(holder.Parent, nil)
		stop() -- twice is safe
		t.fails(function()
			Fx.ambience({ center = Vector3.zero, size = Vector3.one }, "snow")
		end, "unknown preset")
	end)

	t.test("UI primitives assemble, select, update and close", function()
		local playerGui = Instance.new("Folder")
		local previous = services.Players.LocalPlayer
		services.Players.LocalPlayer = {
			WaitForChild = function()
				return playerGui
			end,
		}
		local hud = UI.hud("Test")
		t.eq(UI.hud("Test"), hud, "one per screen")
		local pad = hud:FindFirstChildOfClass("UIPadding")
		t.eq(pad.PaddingTop.Offset, 36, "clear of the top bar")
		local corner = UI.anchor({ parent = hud, corner = "bottomLeft" })
		t.eq(corner.AnchorPoint, Vector2.new(0, 1))
		local bar = UI.bar({ parent = corner, value = 5, max = 10, label = true })
		t.eq(bar.fill.Size.X.Scale, 0.5)
		t.eq(bar.frame:FindFirstChild("Text").Text, "5 / 10")
		bar.set(2)
		task.wait(0.3)
		t.eq(bar.fill.Size.X.Scale, 0.2)
		bar.set(30, 60)
		t.eq(bar.frame:FindFirstChild("Text").Text, "30 / 60")
		local scroll = UI.scroll({ parent = hud })
		t.ok(scroll:FindFirstChildOfClass("UIListLayout"))
		t.eq(scroll.AutomaticCanvasSize, Enum.AutomaticSize.Y)
		local grid = UI.grid({ parent = scroll, columns = 2, gap = 4 })
		t.eq(grid:FindFirstChildOfClass("UIGridLayout").CellSize.X.Scale, 0.5)

		local picked = {}
		local tabs = UI.tabs({
			parent = hud,
			tabs = { { id = "a", text = "One" }, { id = "b", text = "Two" } },
			onSelect = function(id)
				table.insert(picked, id)
			end,
		})
		t.eq(tabs.selected, "a")
		t.eq(tabs.pages.a.Visible, true)
		t.eq(tabs.pages.b.Visible, false)
		tabs.select("b")
		t.eq(tabs.pages.a.Visible, false)
		t.eq(tabs.pages.b.Visible, true)
		t.eq(picked[2], "b")
		t.fails(function()
			tabs.select("c")
		end, "no tab")

		local input = services.UserInputService
		local gui = services.GuiService
		input.GamepadEnabled = true
		local outside = UI.button({ parent = hud, text = "Outside" })
		gui.SelectedObject = nil
		local closed, clicked = false, false
		local modal = UI.modal({
			title = "Quit?",
			text = "Progress is saved.",
			buttons = {
				{ text = "Stay" },
				{
					text = "Leave",
					style = "danger",
					onClick = function()
						clicked = true
					end,
				},
			},
			onClose = function()
				closed = true
			end,
		})
		t.ok(gui.SelectedObject and gui.SelectedObject.Text == "Stay", "a gamepad lands on the first button")
		t.eq(modal.panel.SelectionGroup, true, "and can't wander out")
		local back = next(services.ContextActionService.bound)
		t.ok(back, "gamepad B bound")
		modal.panel:FindFirstChild("Leave", true).Activated:Fire()
		t.ok(closed and clicked, "buttons close, then act")
		t.eq(next(services.ContextActionService.bound), nil, "B released")
		t.ok(modal.frame.destroyed)
		modal.close() -- twice is safe
		input.GamepadEnabled = false
		gui.SelectedObject = nil
		t.eq(UI.focus(outside), nil, "mouse players keep their cursor")
		services.Players.LocalPlayer = previous
	end)
end
