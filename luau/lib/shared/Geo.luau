--!strict
-- Geo: procedural meshes from Luau (EditableMesh → MeshPart), for props, architecture and effect shapes
-- that parts can't make (rings, domes, lathed vases, tubes, extruded silhouettes). No Blender, no upload.
--
--   local ring = Geo.cached("Ring", function(b) b:torus(4, 0.5, 48, 12) end)   -- built once, then cloned
--   local part = ring:Clone() ; part.Material = Enum.Material.Neon ; part.Parent = workspace
--   local vase = Geo.build(function(b)
--       b:setColor(Color3.fromRGB(180, 90, 60))
--       b:lathe({ Vector2.new(0, 0), Vector2.new(1.4, 0.2), Vector2.new(0.9, 2), Vector2.new(1.2, 3) }, 24)
--   end)
--
-- Shared vertices shade smoothly (Roblox computes normals); `b.flat = true` before building gives hard
-- facets. Runtime meshes don't save with the place and DON'T render when made on the server (verified in
-- Studio 0.743: clients see a "missing mesh" checker). Build them on clients: for world props, put
-- ordinary parts ("spots") with a `GeoShape` attribute in the world (they save, collide and replicate)
-- and call `Geo.dress(workspace)` from a client script; each spot gets its mesh and turns invisible.
-- Clients allow few live growable EditableMeshes (8 in Studio 0.743), so each build is baked into a
-- fixed-size copy (hundreds allowed) and the builder freed. Still prefer few distinct shapes and many
-- clones: clones share one mesh.
-- Published games need Game Settings → Security → "Allow Mesh & Image APIs".
-- Approach adapted from RoClicks meshlab's lathe/tube/loft helpers and its "shape spot" idea (MIT).
local AssetService = game:GetService("AssetService")

local Geo = {}

export type Builder = {
	mesh: EditableMesh,
	flat: boolean,
	-- Per-face colour from the triangle's centre (speckles, gradients, AO); overrides setColor.
	colorAt: ((Vector3) -> Color3)?,
	vertex: (self: Builder, p: Vector3) -> number,
	tri: (self: Builder, a: number, b: number, c: number) -> (),
	quad: (self: Builder, a: number, b: number, c: number, d: number) -> (),
	setColor: (self: Builder, color: Color3?) -> (),
	grid: (self: Builder, rows: { { Vector3 } }, closed: boolean?) -> (),
	lathe: (
		self: Builder,
		profile: { Vector2 },
		segments: number,
		cf: CFrame?,
		radiusAt: ((number, number) -> number)?
	) -> (),
	torus: (self: Builder, radius: number, thickness: number, segments: number?, sides: number?, cf: CFrame?) -> (),
	tube: (self: Builder, path: { Vector3 }, radius: number | { number }, sides: number?) -> (),
	box: (self: Builder, cf: CFrame, size: Vector3) -> (),
	extrude: (self: Builder, outline: { Vector2 }, height: number, cf: CFrame?) -> (),
	sphere: (self: Builder, radius: number, rings: number?, segments: number?, cf: CFrame?) -> (),
	displace: (self: Builder, fn: (Vector3) -> Vector3) -> (),
	volume: (self: Builder) -> number,
	count: (self: Builder) -> number,
}

type Internal = Builder & {
	_positions: { [number]: Vector3 },
	_order: { number },
	_color: Color3?,
	_colorIds: { [string]: number },
	_faces: number,
}

local MAX_FACES = 20000

local BuilderMethods = {}
BuilderMethods.__index = BuilderMethods

function BuilderMethods.vertex(self: Internal, p: Vector3): number
	local id = self.mesh:AddVertex(p)
	self._positions[id] = p
	table.insert(self._order, id)
	return id
end

function BuilderMethods.setColor(self: Internal, color: Color3?)
	self._color = color
end

