--!strict
-- GeoShapes: ten built-in stylized props for Geo: rock, tree, pine, bush, crystal, mushroom, fence, lantern,
-- barrel, crate. Flat facets and banded colour, so a scene reads as one low-poly style at any size.
--
--   GeoShapes.register()                                       -- client, before Geo.watch(workspace)
--   Geo.watch(workspace)
--   GeoShapes.spot("pine", CFrame.new(10, 0, 4), { seed = 3, parent = workspace.World }) -- any side
--
-- A spot is an ordinary Part with `GeoShape` and `Seed` attributes, so spots made on the server (or by
-- hand in Studio) save and replicate. Attributes are the parameters: `Seed` picks the variation, and an
-- attribute named after a `GeoShapes.Palette` key with a Color3 value recolours that part (`leaf` on a
-- tree). Each distinct set of attributes is one more mesh, so use a few seeds across many spots.
local Geo = require(script.Parent.Geo)

local GeoShapes = {}

type Params = { [string]: any }
export type SpotOptions = {
	seed: number?,
	scale: number?,
	parent: Instance?,
	attributes: { [string]: any }?, -- palette overrides and shape parameters such as `Posts` on a fence
	name: string?,
}

-- Shared colours; every shape reads them here unless a spot attribute overrides one.
GeoShapes.Palette = {
	bark = Color3.fromRGB(104, 72, 52),
	leaf = Color3.fromRGB(96, 158, 76),
	needle = Color3.fromRGB(46, 104, 84),
	berry = Color3.fromRGB(216, 74, 82),
	stone = Color3.fromRGB(128, 132, 146),
	crystal = Color3.fromRGB(126, 104, 232),
	stem = Color3.fromRGB(232, 218, 190),
	cap = Color3.fromRGB(206, 62, 58),
	spots = Color3.fromRGB(252, 240, 216),
	wood = Color3.fromRGB(176, 124, 74),
	trim = Color3.fromRGB(112, 74, 46),
	iron = Color3.fromRGB(62, 62, 74),
	flame = Color3.fromRGB(255, 196, 96),
} :: { [string]: Color3 }

-- Studs for a spot at scale 1, width and depth matching each mesh's proportions.
GeoShapes.Sizes = {
	rock = Vector3.new(6.6, 4.2, 6),
	tree = Vector3.new(13, 14, 13),
	pine = Vector3.new(9, 18, 9),
	bush = Vector3.new(6, 3.6, 6),
	crystal = Vector3.new(4.6, 7, 4.6),
	mushroom = Vector3.new(4.4, 4.2, 4.4),
	fence = Vector3.new(6, 3.6, 0.7),
	lantern = Vector3.new(2.4, 3, 2.1),
	barrel = Vector3.new(3.2, 4, 3.2),
	crate = Vector3.new(4, 4, 4),
} :: { [string]: Vector3 }

-- Shapes people bump into get a solid spot; soft or overhanging ones let the player through.
local SOLID: { [string]: boolean } =
	{ rock = true, fence = true, barrel = true, crate = true, lantern = true, crystal = true }
local BANDS = 4

local function color(params: Params, key: string): Color3
	local override = params[key]
	return if typeof(override) == "Color3" then override else GeoShapes.Palette[key]
end

-- Toon shading: the colour darkens toward y0 and lightens toward y1 in a few hard bands.
local function banded(b: Geo.Builder, base: Color3, y0: number, y1: number)
	local dark, light = base:Lerp(Color3.new(0, 0, 0.1), 0.3), base:Lerp(Color3.new(1, 1, 0.9), 0.18)
	b.colorAt = function(centre: Vector3): Color3
		local alpha = math.clamp((centre.Y - y0) / math.max(y1 - y0, 1e-3), 0, 0.999)
		return dark:Lerp(light, math.floor(alpha * BANDS) / (BANDS - 1))
	end
end

-- A lumpy faceted ball. Lumps come from the seed, so the shape is the same on every client.
local function blob(b: Geo.Builder, rng: Geo.Random, cf: CFrame, rx: number, ry: number, lump: number, sides: number?)
	local rings = 4
	local profile = {}
	for i = 0, rings do
		local angle = -math.pi / 2 + i / rings * math.pi
		table.insert(profile, Vector2.new(math.max(math.cos(angle), 0.002) * rx, math.sin(angle) * ry))
	end
	local phase = rng(0, 100)
	b:lathe(profile, sides or 7, cf, function(angle, y)
		return 1 + lump * 2 * math.noise(math.cos(angle) * 1.3 + phase, y / ry * 1.3, math.sin(angle) * 1.3 + 0.5)
	end)
