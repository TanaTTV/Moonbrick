--!strict
-- Tex: original effect textures (white shapes with alpha; Color tints them). No borrowed art.
--
--   Tex.apply(emitter, "spark")          -- particles/beams/trails: a texture FILE (see below)
--   Tex.apply(decal, "crack")            -- decals/images/meshes: drawn at runtime (EditableImage)
--
-- Verified in Studio 0.743: ImageLabel, Decal (and MeshPart/SurfaceAppearance) render runtime
-- EditableImages; ParticleEmitter, Beam and Trail accept them but render nothing. So those three use
-- files rendered by `python scripts/fxtex.py`: `Tex.usePreview()` after `fxtex.py preview` (Studio on
-- this computer only), or `Tex.useFiles({ spark = "rbxassetid://…" })` after you upload them.
-- Without either they fall back to stock Roblox particle textures, so nothing is ever invisible.
-- Runtime images: draw on the CLIENT (they don't replicate); published games need Game Settings →
-- Security → "Allow Mesh & Image APIs". `Tex.alpha` is the pure pixel function shared with fxtex.py.
local AssetService = game:GetService("AssetService")

local Tex = {}

export type Name =
	"glow"
	| "core"
	| "ring"
	| "spark"
	| "star"
	| "streak"
	| "smoke"
	| "dust"
	| "shard"
	| "crack"
	| "wisp"
export type Options = {
	size: number?, -- pixels per side (or per cell for flipbooks), default 128
	seed: number?,
	softness: number?, -- edge falloff, 0..1
	thickness: number?, -- ring/streak width, 0..1
	points: number?, -- star/spark points
	flipbook: number?, -- 2, 4 or 8: animated grid of `flipbook`² frames
}

-- Flipbook grids of the rendered files (fxtex.py draws these as animated sheets).
Tex.Flipbooks = { smoke = 4, wisp = 4 } :: { [string]: number }

local files: { [string]: string } = {}
local previewBase: string? = nil

-- Uses uploaded texture files: { name = "rbxassetid://…" } (overrides preview and stock).
function Tex.useFiles(map: { [string]: string })
	for name, id in map do
		files[name] = id
	end
end

-- Uses the local Studio preview copied by `python scripts/fxtex.py preview` (this computer only).
function Tex.usePreview(base: string?)
	previewBase = base or "rbxasset://textures/moonbrick/"
end

-- The file texture for a particle/beam/trail and whether it is a flipbook sheet (pure).
function Tex.fileFor(name: string): (string, number?)
	local uploaded = files[name]
	if uploaded then
		return uploaded, Tex.Flipbooks[name]
	elseif previewBase then
		return previewBase .. name .. ".png", Tex.Flipbooks[name]
	end
	return Tex.Fallback[name] or Tex.Fallback.glow, nil
end

-- Stock Roblox textures used when no file is configured (and when runtime drawing fails).
Tex.Fallback = {
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	core = "rbxasset://textures/particles/explosion01_core_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	star = "rbxasset://textures/particles/sparkles_main.dds",
	streak = "rbxasset://textures/particles/fire_sparks_main.dds",
	smoke = "rbxasset://textures/particles/explosion01_smoke_main.dds",
	dust = "rbxasset://textures/particles/smoke_main.dds",
	shard = "rbxasset://textures/particles/sparkles_main.dds",
	crack = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	wisp = "rbxasset://textures/particles/forcefield_vortex_main.dds",
} :: { [string]: string }

-- Deterministic value noise (no engine dependency).
local function hash(x: number, y: number, seed: number): number
	local n = math.sin(x * 127.1 + y * 311.7 + seed * 74.7) * 43758.5453
	return n - math.floor(n)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function noise(x: number, y: number, seed: number): number
	local xi, yi = math.floor(x), math.floor(y)
	local xf, yf = x - xi, y - yi
	local a, b = hash(xi, yi, seed), hash(xi + 1, yi, seed)
	local c, d = hash(xi, yi + 1, seed), hash(xi + 1, yi + 1, seed)
	local u, v = smooth(xf), smooth(yf)
	return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
end

function Tex.noise(x: number, y: number, seed: number?, octaves: number?): number
	local total, amplitude, frequency, norm = 0, 1, 1, 0
	for _ = 1, octaves or 4 do
		total += noise(x * frequency, y * frequency, seed or 0) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return total / norm
end

local function falloff(d: number, softness: number): number
	-- 1 at the centre, 0 at d >= 1, with a soft shoulder of width `softness`.
	if d >= 1 then
		return 0
	end
	local edge = math.max(softness, 1e-3)
	return math.clamp((1 - d) / edge, 0, 1)
end

-- Alpha (0..1) of texture `name` at u, v in -1..1. `frame` (0..1) animates flipbook textures.
function Tex.alpha(name: string, u: number, v: number, opts: Options?, frame: number?): number
	local o: Options = opts or {}
	local seed = o.seed or 1
	local t = frame or 0
	local r = math.sqrt(u * u + v * v)
	local angle = math.atan2(v, u)
	if name == "glow" then
		return (1 - math.clamp(r, 0, 1)) ^ 2.2
	elseif name == "core" then
		return falloff(r, o.softness or 0.35) ^ 0.8
	elseif name == "ring" then
		local width = o.thickness or 0.14
		local d = math.abs(r - (0.86 - width)) / width
		return falloff(d, o.softness or 0.8) * (if r < 1 then 1 else 0)
	elseif name == "spark" or name == "star" then
		local points = o.points or (if name == "spark" then 4 else 6)
		local spikes = math.abs(math.cos(angle * points / 2)) ^ (if name == "spark" then 18 else 8)
		local arm = falloff(r, 1) ^ 1.5 * spikes
		local centre = (1 - math.clamp(r * 3.2, 0, 1)) ^ 2
		return math.clamp(arm + centre, 0, 1)
	elseif name == "streak" then
		local width = o.thickness or 0.12
		local along = 1 - math.clamp(math.abs(u), 0, 1)
		local across = falloff(math.abs(v) / width, 0.9)
		return across * along ^ 0.6
	elseif name == "smoke" then
		-- A billowing puff that grows and thins over the flipbook.
		local grow = 0.55 + 0.4 * t
		local n = Tex.noise(u * 2.2 + seed, v * 2.2 - t * 1.5, seed, 4)
		local shape = falloff(r / grow, 0.6) * (0.45 + 0.75 * n)
		return math.clamp(shape * (1 - t * 0.85), 0, 1)
	elseif name == "dust" then
		local n = Tex.noise(u * 6 + seed, v * 6, seed, 3)
		return math.clamp(falloff(r, 0.9) * (n - 0.35) * 2.2, 0, 1)
	elseif name == "shard" then
		-- A sharp kite: long along v, thin along u.
		local d = math.abs(u) / 0.32 + math.abs(v) / 0.98
		return falloff(d, 0.12)
	elseif name == "crack" then
		-- Thin branching lines radiating from the centre.
		local branches = 7
		local wobble = (Tex.noise(r * 4, angle * 2, seed, 2) - 0.5) * 0.5
		local line = math.abs(math.sin((angle + wobble) * branches / 2))
		local thin = 1 - math.clamp(line / (0.06 + 0.08 * (1 - r)), 0, 1)
		return thin * falloff(r, 0.5)
	elseif name == "wisp" then
		-- A curling ribbon of energy.
		local swirl = math.sin(angle * 2 + r * 7 - t * 6.28 + seed)
		local band = 1 - math.clamp(math.abs(swirl) / 0.35, 0, 1)
		return band * falloff(r, 0.7) * (0.6 + 0.4 * Tex.noise(u * 3, v * 3, seed, 2))
	end
	return falloff(r, 0.5)
end

local cache: { [string]: any } = {}

local function key(name: string, o: Options): string
	return string.format(
		"%s|%d|%d|%.3f|%.3f|%d|%d",
		name,
		o.size or 128,
		o.seed or 1,
		o.softness or -1,
		o.thickness or -1,
		o.points or 0,
		o.flipbook or 0
	)
end

local function draw(name: string, o: Options): any
	local cell = math.clamp(math.floor(o.size or 128), 16, 512)
	local grid = o.flipbook or 1
	assert(grid == 1 or grid == 2 or grid == 4 or grid == 8, "flipbook must be 2, 4 or 8")
	local side = cell * grid
	assert(side <= 1024, "texture too large (max 1024 px)")
	local image = AssetService:CreateEditableImage({ Size = Vector2.new(side, side) })
	local pixels = buffer.create(side * side * 4)
	for gy = 0, grid - 1 do
		for gx = 0, grid - 1 do
			local frame = if grid > 1 then (gy * grid + gx) / (grid * grid - 1) else 0
			for y = 0, cell - 1 do
				local v = (y + 0.5) / cell * 2 - 1
				for x = 0, cell - 1 do
					local u = (x + 0.5) / cell * 2 - 1
					local a = Tex.alpha(name, u, v, o, frame)
					local index = (((gy * cell + y) * side) + gx * cell + x) * 4
					buffer.writeu8(pixels, index, 255)
					buffer.writeu8(pixels, index + 1, 255)
					buffer.writeu8(pixels, index + 2, 255)
					buffer.writeu8(pixels, index + 3, math.floor(math.clamp(a, 0, 1) * 255 + 0.5))
				end
			end
		end
	end
	image:WritePixelsBuffer(Vector2.zero, image.Size, pixels)
	return Content.fromObject(image)
end

-- The drawn texture as Content, or nil when runtime images are unavailable here.
function Tex.get(name: string, opts: Options?): any
	local o: Options = opts or {}
	local k = key(name, o)
	local cached = cache[k]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local ok, result = pcall(draw, name, o)
	if not ok then
		warn(`Tex: drawing '{name}' failed ({result}); using a stock texture`)
		cache[k] = false
		return nil
	end
	cache[k] = result
	return result
end

local LAYOUTS: { [number]: Enum.ParticleFlipbookLayout } = {
	[2] = Enum.ParticleFlipbookLayout.Grid2x2,
	[4] = Enum.ParticleFlipbookLayout.Grid4x4,
	[8] = Enum.ParticleFlipbookLayout.Grid8x8,
}

-- Puts texture `name` on a ParticleEmitter, Beam, Trail, ImageLabel/ImageButton or Decal.
-- Falls back to a stock Roblox texture where runtime images are unavailable.
function Tex.apply(target: Instance, name: string, opts: Options?)
	local o: Options = opts or {}
	local any = target :: any
	if target:IsA("ParticleEmitter") or target:IsA("Beam") or target:IsA("Trail") then
		local id, grid = Tex.fileFor(name)
		any.Texture = id
		if target:IsA("ParticleEmitter") and grid and LAYOUTS[grid] then
			-- Layout before mode, or the emitter loops frame 1 (see the studio skill).
			any.FlipbookLayout = LAYOUTS[grid]
			any.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		end
		return
	end
	local content = Tex.get(name, o)
	if target:IsA("ImageLabel") or target:IsA("ImageButton") then
		if content then
			any.ImageContent = content
		else
			any.Image = Tex.Fallback[name] or Tex.Fallback.glow
		end
	elseif target:IsA("Decal") then
		if content then
			any.ColorMapContent = content
		else
			any.Texture = Tex.Fallback[name] or Tex.Fallback.glow
		end
	else
		error(`Tex.apply: unsupported target {target.ClassName}`)
	end
end

-- Drops cached textures (call when leaving a scene that used many).
function Tex.clear()
	table.clear(cache)
end

return Tex