function BuilderMethods.tri(self: Internal, a: number, b: number, c: number)
	assert(self._faces < MAX_FACES, `Geo: more than {MAX_FACES} triangles; simplify the model`)
	if self.flat then
		-- Hard facets: each triangle gets its own corners, so normals are not shared.
		a = self.mesh:AddVertex(self._positions[a])
		b = self.mesh:AddVertex(self._positions[b])
		c = self.mesh:AddVertex(self._positions[c])
	end
	local face = self.mesh:AddTriangle(a, b, c)
	self._faces += 1
	local color = self._color
	if self.colorAt then
		local centre = (self.mesh:GetPosition(a) + self.mesh:GetPosition(b) + self.mesh:GetPosition(c)) / 3
		color = self.colorAt(centre)
	end
	if color then
		local key = color:ToHex()
		local id = self._colorIds[key]
		if not id then
			id = self.mesh:AddColor(color, 1)
			self._colorIds[key] = id
		end
		self.mesh:SetFaceColors(face, { id, id, id })
	end
end

function BuilderMethods.quad(self: Internal, a: number, b: number, c: number, d: number)
	BuilderMethods.tri(self, a, b, c)
	BuilderMethods.tri(self, a, c, d)
end

-- A surface through rows of points; `closed` wraps each row back to its first point.
-- Front faces (the visible side; Roblox culls the back) face where rows advance counter-clockwise
-- around: outward for lathes, tubes and tori.
function BuilderMethods.grid(self: Internal, rows: { { Vector3 } }, closed: boolean?)
	local ids: { { number } } = {}
	for i, row in rows do
		ids[i] = {}
		for j, p in row do
			ids[i][j] = BuilderMethods.vertex(self, p)
		end
	end
	for i = 1, #rows - 1 do
		local count = #rows[i]
		local last = if closed then count else count - 1
		for j = 1, last do
			local k = if j == count then 1 else j + 1
			BuilderMethods.quad(self, ids[i][j], ids[i][k], ids[i + 1][k], ids[i + 1][j])
		end
	end
end

-- Surface of revolution around the Y axis. profile = { Vector2(radius, y), … } from bottom to top.
-- `radiusAt(angle, y)` scales the radius (ribs, petals, bulges).
function BuilderMethods.lathe(
	self: Internal,
	profile: { Vector2 },
	segments: number,
	cf: CFrame?,
	radiusAt: ((number, number) -> number)?
)
	local frame = cf or CFrame.identity
	local rows: { { Vector3 } } = {}
	for _, point in profile do
		local row = {}
		for s = 0, segments - 1 do
			local angle = s / segments * math.pi * 2
			local r = point.X * (if radiusAt then radiusAt(angle, point.Y) else 1)
			table.insert(row, frame * Vector3.new(math.cos(angle) * r, point.Y, -math.sin(angle) * r))
		end
		table.insert(rows, row)
	end
	BuilderMethods.grid(self, rows, true)
end

function BuilderMethods.torus(
	self: Internal,
	radius: number,
	thickness: number,
	segments: number?,
	sides: number?,
	cf: CFrame?
)
	local frame = cf or CFrame.identity
	local S, s = segments or 48, sides or 12
	local rows: { { Vector3 } } = {}
	for j = 0, s do
		local b = j / s * math.pi * 2
		local row = {}
		for i = 0, S - 1 do
			local a = i / S * math.pi * 2
			local d = radius + thickness * math.cos(b)
			table.insert(row, frame * Vector3.new(d * math.cos(a), thickness * math.sin(b), -d * math.sin(a)))
		end
		table.insert(rows, row)
	end
	BuilderMethods.grid(self, rows, true)
end

