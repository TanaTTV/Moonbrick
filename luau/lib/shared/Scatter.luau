--!strict
-- Scatter: seeded prop placement over a region or terrain. `Scatter.plan` decides where things go and
-- touches no instances (same seed, same layout), and `Scatter.place` makes them.
--
--   local plan = Scatter.plan({
--       seed = 11, spacing = 14, count = 120,
--       region = { center = Vector3.new(0, 0, 0), size = Vector3.new(400, 0, 400) },
--       sample = Scatter.ground({ top = 300 }),                  -- raycast down onto terrain or parts
--       slopeMax = 28, density = { inner = 60, outer = 200 },    -- thicker at the centre
--       avoid = Scatter.around(workspace.World.Roads, 6),
--       scale = { 0.8, 1.4 }, tilt = 4, align = 0.6, variants = 3,
--   })
--   Scatter.place(plan, { "pine", "tree" }, { parent = workspace.World })   -- GeoShapes spots
--
-- `what` can be a GeoShapes name, a list of them (picked per placement), a Model or BasePart to clone,
-- or a function(placement) returning an instance. Spots made on the server replicate, spots made in
-- Edit mode save, and clients need `Geo.watch` either way. A Model's pivot should sit at its base.
local Geo = require(script.Parent.Geo)
local GeoShapes = require(script.Parent.GeoShapes)

local Scatter = {}

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

local UP = Vector3.new(0, 1, 0)
local MAX_POINTS = 20000
local ATTEMPTS = 16

local function bounds(region: Region): (number, number, number, number)
	local spec = region :: any
	if spec.radius then
		local c, r = spec.center, spec.radius
		return c.X - r, c.Z - r, c.X + r, c.Z + r
	end
	local c, half = spec.center, spec.size / 2
	return c.X - half.X, c.Z - half.Z, c.X + half.X, c.Z + half.Z
end

local function inside(region: Region, x: number, z: number): boolean
	local spec = region :: any
	if spec.radius then
		return Vector2.new(x - spec.center.X, z - spec.center.Z).Magnitude <= spec.radius
	end
	local half = spec.size / 2
	return math.abs(x - spec.center.X) <= half.X and math.abs(z - spec.center.Z) <= half.Z
end

