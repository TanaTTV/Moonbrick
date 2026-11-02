--!strict
-- Scene: a persistent look for a place, plus terrain. Nothing here runs by itself: a script must call
-- `Scene.apply`, `Scene.follow` or a terrain helper. Scripts that want a world rebuilt from git call
-- these from a server script; `ArtStyle.applyScene()` applies the look in art.json the same way.
--
--   Scene.apply({
--       lighting = { ClockTime = 17.5, Brightness = 2, Ambient = Color3.fromHex("#2A2F45") },
--       atmosphere = { Density = 0.35, Haze = 1.5, Color = Color3.fromHex("#C8B8A0") },
--       bloom = { Intensity = 0.4, Size = 24, Threshold = 1.1 },
--   })
--   Scene.zone("Cave", workspace.World.CaveVolume, { lighting = { Brightness = 0.4 } }, { edge = 12 })
--   local stop = Scene.follow()                                   -- client: blends zones around the camera
--
--   Scene.sculpt({ center = Vector3.zero, size = Vector3.new(512, 128, 512) }, {
--       noise = { seed = 7, scale = 180, amplitude = 36, base = 20 },
--       biomes = { { material = Enum.Material.Rock, minSlope = 40 },
--                  { material = Enum.Material.Sand, maxHeight = 6 }, { material = Enum.Material.Grass } },
--       water = 4,
--   })
--
-- Look sections use the engine's property names; `Scene.Schema` lists them with their ranges. A section
-- you leave out is left alone, and `false` removes that object. Lighting.Technology can't be set from
-- scripts: pick it in Studio. Applied on the server a look reaches everyone; on a client, that player.
-- Terrain must run on the server (or in Edit mode) to replicate and save; helpers yield between chunks.
local Lighting = game:GetService("Lighting")

local Scheduler = require(script.Parent.Scheduler)

local Scene = {}

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

local COLOR = "color"
local ASSET = "asset"
local BOOLEAN = "boolean"

-- Every property a look may set: { min, max }, or "color", "asset" or "boolean".
Scene.Schema = {
	lighting = {
		Ambient = COLOR,
		OutdoorAmbient = COLOR,
		ColorShift_Top = COLOR,
		ColorShift_Bottom = COLOR,
		FogColor = COLOR,
		ClockTime = { 0, 24 },
		Brightness = { 0, 10 },
		ExposureCompensation = { -5, 5 },
		ShadowSoftness = { 0, 1 },
		EnvironmentDiffuseScale = { 0, 1 },
		EnvironmentSpecularScale = { 0, 1 },
		GeographicLatitude = { -90, 90 },
		FogStart = { 0, 100000 },
		FogEnd = { 0, 100000 },
		GlobalShadows = BOOLEAN,
	},
	atmosphere = {
		Density = { 0, 1 },
		Offset = { 0, 1 },
		Glare = { 0, 10 },
		Haze = { 0, 10 },
		Color = COLOR,
		Decay = COLOR,
	},
	sky = {
		CelestialBodiesShown = BOOLEAN,
		StarCount = { 0, 5000 },
		SunAngularSize = { 0, 60 },
		MoonAngularSize = { 0, 60 },
		SkyboxBk = ASSET,
		SkyboxDn = ASSET,
		SkyboxFt = ASSET,
		SkyboxLf = ASSET,
		SkyboxRt = ASSET,
		SkyboxUp = ASSET,
		SunTextureId = ASSET,
		MoonTextureId = ASSET,
	},
	colorCorrection = {
		Brightness = { -1, 1 },
		Contrast = { -1, 1 },
		Saturation = { -1, 1 },
		TintColor = COLOR,
	},
	bloom = { Intensity = { 0, 10 }, Size = { 0, 56 }, Threshold = { 0, 4 } },
	sunRays = { Intensity = { 0, 1 }, Spread = { 0, 1 } },
}

-- Where each section lives under Lighting. One Atmosphere and one Sky take effect, so those reuse any
-- existing object; the post effects use their own names and leave a game's other effects alone.
local OBJECTS: { [string]: { class: string, name: string? } } = {
	atmosphere = { class = "Atmosphere" },
	sky = { class = "Sky" },
	colorCorrection = { class = "ColorCorrectionEffect", name = "MoonbrickGrade" },
	bloom = { class = "BloomEffect", name = "MoonbrickBloom" },
	sunRays = { class = "SunRaysEffect", name = "MoonbrickSunRays" },
}