-- A tube along a path (open ends are capped to a point). `radius` is one value or one per point.
function BuilderMethods.tube(self: Internal, path: { Vector3 }, radius: number | { number }, sides: number?)
	assert(#path >= 2, "Geo.tube needs at least two points")
	local n = sides or 10
	local rows: { { Vector3 } } = {}
	for i, p in path do
		local ahead = path[math.min(i + 1, #path)] - path[math.max(i - 1, 1)]
		local forward = if ahead.Magnitude > 1e-6 then ahead.Unit else Vector3.yAxis
		local side = forward:Cross(if math.abs(forward.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis).Unit
		local up = side:Cross(forward).Unit
		local r = if type(radius) == "number" then radius else radius[i]
		local row = {}
		for s = 0, n - 1 do
			local a = s / n * math.pi * 2
			table.insert(row, p + (side * math.cos(a) - up * math.sin(a)) * r) -- turns so faces point outward
		end
		table.insert(rows, row)
	end
	-- Caps: collapse to the end points.
	local first, last = {}, {}
	for _ = 1, n do
		table.insert(first, path[1])
		table.insert(last, path[#path])
	end
	table.insert(rows, 1, first)
	table.insert(rows, last)
	BuilderMethods.grid(self, rows, true)
end

local BOX_FACES = {
	{ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) },
	{ Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1) },
	{ Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0) },
	{ Vector3.new(0, -1, 0), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0) },
	{ Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0) },
	{ Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0) },
}

-- A box with hard edges (its own vertices per face).
function BuilderMethods.box(self: Internal, cf: CFrame, size: Vector3)
	local h = size / 2
	for _, face in BOX_FACES do
		local n, u, v = face[1], face[2], face[3]
		local c = n * h
		local du, dv = u * h, v * h
		local a = BuilderMethods.vertex(self, cf * (c - du - dv))
		local b = BuilderMethods.vertex(self, cf * (c + du - dv))
		local cc = BuilderMethods.vertex(self, cf * (c + du + dv))
		local d = BuilderMethods.vertex(self, cf * (c - du + dv))
		BuilderMethods.quad(self, a, b, cc, d)
	end
end

-- Extrudes a convex or simple outline (X, Z on the ground plane, either direction) upward by `height`,
-- with caps. Concave outlines cap correctly only if star-shaped around their centre.
function BuilderMethods.extrude(self: Internal, outline: { Vector2 }, height: number, cf: CFrame?)
	local frame = cf or CFrame.identity
	local n = #outline
	assert(n >= 3, "Geo.extrude needs at least three outline points")
	local centre = Vector2.zero
	local area = 0
	for i, p in outline do
		centre += p / n
		local q = outline[i % n + 1]
		area += p.X * q.Y - q.X * p.Y
	end
	-- Wind every face outward whichever way the outline runs.
	local function face(a: number, b: number, c: number)
		if area >= 0 then
			BuilderMethods.tri(self, a, b, c)
		else
			BuilderMethods.tri(self, a, c, b)
		end
	end
	local bottom, top = {}, {}
	for _, p in outline do
		table.insert(bottom, BuilderMethods.vertex(self, frame * Vector3.new(p.X, 0, p.Y)))
		table.insert(top, BuilderMethods.vertex(self, frame * Vector3.new(p.X, height, p.Y)))
	end
	for i = 1, n do
		local j = i % n + 1
		-- Separate side vertices keep the wall edges sharp.
		local a = BuilderMethods.vertex(self, self._positions[bottom[i]])
		local b = BuilderMethods.vertex(self, self._positions[bottom[j]])
		local c = BuilderMethods.vertex(self, self._positions[top[j]])
		local d = BuilderMethods.vertex(self, self._positions[top[i]])
		face(a, d, c)
		face(a, c, b)
	end
	local cb = BuilderMethods.vertex(self, frame * Vector3.new(centre.X, 0, centre.Y))
	local ct = BuilderMethods.vertex(self, frame * Vector3.new(centre.X, height, centre.Y))
	for i = 1, n do
		local j = i % n + 1
		face(ct, top[j], top[i])
		face(cb, bottom[i], bottom[j])
	end
end

