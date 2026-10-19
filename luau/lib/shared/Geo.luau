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
-- facets. Runtime meshes don't save with the place or replicate: build them where they are seen (client
-- for effects; the server for world props that need collisions only replicates when Roblox supports it,
-- so verify in a playtest). Published games need Game Settings → Security → "Allow Mesh & Image APIs".
-- Approach adapted from RoClicks meshlab's lathe/tube/loft helpers (MIT); written for strict Luau here.
local AssetService = game:GetService("AssetService")

local Geo = {}

export type Builder = {
	mesh: EditableMesh,
	flat: boolean,
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
-- Faces wind counter-clockwise seen from the side the rows turn toward (outward for lathes).
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
			BuilderMethods.quad(self, ids[i][j], ids[i + 1][j], ids[i + 1][k], ids[i][k])
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
			table.insert(row, p + (side * math.cos(a) + up * math.sin(a)) * r)
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
		BuilderMethods.quad(self, a, d, cc, b)
	end
end

-- Extrudes a convex or simple outline (X, Z on the ground plane, counter-clockwise seen from above)
-- upward by `height`, with caps. Concave outlines cap correctly only if star-shaped around their centre.
function BuilderMethods.extrude(self: Internal, outline: { Vector2 }, height: number, cf: CFrame?)
	local frame = cf or CFrame.identity
	local n = #outline
	assert(n >= 3, "Geo.extrude needs at least three outline points")
	local centre = Vector2.zero
	for _, p in outline do
		centre += p / n
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
		BuilderMethods.quad(self, a, b, c, d)
	end
	local cb = BuilderMethods.vertex(self, frame * Vector3.new(centre.X, 0, centre.Y))
	local ct = BuilderMethods.vertex(self, frame * Vector3.new(centre.X, height, centre.Y))
	for i = 1, n do
		local j = i % n + 1
		BuilderMethods.tri(self, ct, top[j], top[i])
		BuilderMethods.tri(self, cb, bottom[i], bottom[j])
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

function BuilderMethods.count(self: Internal): number
	return self._faces
end

function Geo.new(): Builder
	local self = setmetatable({
		mesh = AssetService:CreateEditableMesh(),
		flat = false,
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

-- Turns a builder into a MeshPart, centred on its bounds (yields). Model space stays world space:
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
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
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
	fn(builder)
	return Geo.toPart(builder, opts)
end

local cache: { [string]: MeshPart } = {}

-- A template MeshPart built once per key; Clone() it for each use (clones share the mesh data).
function Geo.cached(key: string, fn: (Builder) -> (), opts: PartOptions?): MeshPart
	local template = cache[key]
	if not template then
		template = Geo.build(fn, opts)
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

return Geo