local function valueError(section: string, key: string, value: any): string?
	local kinds: any = Scene.Schema
	local rule = kinds[section][key]
	if rule == nil then
		if key == "Technology" then
			return "Lighting.Technology can't be set from scripts; choose it in Studio"
		end
		return `Scene: {section}.{key} is not a look property`
	elseif rule == COLOR then
		return if typeof(value) == "Color3" then nil else `Scene: {section}.{key} must be a Color3`
	elseif rule == BOOLEAN then
		return if type(value) == "boolean" then nil else `Scene: {section}.{key} must be true or false`
	elseif rule == ASSET then
		return if type(value) == "string" and string.find(value, "^rbxasset") ~= nil
			then nil
			else `Scene: {section}.{key} must be an rbxassetid:// or rbxasset:// id`
	end
	if type(value) ~= "number" or value ~= value or value < rule[1] or value > rule[2] then
		return `Scene: {section}.{key} must be a number in {rule[1]}..{rule[2]}`
	end
	return nil
end

-- Checks a look against `Scene.Schema` (pure). Returns false and a reason naming the bad property.
function Scene.validate(look: Look): (boolean, string?)
	if type(look) ~= "table" then
		return false, "Scene: a look must be a table"
	end
	for section, values in look :: any do
		if (Scene.Schema :: any)[section] == nil then
			return false, `Scene: unknown look section '{tostring(section)}'`
		elseif type(values) == "table" then
			for key, value in values do
				local problem = valueError(section, key, value)
				if problem then
					return false, problem
				end
			end
		elseif not (values == false and section ~= "lighting") then
			return false, `Scene: {section} must be a table{if section == "lighting" then "" else " or false"}`
		end
	end
	return true
end

-- `{ "lighting.ClockTime" = 14, ... }`: one value per property, the form zones blend (pure).
function Scene.flatten(look: Look): { [string]: any }
	local flat: { [string]: any } = {}
	for section, values in look :: any do
		if type(values) == "table" then
			for key, value in values do
				flat[`{section}.{key}`] = value
			end
		end
	end
	return flat
end

local function find(section: string): Instance?
	local object = OBJECTS[section]
	if object.name then
		local found = Lighting:FindFirstChild(object.name)
		return if found and found:IsA(object.class) then found else nil
	end
	return Lighting:FindFirstChildOfClass(object.class)
end

local function target(section: string): Instance
	if section == "lighting" then
		return Lighting
	end
	local found = find(section)
	if found then
		return found
	end
	local object = OBJECTS[section]
	local made = Instance.new(object.class)
	if object.name then
		made.Name = object.name
	end
	made.Parent = Lighting
	return made
end

local function write(section: string, key: string, value: any)
	(target(section) :: any)[key] = value
end

-- The look in force, by flat key; zones blend away from these values and back.
local applied: { [string]: any } = {}