function BuilderMethods.sphere(self: Internal, radius: number, rings: number?, segments: number?, cf: CFrame?)
	local profile = {}
	local r = rings or 10
	for i = 0, r do
		local a = -math.pi / 2 + i / r * math.pi
		table.insert(profile, Vector2.new(math.cos(a) * radius, math.sin(a) * radius))
	end
	BuilderMethods.lathe(self, profile, segments or 16, cf)
end

-- Moves every vertex by `fn(position)` (noise, bulges, wind-worn edges).
function BuilderMethods.displace(self: Internal, fn: (Vector3) -> Vector3)
	for _, id in self.mesh:GetVertices() do
		local p = self.mesh:GetPosition(id)
		self.mesh:SetPosition(id, p + fn(p))
	end
end

-- Signed volume of the mesh so far: positive when faces point outward (a closed shape built right),
-- negative when it is inside-out. Used by tests.
function BuilderMethods.volume(self: Internal): number
	local total = 0
	for _, face in self.mesh:GetFaces() do
		local v = self.mesh:GetFaceVertices(face)
		local a, b, c = self.mesh:GetPosition(v[1]), self.mesh:GetPosition(v[2]), self.mesh:GetPosition(v[3])
		total += a:Dot(b:Cross(c)) / 6
	end
	return total
end

function BuilderMethods.count(self: Internal): number
	return self._faces
end

function Geo.new(): Builder
	local mesh = AssetService:CreateEditableMesh()
	assert(mesh, "Geo: EditableMesh budget reached (share templates: fewer distinct shapes/params)")
	local self = setmetatable({
		mesh = mesh,
		flat = false,
		colorAt = nil,
		_positions = {},
		_order = {},
		_color = nil,
		_colorIds = {},
		_faces = 0,
	}, BuilderMethods) :: any
	return self
end

export type PartOptions = {
	name: string?,
	material: Enum.Material?,
	color: Color3?,
	anchored: boolean?,
	collision: boolean?,
}

-- The fixed-size meshes behind generated parts. They must stay alive: destroying one blanks every
-- MeshPart made from it, clones included (verified).
local baked: { [MeshPart]: EditableMesh } = {}

-- Turns a builder into a MeshPart, centred on its bounds (yields). The builder can't be used afterwards. Model space stays world space:
-- the part is placed where the mesh was built around the origin.
function Geo.toPart(builder: Builder, opts: PartOptions?): MeshPart
	local o: PartOptions = opts or {}
	local mesh = builder.mesh
	local ids = mesh:GetVertices()
	assert(#ids > 0, "Geo: the mesh is empty")
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, id in ids do
		local p = mesh:GetPosition(id)
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local centre = (lo + hi) / 2
	for _, id in ids do
		mesh:SetPosition(id, mesh:GetPosition(id) - centre)
	end
	-- Bake into a fixed-size copy and free the growable builder: clients allow only a handful of live
	-- growable EditableMeshes (8 measured in Studio 0.743) but hundreds of fixed-size ones.
	local fixed = AssetService:CreateEditableMeshAsync(Content.fromObject(mesh), { FixedSize = true })
	mesh:Destroy()
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(fixed))
	baked[part] = fixed
	part.Name = o.name or "GeoMesh"
	part.Anchored = o.anchored ~= false
	part.Material = o.material or Enum.Material.SmoothPlastic
	part.Color = o.color or Color3.new(1, 1, 1)
	if o.collision == false then
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
	end
	part.CFrame = CFrame.new(centre)
	return part
end

-- Builds a MeshPart in one call (yields).
function Geo.build(fn: (Builder) -> (), opts: PartOptions?): MeshPart
	local builder = Geo.new()
	local ok, err: any = pcall(function()
		fn(builder)
	end)
	if not ok then
		builder.mesh:Destroy() -- don't leak budget on a failed build
		error(err, 2)
	end
	return Geo.toPart(builder, opts)
end

local cache: { [string]: MeshPart } = {}
local building: { [string]: boolean } = {}