end

local function cone(b: Geo.Builder, y0: number, y1: number, radius: number, sides: number, cf: CFrame?, flute: number?)
	local depth = flute or 0
	b:lathe(
		{ Vector2.new(0.002, y0 + 0.02), Vector2.new(radius, y0), Vector2.new(0.002, y1) },
		sides,
		cf,
		function(angle)
			return 1 + depth * math.cos(angle * sides)
		end
	)
end

local function rock(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	b.flat = true
	banded(b, color(params, "stone"), 0, 1)
	blob(b, rng, CFrame.new(0, 0.42, 0) * CFrame.Angles(0, rng(0, 6.28), 0), 0.72, 0.46, 0.3)
	local angle = rng(0, 6.28)
	local side = CFrame.new(math.cos(angle) * 0.56, 0.2, math.sin(angle) * 0.42)
	blob(b, rng, side * CFrame.Angles(0, rng(0, 6.28), 0), 0.34, 0.22, 0.26, 6)
end

local function tree(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	b.flat = true
	banded(b, color(params, "bark"), 0, 0.62)
	b:lathe({
		Vector2.new(0.002, 0),
		Vector2.new(0.17, 0),
		Vector2.new(0.09, 0.14),
		Vector2.new(0.07, 0.5),
		Vector2.new(0.05, 0.68),
		Vector2.new(0.002, 0.7),
	}, 6)
	banded(b, color(params, "leaf"), 0.45, 1.25)
	blob(b, rng, CFrame.new(0, 0.86, 0) * CFrame.Angles(0, rng(0, 6.28), 0), 0.46, 0.36, 0.22)
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2 + rng(-0.4, 0.4)
		local at = CFrame.new(math.cos(angle) * 0.34, rng(0.62, 0.74), math.sin(angle) * 0.34)
		blob(b, rng, at * CFrame.Angles(0, rng(0, 6.28), 0), rng(0.24, 0.32), rng(0.2, 0.26), 0.24, 6)
	end
end

local function pine(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	b.flat = true
	banded(b, color(params, "bark"), 0, 0.3)
	b:lathe({ Vector2.new(0.002, 0), Vector2.new(0.06, 0), Vector2.new(0.03, 0.4), Vector2.new(0.002, 0.42) }, 6)
	local needle = color(params, "needle")
	local tiers = 3 + (math.floor(params.Seed or 1) % 2)
	for tier = 1, tiers do
		local t = (tier - 1) / tiers
		local y0 = 0.16 + t * 0.62
		local y1 = y0 + 0.58 - t * 0.2
		banded(b, needle, y0, y1)
		local turn = CFrame.Angles(0, rng(0, 6.28), 0)
		cone(b, y0, y1, 0.27 * (1 - t * 0.62), 8, turn, 0.1)
	end
end

local function bush(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	b.flat = true
	banded(b, color(params, "leaf"), 0, 1)
	blob(b, rng, CFrame.new(0, 0.42, 0) * CFrame.Angles(0, rng(0, 6.28), 0), 0.5, 0.42, 0.24)
	local lobes = 3
	local berries: { CFrame } = {}
	for i = 1, lobes do
		local angle = i / lobes * math.pi * 2 + rng(-0.5, 0.5)
		local reach = rng(0.42, 0.52)
		local at = Vector3.new(math.cos(angle) * reach, rng(0.24, 0.32), math.sin(angle) * reach)
		blob(b, rng, CFrame.new(at) * CFrame.Angles(0, rng(0, 6.28), 0), rng(0.28, 0.36), 0.26, 0.26, 6)
		table.insert(berries, CFrame.new(at + Vector3.new(math.cos(angle) * 0.3, 0.14, math.sin(angle) * 0.3)))
	end
	b.colorAt = nil
	b:setColor(color(params, "berry"))
	for _, at in berries do
		b:sphere(0.055, 3, 5, at)
	end
end

local function crystal(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	b.flat = true
	banded(b, color(params, "crystal"), 0, 1)
	local function shard(cf: CFrame, radius: number, height: number)
		b:lathe({
			Vector2.new(0.002, -0.1),
			Vector2.new(radius * 0.86, -0.1),
			Vector2.new(radius, height * 0.12),
			Vector2.new(radius * 0.82, height * 0.72),
			Vector2.new(0.002, height),
		}, 6, cf)
	end
	shard(CFrame.Angles(rng(-0.08, 0.08), rng(0, 6.28), rng(-0.08, 0.08)), 0.2, 1)
	local satellites = 3 + (math.floor(params.Seed or 1) % 2)
	for i = 1, satellites do
		local angle = i / satellites * math.pi * 2 + rng(-0.3, 0.3)
		local lean = rng(0.26, 0.5)
		local at = CFrame.new(math.cos(angle) * 0.2, 0, math.sin(angle) * 0.2)
			* CFrame.Angles(0, -angle, 0)
			* CFrame.Angles(0, 0, -lean)
		shard(at, rng(0.08, 0.13), rng(0.34, 0.62))
	end
end

local function mushroom(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	banded(b, color(params, "stem"), 0, 0.6)
	local bow = rng(-0.04, 0.04)
	b:lathe({
		Vector2.new(0.002, 0),
		Vector2.new(0.2, 0),
		Vector2.new(0.16, 0.1),
		Vector2.new(0.12, 0.34),
		Vector2.new(0.14, 0.56),
		Vector2.new(0.002, 0.58),
	}, 10, CFrame.new(bow, 0, 0))
	banded(b, color(params, "cap"), 0.46, 1)
	local rim, top = 0.5, 0.48
	local profile = {
		Vector2.new(0.002, 0.46),
		Vector2.new(rim * 0.7, 0.44),
		Vector2.new(rim, 0.5),
		Vector2.new(rim * 0.96, 0.64),
		Vector2.new(rim * 0.72, 0.82),
		Vector2.new(rim * 0.36, 0.92),
		Vector2.new(0.002, 0.46 + top),
	}
	b:lathe(profile, 14)
	b.colorAt = nil
	b:setColor(color(params, "spots"))
	local count = 5 + (math.floor(params.Seed or 1) % 3)
	for i = 1, count do
		local angle = i / count * math.pi * 2 + rng(-0.3, 0.3)
		local reach = rng(0.22, 0.4)
		-- On the dome: the higher a spot sits, the closer it is to the axis.
		local y = 0.92 - (reach / rim) ^ 2 * 0.36
		local at = CFrame.new(math.cos(angle) * reach, y, math.sin(angle) * reach)
		blob(b, rng, at, rng(0.06, 0.1), 0.03, 0.1, 6)
	end
end

local function fence(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	local posts = math.clamp(math.floor(tonumber(params.Posts) or 3), 2, 6)
	b.flat = true
	banded(b, color(params, "wood"), 0, 1)
	local width = 2 * (posts - 1) / posts + 0.3
	for i = 0, posts - 1 do
		local x = -width / 2 + 0.15 + i / (posts - 1) * (width - 0.3)
		local tilt = CFrame.Angles(0, 0, rng(-0.03, 0.03))
		local cf = CFrame.new(x, 0, 0) * tilt
		b:box(cf * CFrame.new(0, 0.42, 0), Vector3.new(0.13, 0.84, 0.13))
		cone(b, 0.84, 1, 0.1, 4, cf * CFrame.Angles(0, math.pi / 4, 0))
	end
	banded(b, color(params, "trim"), 0.1, 0.9)
	for _, y in { 0.3, 0.64 } do
		local sag = CFrame.Angles(0, 0, rng(-0.012, 0.012))
		b:box(CFrame.new(0, y, 0.08) * sag, Vector3.new(width, 0.09, 0.05))
	end
end

local function lantern(b: Geo.Builder, params: Params)
	b.flat = true
	local iron = color(params, "iron")
	b:setColor(iron)
	b:lathe({
		Vector2.new(0.002, 0),
		Vector2.new(0.44, 0),
		Vector2.new(0.46, 0.06),
		Vector2.new(0.3, 0.12),
		Vector2.new(0.002, 0.12),
	}, 6)
	b:setColor(color(params, "flame"))
	b:lathe({
		Vector2.new(0.002, 0.1),
		Vector2.new(0.26, 0.1),
		Vector2.new(0.3, 0.42),
		Vector2.new(0.26, 0.72),
		Vector2.new(0.002, 0.72),
	}, 6)
	b:setColor(iron)
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		local at = CFrame.new(math.cos(angle) * 0.31, 0.42, -math.sin(angle) * 0.31)
		b:box(at, Vector3.new(0.035, 0.62, 0.035))
	end
	cone(b, 0.7, 0.98, 0.46, 6)
	b:torus(0.08, 0.018, 12, 5, CFrame.new(0, 1.04, 0) * CFrame.Angles(math.pi / 2, 0, 0))
end

local function barrel(b: Geo.Builder, params: Params)
	local wood, dark = color(params, "wood"), color(params, "trim")
	local staves = 12
	b.flat = true
	b.colorAt = function(centre: Vector3): Color3
		local angle = (math.atan2(centre.Z, centre.X) + math.pi) / (math.pi * 2)
		local stave = math.floor(angle * staves + 0.5) % 2
		return wood:Lerp(dark, if stave == 0 then 0 else 0.22)
	end
	b:lathe({
		Vector2.new(0.002, 0),
		Vector2.new(0.4, 0),
		Vector2.new(0.48, 0.25),
		Vector2.new(0.5, 0.5),
		Vector2.new(0.48, 0.75),
		Vector2.new(0.4, 1),
		Vector2.new(0.002, 1),
	}, staves)
	b.colorAt = nil
	b:setColor(color(params, "iron"))
	for _, ring in { { 0.17, 0.455 }, { 0.83, 0.455 } } do
		b:torus(ring[2], 0.022, 24, 5, CFrame.new(0, ring[1], 0))
	end
end

local function crate(b: Geo.Builder, params: Params)
	local rng = Geo.rng(params.Seed or 1)
	b.flat = true
	local wood, trim = color(params, "wood"), color(params, "trim")
	banded(b, wood, 0, 1)
	-- Panels sit in from the frame, so the beams throw a shadow line.
	local inset = rng(0.9, 0.93)
	b:box(CFrame.new(0, 0.5, 0), Vector3.new(inset, 0.92, inset))
	banded(b, trim, 0, 1)
	local r, h, beam = 0.46, 0.5, 0.1
	for _, y in { 0, 1 } do
		for _, s in { -1, 1 } do
			b:box(CFrame.new(0, y * 0.9 + 0.05, s * r), Vector3.new(1, beam, beam))
			b:box(CFrame.new(s * r, y * 0.9 + 0.05, 0), Vector3.new(beam, beam, 1))
		end
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			b:box(CFrame.new(x * r, h, z * r), Vector3.new(beam, 1, beam))
		end
	end
	local flip = if rng() < 0.5 then 1 else -1
	for _, z in { -0.475, 0.475 } do
		local brace = CFrame.new(0, 0.5, z) * CFrame.Angles(0, 0, flip * math.pi / 4)
		b:box(brace, Vector3.new(1.2, 0.09, 0.05))
	end
end

-- Every built-in shape by name, for `Geo.register` or your own wrappers.
GeoShapes.Builders = {
	rock = rock,
	tree = tree,
	pine = pine,
	bush = bush,
	crystal = crystal,
	mushroom = mushroom,
	fence = fence,
	lantern = lantern,
	barrel = barrel,
	crate = crate,
} :: { [string]: (Geo.Builder, Params) -> () }

-- Makes every built-in shape available to `Geo.dress` and `Geo.watch`. Call once on each client.
function GeoShapes.register()
	for name, build in GeoShapes.Builders do
		Geo.register(name, build, { vertexColors = true })
	end
end

-- A Part spot standing on `cframe` (the point on the ground, its up axis up). Works on any side; the
-- mesh appears on clients running `Geo.watch`. Lanterns carry their own light.
function GeoShapes.spot(shape: string, cframe: CFrame, opts: SpotOptions?): Part
	local o: SpotOptions = opts or {}
	local size = GeoShapes.Sizes[shape]
	assert(size, `GeoShapes.spot: unknown shape '{shape}'`)
	local part = Instance.new("Part")
	part.Name = o.name or shape
	part.Size = size * (o.scale or 1)
	part.CFrame = cframe * CFrame.new(0, part.Size.Y / 2, 0)
	part.Anchored = true
	part.CanCollide = SOLID[shape] == true
	part.Material = if shape == "lantern" or shape == "crystal" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part:SetAttribute("GeoShape", shape)
	part:SetAttribute("Seed", o.seed or 1)
	for key, value in o.attributes or {} :: { [string]: any } do
		part:SetAttribute(key, value)
	end
	if shape == "lantern" then
		local light = Instance.new("PointLight")
		light.Color = GeoShapes.Palette.flame
		light.Range = 18 * (o.scale or 1)
		light.Brightness = 1.4
		light.Shadows = true
		light.Parent = part
	end
	part.Parent = o.parent
	return part
end

return GeoShapes