-- Makes a look permanent (until the next call). Errors, naming the property, on a look `validate` refuses.
function Scene.apply(look: Look)
	local ok, problem = Scene.validate(look)
	assert(ok, problem)
	for section, values in look :: any do
		if values == false then
			local found = find(section)
			if found then
				found:Destroy()
			end
			for key in applied do
				if string.sub(key, 1, #section + 1) == section .. "." then
					applied[key] = nil
				end
			end
		else
			for key, value in values do
				write(section, key, value)
				applied[`{section}.{key}`] = value
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Zones

local function distanceOutside(shape: ZoneShape, position: Vector3): number
	if typeof(shape) == "Instance" then
		local part = shape :: BasePart
		local half = part.Size / 2
		local p = part.CFrame:ToObjectSpace(CFrame.new(position)).Position
		local x, y, z = math.abs(p.X) - half.X, math.abs(p.Y) - half.Y, math.abs(p.Z) - half.Z
		return Vector3.new(math.max(x, 0), math.max(y, 0), math.max(z, 0)).Magnitude
	end
	local spec = shape :: any
	if spec.radius then
		return math.max((position - spec.center).Magnitude - spec.radius, 0)
	end
	local half = spec.size / 2
	local p = position - spec.center
	local x, y, z = math.abs(p.X) - half.X, math.abs(p.Y) - half.Y, math.abs(p.Z) - half.Z
	return Vector3.new(math.max(x, 0), math.max(y, 0), math.max(z, 0)).Magnitude
end

-- How much of a zone's mood applies at `position`: 1 inside, 0 beyond `edge` studs outside (pure).
function Scene.zoneWeight(shape: ZoneShape, position: Vector3, edge: number?): number
	local width = edge or 8
	local outside = distanceOutside(shape, position)
	if outside <= 0 then
		return 1
	end
	return if width <= 0 then 0 else math.clamp(1 - outside / width, 0, 1)
end

local function blend(key: string, from: any, to: any, alpha: number): any
	if type(from) == "number" then
		if key == "lighting.ClockTime" then
			-- The short way around the clock: 23h to 1h goes through midnight.
			local delta = (to - from + 12) % 24 - 12
			return (from + delta * alpha) % 24
		end
		return from + (to - from) * alpha
	elseif typeof(from) == "Color3" then
		return from:Lerp(to, alpha)
	end
	return if alpha >= 0.5 then to else from
end

-- `base` with each layer blended over it in order (pure). Layers are { values, weight }; keys a layer
-- doesn't name keep what the layers under it left.
function Scene.mix(
	base: { [string]: any },
	layers: { { values: { [string]: any }, weight: number } }
): { [string]: any }
	local out = table.clone(base)
	for _, layer in layers do
		if layer.weight > 0 then
			for key, value in layer.values do
				local from = out[key]
				out[key] = if from == nil then value else blend(key, from, value, layer.weight)
			end
		end
	end
	return out
end

type Zone = {
	name: string,
	shape: ZoneShape,
	values: { [string]: any },
	edge: number,
	fade: number,
	priority: number,
	weight: number,
}

local zones: { [string]: Zone } = {}

-- Registers a named mood for an area, replacing any zone with that name. Does nothing until
-- `Scene.follow` runs. Sky can't blend, so a zone's look can't set it. A section with no object yet (an
-- Atmosphere, say) has nothing to fade from: apply one first for a smooth blend. Returns a function that
-- removes the zone.
function Scene.zone(name: string, shape: ZoneShape, look: Look, opts: ZoneOptions?): () -> ()
	local ok, problem = Scene.validate(look)
	assert(ok, problem)
	assert(look.sky == nil, `Scene.zone '{name}': a zone can't change the Sky`)
	local o: ZoneOptions = opts or {}
	local zone: Zone = {
		name = name,
		shape = shape,
		values = Scene.flatten(look),
		edge = o.edge or 8,
		fade = o.fade or 0.6,
		priority = o.priority or 0,
		weight = 0,
	}
	zones[name] = zone
	return function()
		if zones[name] == zone then
			zones[name] = nil
		end
	end
end

local function current(key: string): any
	local section, property = string.match(key, "^(%w+)%.(.+)$")
	assert(section and property, key)
	if applied[key] ~= nil then
		return applied[key]
	end
	local object = if section == "lighting" then Lighting else find(section)
	return if object then (object :: any)[property] else nil
end