-- Poisson-disc points (pure; Bridson's algorithm): every pair is at least `spacing` apart and the
-- gaps stay even, with none of the clumps plain random placement gives.
function Scatter.points(region: Region, spacing: number, seed: number, limit: number?): { Vector2 }
	assert(spacing > 0, "Scatter: spacing must be positive")
	local rng = Geo.rng(seed)
	local x0, z0, x1, z1 = bounds(region)
	local cap = math.min(limit or MAX_POINTS, MAX_POINTS)
	local cell = spacing / math.sqrt(2)
	local grid: { [number]: Vector2 } = {}
	local columns = math.ceil((x1 - x0) / cell) + 2
	local function key(x: number, z: number): number
		return math.floor((x - x0) / cell) + math.floor((z - z0) / cell) * columns
	end
	local function clear(x: number, z: number): boolean
		local cx, cz = math.floor((x - x0) / cell), math.floor((z - z0) / cell)
		for dz = -2, 2 do
			for dx = -2, 2 do
				local other = grid[(cx + dx) + (cz + dz) * columns]
				if other and Vector2.new(other.X - x, other.Y - z).Magnitude < spacing then
					return false
				end
			end
		end
		return true
	end

	local points: { Vector2 } = {}
	local active: { Vector2 } = {}
	local function add(x: number, z: number)
		local point = Vector2.new(x, z)
		table.insert(points, point)
		table.insert(active, point)
		grid[key(x, z)] = point
	end
	for _ = 1, 64 do
		local x, z = rng(x0, x1), rng(z0, z1)
		if inside(region, x, z) then
			add(x, z)
			break
		end
	end
	while #active > 0 and #points < cap do
		local index = math.floor(rng(1, #active + 1))
		local from = active[index]
		local placed = false
		for _ = 1, ATTEMPTS do
			local angle, reach = rng(0, math.pi * 2), rng(spacing, spacing * 2)
			local x, z = from.X + math.cos(angle) * reach, from.Y + math.sin(angle) * reach
			if inside(region, x, z) and clear(x, z) then
				add(x, z)
				placed = true
				break
			end
		end
		if not placed then
			active[index] = active[#active]
			active[#active] = nil
		end
	end
	return points
end

-- Chance to keep a point at x, z under a density setting (pure).
function Scatter.densityAt(density: (number | Falloff | ((number, number) -> number))?, x: number, z: number): number
	if density == nil then
		return 1
	elseif type(density) == "number" then
		return density
	elseif type(density) == "function" then
		return density(x, z)
	end
	local falloff = density :: Falloff
	local centre = falloff.center or Vector3.zero
	local distance = Vector2.new(x - centre.X, z - centre.Z).Magnitude
	local alpha = 1 - math.clamp((distance - falloff.inner) / math.max(falloff.outer - falloff.inner, 1e-3), 0, 1)
	return alpha ^ (falloff.power or 1)
end

local function standing(position: Vector3, up: Vector3): CFrame
	local right = if math.abs(up.Y) > 0.999 then Vector3.xAxis else up:Cross(Vector3.zAxis).Unit
	return CFrame.fromMatrix(position, right, up, right:Cross(up).Unit)
end

-- Where everything goes (pure unless `opts.sample` raycasts; yields only with `opts.chunk`).
function Scatter.plan(opts: Options): { Placement }
	local rng = Geo.rng(opts.seed + 1)
	local region = opts.region
	local groundY = region.center.Y
	local yaw = opts.yaw or { 0, 360 }
	local scale = opts.scale or { 1, 1 }
	local align = math.clamp(opts.align or 0, 0, 1)
	local tilt = math.rad(opts.tilt or 0)
	local out: { Placement } = {}
	for index, point in Scatter.points(region, opts.spacing, opts.seed) do
		if opts.count and #out >= opts.count then
			break
		end
		if opts.chunk and index % opts.chunk == 0 then
			task.wait()
		end
		-- Every roll is drawn up front, so one rejected point can't shift the rest of the layout.
		local keep, yawRoll, scaleRoll, leanRoll, turnRoll, variantRoll = rng(), rng(), rng(), rng(), rng(), rng()
		local x, z = point.X, point.Y
		local hit: Hit? = if opts.sample
			then opts.sample(x, z)
			else { position = Vector3.new(x, groundY, z), normal = Vector3.yAxis }
		local allowed = hit ~= nil and keep <= Scatter.densityAt(opts.density, x, z)
		if hit and allowed and hit.material == Enum.Material.Water then
			allowed = opts.materials ~= nil and table.find(opts.materials, Enum.Material.Water) ~= nil
		end
		if hit and allowed and opts.materials and hit.material then
			allowed = table.find(opts.materials, hit.material) ~= nil
		end
		if hit and allowed and opts.slopeMax then
			local angle = math.deg(math.acos(math.clamp(hit.normal.Y, -1, 1)))
			allowed = angle <= opts.slopeMax
		end
		if hit and allowed then
			for _, keepOut in opts.avoid or {} :: { Avoid } do
				local away = Vector2.new(hit.position.X - keepOut.position.X, hit.position.Z - keepOut.position.Z)
				if away.Magnitude < keepOut.radius then
					allowed = false
					break
				end
			end
		end
		if hit and allowed then
			local up = UP:Lerp(hit.normal, align).Unit
			local cf = standing(hit.position, up)
				* CFrame.Angles(0, math.rad(yaw[1] + (yaw[2] - yaw[1]) * yawRoll), 0)
				* CFrame.Angles((leanRoll - 0.5) * 2 * tilt, 0, (turnRoll - 0.5) * 2 * tilt)
			table.insert(out, {
				position = hit.position,
				normal = hit.normal,
				scale = scale[1] + ((scale[2] or scale[1]) - scale[1]) * scaleRoll,
				cframe = cf,
				variant = math.floor(variantRoll * (opts.variants or 1)) + 1,
				index = #out + 1,
			})
		end
	end
	return out
end

-- A `sample` function that raycasts straight down. `top` is the Y to start from; `depth` how far to
-- look (default twice `top`, at least 1000); `exclude` skips instances, such as already scattered props.
function Scatter.ground(opts: { top: number, depth: number?, exclude: { Instance }? }): (number, number) -> Hit?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = opts.exclude or {}
	params.IgnoreWater = false -- so props don't sink to the lake bed; `Scatter.plan` drops water hits
	local depth = opts.depth or math.max(math.abs(opts.top) * 2, 1000)
	return function(x, z)
		local hit = workspace:Raycast(Vector3.new(x, opts.top, z), Vector3.new(0, -depth, 0), params)
		if not hit then
			return nil
		end
		return { position = hit.Position, normal = hit.Normal, material = hit.Material }
	end
end

-- An `avoid` list from instances: each part or model keeps props `pad` studs clear of its bounds.
function Scatter.around(root: Instance | { Instance }, pad: number?): { Avoid }
	local out: { Avoid } = {}
	local extra = pad or 0
	local function add(cf: CFrame, size: Vector3)
		table.insert(out, { position = cf.Position, radius = math.max(size.X, size.Z) / 2 + extra })
	end
	local list: { Instance } = if typeof(root) == "Instance" then root:GetChildren() else root :: { Instance }
	if typeof(root) == "Instance" and #list == 0 then
		list = { root }
	end
	for _, item in list do
		if item:IsA("Model") then
			local cf, size = item:GetBoundingBox()
			add(cf, size)
		elseif item:IsA("BasePart") then
			add(item.CFrame, item.Size)
		end
	end
	return out
end

local function spawnFrom(what: Target, placement: Placement): Instance?
	if typeof(what) == "Instance" then
		if what:IsA("Model") then
			local model = what:Clone()
			model:ScaleTo(what:GetScale() * placement.scale)
			model:PivotTo(placement.cframe)
			return model
		end
		local part = (what :: BasePart):Clone()
		part.Size *= placement.scale
		part.CFrame = placement.cframe * CFrame.new(0, part.Size.Y / 2, 0)
		return part
	elseif type(what) == "function" then
		return what(placement)
	end
	local list: { string } = if type(what) == "string" then { what } else what :: { string }
	local name = list[(placement.index - 1) % #list + 1]
	return GeoShapes.spot(name, placement.cframe, { seed = placement.variant, scale = placement.scale })
end

-- Makes a plan real in a new Folder, `chunk` instances per frame (default 64; yields). Returns the folder.
function Scatter.place(plan: { Placement }, what: Target, opts: PlaceOptions?): Folder
	local o: PlaceOptions = opts or {}
	local folder = Instance.new("Folder")
	folder.Name = o.name or "Scatter"
	folder.Parent = o.parent or workspace
	local chunk = o.chunk or 64
	for index, placement in plan do
		local made = spawnFrom(what, placement)
		if made then
			made.Parent = folder
		end
		if index % chunk == 0 then
			task.wait()
		end
	end
	return folder
end

return Scatter