-- A template MeshPart built once per key; Clone() it for each use (clones share the mesh data).
-- Yields on the first build; concurrent callers for the same key wait for that one build.
function Geo.cached(key: string, fn: (Builder) -> (), opts: PartOptions?): MeshPart
	while building[key] do
		task.wait()
	end
	local template = cache[key]
	if not template then
		building[key] = true
		local ok, result: any = pcall(Geo.build, fn, opts)
		building[key] = nil
		if not ok then
			error(result, 0) -- not cached: a later call retries
		end
		template = result
		cache[key] = template
	end
	return template
end

-- Unit shapes used by Fx mesh layers (size 1 along each axis after Fx scales them).
function Geo.unitTorus(thickness: number?): MeshPart
	local t = thickness or 0.06
	return Geo.cached("UnitTorus" .. t, function(b)
		b:torus(0.5 - t, t, 64, 10)
	end, { collision = false })
end

-- A faceted crystal shard 1 stud wide and tall, pointing up (+Y), base at the bottom.
function Geo.unitShard(): MeshPart
	return Geo.cached("UnitShard", function(b)
		b.flat = true
		b:lathe(
			{ Vector2.new(0.001, -0.5), Vector2.new(0.5, -0.38), Vector2.new(0.36, 0.18), Vector2.new(0.001, 0.5) },
			5
		)
	end, { collision = false })
end

-- Shapes that `Geo.dress` can build, by name. `build(builder, params)` builds around the origin at
-- roughly unit size (1 stud across); the spot's size scales it. `params` are the spot's attributes.
local shapes: { [string]: { build: (Builder, { [string]: any }) -> (), vertexColors: boolean } } = {}

function Geo.register(name: string, build: (Builder, { [string]: any }) -> (), opts: { vertexColors: boolean? }?)
	shapes[name] = { build = build, vertexColors = opts ~= nil and opts.vertexColors == true }
end

local function paramKey(name: string, params: { [string]: any }): string
	local keys = {}
	for key in params do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = { name }
	for _, key in keys do
		table.insert(parts, `{key}={tostring(params[key])}`)
	end
	return table.concat(parts, "|")
end

-- Client: gives every BasePart under `root` that has a `GeoShape` attribute its generated mesh, sized
-- to the part. The part stays as an invisible collision/hit proxy. Returns how many were dressed.
function Geo.dress(root: Instance): number
	local count, failed = 0, 0
	local candidates = root:GetDescendants()
	table.insert(candidates, root)
	for _, spot in candidates do
		local shape = spot:GetAttribute("GeoShape")
		if type(shape) == "string" and spot:IsA("BasePart") and not spot:GetAttribute("GeoDressed") then
			local entry = shapes[shape]
			if not entry then
				warn(`Geo.dress: no shape registered as '{shape}' ({spot:GetFullName()})`)
				continue
			end
			local params: { [string]: any } = spot:GetAttributes()
			params.GeoShape, params.GeoDressed = nil, nil
			local ok, template = pcall(Geo.cached, paramKey(shape, params), function(b)
				entry.build(b, params)
			end, { collision = false })
			if not ok then
				-- Out of mesh budget (or a bad build): leave the spot visible as its plain part.
				failed += 1
				if failed == 1 then
					warn(`Geo.dress: '{shape}' not built, spots stay as plain parts: {template}`)
				end
				continue
			end
			local mesh = template:Clone()
			mesh.Name = spot.Name .. "Mesh"
			mesh.Size = spot.Size
			mesh.CFrame = spot.CFrame
			mesh.Material = spot.Material
			mesh.Color = if entry.vertexColors then Color3.new(1, 1, 1) else spot.Color
			mesh.CastShadow = spot.CastShadow
			mesh.Parent = spot
			spot.Transparency = 1
			spot:SetAttribute("GeoDressed", true)
			count += 1
		end
	end
	return count
end

return Geo