-- Client: blends every zone around `focus()` (default: the camera, so a tour sees each mood) until the
-- returned function is called, then restores the applied look. Runs on the Scheduler, so a freeze holds it.
function Scene.follow(focus: (() -> Vector3)?): () -> ()
	local written: { [string]: any } = {}
	local base: { [string]: any } = {}
	local stopped = false

	local function position(): Vector3?
		if focus then
			return focus()
		end
		local camera = workspace.CurrentCamera
		return if camera then camera.CFrame.Position else nil
	end

	local function flush(values: { [string]: any })
		for key, value in values do
			if written[key] ~= value then
				written[key] = value
				local section, property = string.match(key, "^(%w+)%.(.+)$")
				write(section :: string, property :: string, value)
			end
		end
	end

	local stopJob = Scheduler.every(function(dt)
		if stopped then
			return true
		end
		local at = position()
		if not at then
			return false
		end
		local layers = {}
		local active: { Zone } = {}
		for _, zone in zones do
			local goal = Scene.zoneWeight(zone.shape, at, zone.edge)
			local rate = if zone.fade <= 0 then 1 else dt / zone.fade
			zone.weight += math.clamp(goal - zone.weight, -rate, rate)
			if zone.weight > 0 then
				table.insert(active, zone)
			end
			for key in zone.values do
				if base[key] == nil then
					base[key] = current(key)
				end
			end
		end
		-- Applied values may change while following.
		for key in base do
			if applied[key] ~= nil then
				base[key] = applied[key]
			end
		end
		table.sort(active, function(a, b)
			if a.priority ~= b.priority then
				return a.priority < b.priority
			end
			return a.name < b.name
		end)
		for _, zone in active do
			table.insert(layers, { values = zone.values, weight = zone.weight })
		end
		flush(Scene.mix(base, layers))
		return false
	end)

	return function()
		stopped = true
		stopJob()
		flush(base)
		for _, zone in zones do
			zone.weight = 0
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Terrain

local VOXEL = 4

local function fractal(x: number, z: number, noise: Noise): number
	local frequency, weight, total, range = 1 / noise.scale, 1, 0, 0
	local keep = noise.persistence or 0.5
	local offset = (noise.seed % 4096) * 0.7345 + 0.5
	for octave = 1, noise.octaves or 4 do
		local n = math.noise(x * frequency + offset * octave, z * frequency - offset, offset)
		if noise.ridged then
			n = 1 - 2 * math.abs(n)
		end
		total += n * weight
		range += weight
		weight *= keep
		frequency *= 2
	end
	return total / range
end

-- World height of a seeded landscape at x, z (pure and deterministic: same noise, same world).
function Scene.height(x: number, z: number, noise: Noise): number
	-- math.noise rarely leaves -0.6..0.6, so stretch it to use the amplitude.
	local h = (noise.base or 0) + math.clamp(fractal(x, z, noise) * 1.6, -1, 1) * noise.amplitude
	if noise.terrace and noise.terrace > 0 then
		h = math.floor(h / noise.terrace + 0.5) * noise.terrace
	end
	for _, plateau in noise.plateaus or {} :: { Plateau } do
		local flat = plateau.height or (noise.base or 0)
		local distance = Vector2.new(x - plateau.x, z - plateau.z).Magnitude
		local margin = plateau.blend or plateau.radius * 0.5
		local alpha = if distance <= plateau.radius
			then 1
			else 1 - math.clamp((distance - plateau.radius) / math.max(margin, 1e-3), 0, 1)
		-- Smoothstep, so the plateau rim has no crease.
		alpha = alpha * alpha * (3 - 2 * alpha)
		h += (flat - h) * alpha
	end
	return h
end

-- Slope in degrees of `heightAt(x, z)` at a point (pure).
function Scene.slope(heightAt: (number, number) -> number, x: number, z: number, step: number?): number
	local s = step or VOXEL
	local dx = (heightAt(x + s, z) - heightAt(x - s, z)) / (2 * s)
	local dz = (heightAt(x, z + s) - heightAt(x, z - s)) / (2 * s)
	return math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
end

-- The first biome whose bounds hold (pure). `roll` (0..1) decides `chance`; `jitter` shifts height bounds.
function Scene.biomeAt(biomes: { Biome }, height: number, slope: number, roll: number, jitter: number?): Enum.Material
	local h = height + (jitter or 0)
	for _, biome in biomes do
		if
			h >= (biome.minHeight or -math.huge)
			and h <= (biome.maxHeight or math.huge)
			and slope >= (biome.minSlope or -math.huge)
			and slope <= (biome.maxSlope or math.huge)
			and roll <= (biome.chance or 1)
		then
			return biome.material
		end
	end
	return biomes[#biomes].material
end

-- A chunk grid over min..max (pure): aligned to the 4-stud voxel grid and tiled in X and Z, so
-- `WriteVoxels` regions never overlap.
function Scene.chunks(min: Vector3, max: Vector3, chunk: number?): { { min: Vector3, max: Vector3 } }
	local size = math.max(math.floor((chunk or 64) / VOXEL), 1) * VOXEL
	local function down(v: number): number
		return math.floor(v / VOXEL) * VOXEL
	end
	local function up(v: number): number
		return math.ceil(v / VOXEL) * VOXEL
	end
	local x0, y0, z0 = down(min.X), down(min.Y), down(min.Z)
	local x1, y1, z1 = up(max.X), up(max.Y), up(max.Z)
	local out = {}
	local x = x0
	while x < x1 do
		local z = z0
		while z < z1 do
			table.insert(out, {
				min = Vector3.new(x, y0, z),
				max = Vector3.new(math.min(x + size, x1), y1, math.min(z + size, z1)),
			})
			z += size
		end
		x += size
	end
	return out
end

local function surfacePainter(spec: Sculpt): (number, number, number, (number, number) -> number) -> Enum.Material
	local biomes: { Biome } = spec.biomes or { { material = Enum.Material.Grass } }
	local dither = spec.dither or 3
	local seed = spec.noise.seed
	return function(x, z, height, heightAt)
		local roll = math.clamp(math.noise(x * 0.31 + 0.5, z * 0.31 + 0.5, seed % 97 + 0.5) + 0.5, 0, 1)
		local slope = Scene.slope(heightAt, x, z)
		return Scene.biomeAt(biomes, height, slope, roll, (roll - 0.5) * dither)
	end
end

-- Materials and occupancies for one chunk (pure), indexed [x][y][z] for `Terrain:WriteVoxels`.
function Scene.voxels(
	chunk: { min: Vector3, max: Vector3 },
	spec: Sculpt
): ({ { { Enum.Material } } }, { { { number } } })
	local heightAt = function(x: number, z: number): number
		return Scene.height(x, z, spec.noise)
	end
	local paint = surfacePainter(spec)
	local under = spec.under or Enum.Material.Rock
	local surface = spec.surface or 8
	local min, max = chunk.min, chunk.max
	local nx, ny, nz = (max.X - min.X) / VOXEL, (max.Y - min.Y) / VOXEL, (max.Z - min.Z) / VOXEL
	local materials: { { { Enum.Material } } } = table.create(nx)
	local occupancy: { { { number } } } = table.create(nx)
	for ix = 1, nx do
		local x = min.X + (ix - 0.5) * VOXEL
		local materialPlane: { { Enum.Material } } = table.create(ny)
		local occupancyPlane: { { number } } = table.create(ny)
		for iy = 1, ny do
			materialPlane[iy] = table.create(nz)
			occupancyPlane[iy] = table.create(nz)
		end
		for iz = 1, nz do
			local z = min.Z + (iz - 0.5) * VOXEL
			local height = heightAt(x, z)
			local top = paint(x, z, height, heightAt)
			for iy = 1, ny do
				local bottom = min.Y + (iy - 1) * VOXEL
				local fill = math.clamp((height - bottom) / VOXEL, 0, 1)
				local material = Enum.Material.Air
				if fill > 0 then
					material = if height - bottom > surface then under else top
				elseif spec.water and bottom < spec.water then
					material, fill = Enum.Material.Water, 1
				end
				materialPlane[iy][iz] = material
				occupancyPlane[iy][iz] = fill
			end
		end
		materials[ix] = materialPlane
		occupancy[ix] = occupancyPlane
	end
	return materials, occupancy
end

-- Replaces terrain in `region` with a seeded landscape, one chunk per frame (yields).
function Scene.sculpt(region: Region, spec: Sculpt)
	local half = region.size / 2
	for _, chunk in Scene.chunks(region.center - half, region.center + half, spec.chunk) do
		local materials, occupancy = Scene.voxels(chunk, spec)
		workspace.Terrain:WriteVoxels(Region3.new(chunk.min, chunk.max), VOXEL, materials, occupancy)
		task.wait()
	end
end

-- Repaints one chunk's surface in place (pure): cells within `surface` studs of each column's top get the
-- biome for that column's height and slope. Air and water stay. Returns a new table.
function Scene.repaint(
	materials: { { { Enum.Material } } },
	occupancy: { { { number } } },
	min: Vector3,
	biomes: { Biome },
	surface: number?,
	seed: number?
): { { { Enum.Material } } }
	local depth = math.ceil((surface or 8) / VOXEL)
	local nx, ny, nz = #materials, #materials[1], #materials[1][1]
	local tops: { { number? } } = table.create(nx) -- surface height per column
	local cells: { { number? } } = table.create(nx) -- and the cell it sits in
	for ix = 1, nx do
		local row: { number? } = table.create(nz)
		local cellRow: { number? } = table.create(nz)
		for iz = 1, nz do
			for iy = ny, 1, -1 do
				local material = materials[ix][iy][iz]
				if occupancy[ix][iy][iz] > 0 and material ~= Enum.Material.Air and material ~= Enum.Material.Water then
					row[iz] = min.Y + (iy - 1 + occupancy[ix][iy][iz]) * VOXEL
					cellRow[iz] = iy
					break
				end
			end
		end
		tops[ix], cells[ix] = row, cellRow
	end
	local function top(ix: number, iz: number, fallback: number): number
		local row = tops[math.clamp(ix, 1, nx)]
		return row[math.clamp(iz, 1, nz)] or fallback
	end
	local out: { { { Enum.Material } } } = table.create(nx)
	local noiseSeed = (seed or 1) % 97 + 0.5
	for ix = 1, nx do
		local plane: { { Enum.Material } } = table.create(ny)
		for iy = 1, ny do
			plane[iy] = table.clone(materials[ix][iy])
		end
		for iz = 1, nz do
			local height, topCell = tops[ix][iz], cells[ix][iz]
			if height and topCell then
				local dx = (top(ix + 1, iz, height) - top(ix - 1, iz, height)) / (2 * VOXEL)
				local dz = (top(ix, iz + 1, height) - top(ix, iz - 1, height)) / (2 * VOXEL)
				local slope = math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
				local x, z = min.X + (ix - 0.5) * VOXEL, min.Z + (iz - 0.5) * VOXEL
				local roll = math.clamp(math.noise(x * 0.31 + 0.5, z * 0.31 + 0.5, noiseSeed) + 0.5, 0, 1)
				local material = Scene.biomeAt(biomes, height, slope, roll)
				for iy = math.max(topCell - depth + 1, 1), topCell do
					if plane[iy][iz] ~= Enum.Material.Air and plane[iy][iz] ~= Enum.Material.Water then
						plane[iy][iz] = material
					end
				end
			end
		end
		out[ix] = plane
	end
	return out
end

-- Repaints existing terrain in `region` by height and slope, one chunk per frame (yields).
function Scene.paint(region: Region, biomes: { Biome }, opts: { surface: number?, seed: number?, chunk: number? }?)
	local o: { surface: number?, seed: number?, chunk: number? } = opts or {}
	local half = region.size / 2
	local terrain = workspace.Terrain
	for _, chunk in Scene.chunks(region.center - half, region.center + half, o.chunk) do
		local area = Region3.new(chunk.min, chunk.max)
		local materials, occupancy = terrain:ReadVoxels(area, VOXEL)
		local painted = Scene.repaint(materials :: any, occupancy :: any, chunk.min, biomes, o.surface, o.seed)
		terrain:WriteVoxels(area, VOXEL, painted, occupancy)
		task.wait()
	end
end

-- Fills a box of terrain, in chunks so a huge fill can't stall a frame (yields).
function Scene.fillBox(cframe: CFrame, size: Vector3, material: Enum.Material, chunk: number?)
	local half = size / 2
	local step = chunk or 256
	local x = -half.X
	while x < half.X do
		local z = -half.Z
		local sx = math.min(step, half.X - x)
		while z < half.Z do
			local sz = math.min(step, half.Z - z)
			local at = cframe * CFrame.new(x + sx / 2, 0, z + sz / 2)
			workspace.Terrain:FillBlock(at, Vector3.new(sx, size.Y, sz), material)
			z += step
			task.wait()
		end
		x += step
	end
end

-- Fills a ball of terrain. One engine call: keep radii under a few hundred studs.
function Scene.fillBall(center: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillBall(center, radius, material)
end

return Scene
