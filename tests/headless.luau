--!nonstrict
--!nolint LocalUnused
--!nolint FunctionUnused
--!nolint UninitializedLocal
-- Minimal deterministic scheduler and isolated remote fixtures, not Roblox engine emulation.
-- Module splicing below supplies these locals and uses the mock globals before execution.
local task = {}
local warnings = {}
local function warn(...) -- warnings are expected in provider-failure fixtures
	table.insert(warnings, table.concat({ tostring((...)) }, " "))
end
local queue = {}
local workerErrors = {}
local now = 0
local function resume(thread, ...)
	local result = table.pack(coroutine.resume(thread, ...))
	if not result[1] then
		table.insert(workerErrors, tostring(result[2]))
	elseif coroutine.status(thread) ~= "dead" then
		table.insert(queue, { thread = thread, at = now + (result[2] or 0.01) })
	end
end
function task.wait(delay)
	return coroutine.yield(delay or 0.01)
end
function task.spawn(fn, ...)
	resume(coroutine.create(fn), ...)
end
function task.delay(delay, fn, ...)
	local args = table.pack(...)
	table.insert(queue, {
		thread = coroutine.create(function()
			fn(table.unpack(args, 1, args.n))
		end),
		at = now + delay,
	})
end
local function signal()
	local listeners = {}
	local s = {}
	function s:Connect(fn)
		local connection = { Connected = true }
		local entry = { fn = fn, connection = connection }
		function connection:Disconnect()
			connection.Connected = false
			local index = table.find(listeners, entry)
			if index then
				table.remove(listeners, index)
			end
		end
		table.insert(listeners, entry)
		return connection
	end
	function s:Once(fn)
		local connection
		connection = s:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function s:Wait()
		local fired = false
		s:Once(function()
			fired = true
		end)
		while not fired do
			task.wait()
		end
	end
	function s:Fire(...)
		for _, entry in table.clone(listeners) do
			task.spawn(entry.fn, ...)
		end
	end
	return s
end
local runtime = { client = false }
local sequence = 0
local services = {
	DataStoreService = {},
	HttpService = {
		GenerateGUID = function()
			sequence += 1
			return "test-guid-" .. sequence
		end,
	},
	RunService = {
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return not runtime.client
		end,
		IsClient = function()
			return runtime.client
		end,
		IsRunning = function()
			return true
		end,
		-- Frame signals for the creative Scheduler; tests drive it with Scheduler.advance.
		Heartbeat = {
			Connect = function()
				return { Disconnect = function() end }
			end,
		},
		PreSimulation = {
			Connect = function()
				return { Disconnect = function() end }
			end,
		},
		BindToRenderStep = function(self, name, _, fn)
			self.bound = self.bound or {}
			self.bound[name] = fn
		end,
		UnbindFromRenderStep = function(self, name)
			self.bound = self.bound or {}
			self.bound[name] = nil
		end,
		RenderStepped = {
			Wait = function()
				task.wait()
			end,
		},
	},
	Players = {},
	ServerScriptService = { Kit = { PlayerData = "PlayerData" } },
	Debris = { AddItem = function() end },
	LogService = {
		GetLogHistory = function()
			return {}
		end,
	},
}
local game = {
	JobId = "headless",
	Loaded = signal(),
	loaded = true,
	GetService = function(_, name)
		local service = services[name]
		if service == nil and name == "Nonexistent" then
			error("not a service")
		end
		return service
	end,
	FindFirstChild = function(_, name)
		local service = services[name]
		return if type(service) == "table" and service._type == "Instance" then service else nil
	end,
	IsLoaded = function(self)
		return self.loaded
	end,
}
-- Instances are property bags; only the classes below exist, so other classes fail like a broken build.
local PARTS = { Part = true, WedgePart = true, MeshPart = true }
local GUI = { Frame = true, TextLabel = true, TextButton = true, ScrollingFrame = true }
local CLASSES = {
	Folder = true,
	Model = true,
	Humanoid = true,
	Motor6D = true,
	WeldConstraint = true,
	ParticleEmitter = true,
	PointLight = true,
	Sound = true,
	SoundGroup = true,
	Atmosphere = true,
	Sky = true,
	ColorCorrectionEffect = true,
	BloomEffect = true,
	SunRaysEffect = true,
	UICorner = true,
	UIStroke = true,
	UIGradient = true,
	UIPadding = true,
	UIListLayout = true,
	UIGridLayout = true,
	UIScale = true,
	UISizeConstraint = true,
	UIAspectRatioConstraint = true,
	ScreenGui = true,
}
for class in PARTS do
	CLASSES[class] = true
end
for class in GUI do
	CLASSES[class] = true
end
-- Created on first use, like the engine's: a bag only pays for the signals a test touches.
local SIGNALS = {
	Activated = true,
	ChildAdded = true,
	Connected = false,
	DescendantAdded = true,
	Destroying = true,
	Ended = true,
	Loaded = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseEnter = true,
	MouseLeave = true,
	SelectionGained = true,
	SelectionLost = true,
	Touched = true,
}
local created = {}
local Instance
local instanceMethods = {}
local instanceMeta = {}
instanceMeta.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "Position" and PARTS[rawget(self, "ClassName")] then
		local cf = rawget(self, "CFrame")
		return cf and cf.Position
	end
	local method = instanceMethods[key]
	if method then
		return method
	end
	if SIGNALS[key] then
		local s = signal()
		rawset(self, key, s)
		return s
	end
	return nil
end
local function setParent(self, parent)
	local old = rawget(self, "_parent")
	if old then
		local list = rawget(old, "_children")
		local index = table.find(list, self)
		if index then
			table.remove(list, index)
		end
	end
	rawset(self, "_parent", parent)
	if parent then
		table.insert(rawget(parent, "_children"), self)
		parent.ChildAdded:Fire(self)
		local ancestor = parent
		while ancestor do
			ancestor.DescendantAdded:Fire(self)
			for _, inst in instanceMethods.GetDescendants(self) do
				ancestor.DescendantAdded:Fire(inst)
			end
			ancestor = rawget(ancestor, "_parent")
		end
	end
end
instanceMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
	else
		rawset(self, key, value)
	end
end
function instanceMethods.GetFullName(self)
	return self.Name
end
function instanceMethods.IsA(self, requested)
	local class = self.ClassName
	return requested == class
		or (requested == "BasePart" and PARTS[class] == true)
		or (requested == "GuiObject" and GUI[class] == true)
		or (requested == "GuiButton" and class == "TextButton")
		or (requested == "Light" and class == "PointLight")
end
function instanceMethods.IsDescendantOf(self, ancestor)
	local parent = self.Parent
	while parent do
		if parent == ancestor then
			return true
		end
		parent = parent.Parent
	end
	return false
end
function instanceMethods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end
function instanceMethods.GetDescendants(self)
	local out = {}
	for _, child in rawget(self, "_children") do
		table.insert(out, child)
		for _, inst in instanceMethods.GetDescendants(child) do
			table.insert(out, inst)
		end
	end
	return out
end
function instanceMethods.FindFirstChild(self, name, recursive)
	for _, child in (if recursive then instanceMethods.GetDescendants(self) else rawget(self, "_children")) do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function instanceMethods.WaitForChild(self, name)
	return instanceMethods.FindFirstChild(self, name)
end
function instanceMethods.FindFirstChildOfClass(self, class)
	for _, child in rawget(self, "_children") do
		if child.ClassName == class then
			return child
		end
	end
	return nil
end
function instanceMethods.FindFirstChildWhichIsA(self, class, recursive)
	for _, child in (if recursive then instanceMethods.GetDescendants(self) else rawget(self, "_children")) do
		if child:IsA(class) then
			return child
		end
	end
	return nil
end
function instanceMethods.FindFirstAncestorOfClass(self, class)
	local parent = self.Parent
	while parent and parent.ClassName ~= class do
		parent = parent.Parent
	end
	return parent
end
function instanceMethods.GetAttribute(self, name)
	return rawget(self, "_attributes")[name]
end
function instanceMethods.GetAttributes(self)
	return table.clone(rawget(self, "_attributes"))
end
function instanceMethods.SetAttribute(self, name, value)
	rawget(self, "_attributes")[name] = value
	local changed = rawget(self, "_attributeSignals")[name]
	if changed then
		changed:Fire()
	end
end
function instanceMethods.GetAttributeChangedSignal(self, name)
	local signals = rawget(self, "_attributeSignals")
	signals[name] = signals[name] or signal()
	return signals[name]
end
function instanceMethods.GetPropertyChangedSignal()
	return signal()
end
function instanceMethods.PivotTo(self, cf)
	rawset(self, "CFrame", cf)
end
function instanceMethods.GetPivot(self)
	return rawget(self, "CFrame") or CFrame.identity
end
function instanceMethods.ClearAllChildren(self)
	for _, child in self:GetChildren() do
		child:Destroy()
	end
end
function instanceMethods.Clear() end
function instanceMethods.Emit() end
function instanceMethods.Play(self)
	rawset(self, "Playing", true)
end
function instanceMethods.Clone(self)
	local copy = table.clone(self)
	rawset(copy, "_parent", nil)
	rawset(copy, "destroyed", nil)
	rawset(copy, "_children", {})
	rawset(copy, "_attributes", table.clone(rawget(self, "_attributes")))
	rawset(copy, "_attributeSignals", {})
	for key in SIGNALS do
		rawset(copy, key, nil)
	end
	table.insert(created, copy)
	for _, child in rawget(self, "_children") do
		child:Clone().Parent = copy
	end
	return copy
end
function instanceMethods.Destroy(self)
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.Destroying:Fire()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
end
Instance = {
	new = function(className)
		if className == "BindableEvent" then
			local event = signal()
			return {
				Event = event,
				Fire = function(_, ...)
					event:Fire(...)
				end,
				Destroy = function() end,
			}
		end
		assert(CLASSES[className], "headless runner does not implement " .. className)
		local inst = setmetatable({
			_type = "Instance",
			ClassName = className,
			Name = className,
			_children = {},
			_attributes = {},
			_attributeSignals = {},
		}, instanceMeta)
		table.insert(created, inst)
		return inst
	end,
}
-- Values: real rigid CFrames and componentwise vectors, enough for layout maths.
local Vector3 = {}
local vectorMeta = {}
function Vector3.new(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return setmetatable(
		{ _type = "Vector3", X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) },
		vectorMeta
	)
end
local function lift(v)
	return if type(v) == "number" then Vector3.new(v, v, v) else v
end
local vectorMethods = {
	Min = function(a, b)
		return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	end,
	Max = function(a, b)
		return Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	end,
	Lerp = function(a, b, t)
		return a + (b - a) * t
	end,
	Dot = function(a, b)
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z
	end,
	Cross = function(a, b)
		return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
	end,
}
vectorMeta.__index = function(self, key)
	if key == "Unit" then
		return self / self.Magnitude
	end
	return vectorMethods[key]
end
vectorMeta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
vectorMeta.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vectorMeta.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
vectorMeta.__mul = function(a, b)
	a, b = lift(a), lift(b)
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
vectorMeta.__div = function(a, b)
	b = lift(b)
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
vectorMeta.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
Vector3.zero, Vector3.one = Vector3.new(0, 0, 0), Vector3.new(1, 1, 1)
Vector3.xAxis, Vector3.yAxis, Vector3.zAxis = Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)
local Vector2 = {}
local vector2Meta = {}
function Vector2.new(x, y)
	x, y = x or 0, y or 0
	return setmetatable({ _type = "Vector2", X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }, vector2Meta)
end
vector2Meta.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
vector2Meta.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
vector2Meta.__mul = function(a, b)
	return if type(a) == "number" then Vector2.new(a * b.X, a * b.Y) else Vector2.new(a.X * b, a.Y * b)
end
vector2Meta.__div = function(a, b)
	return Vector2.new(a.X / b, a.Y / b)
end
vector2Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2.zero, Vector2.one = Vector2.new(0, 0), Vector2.new(1, 1)
local UDim = {
	new = function(scale, offset)
		return { _type = "UDim", Scale = scale or 0, Offset = offset or 0 }
	end,
}
local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then
		return { _type = "UDim2", X = xs, Y = xo }
	end
	return { _type = "UDim2", X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
local NumberRange = {
	new = function(min, max)
		return { _type = "NumberRange", Min = min, Max = max or min }
	end,
}
local function sequenceType(kind)
	return {
		new = function(a, b)
			-- A number or colour (constant), two colours, or a keypoint list.
			local keypoints = if type(a) == "table" and a._type == nil
				then a
				else { { Time = 0, Value = a }, { Time = 1, Value = b or a } }
			return { _type = kind, Keypoints = keypoints }
		end,
	}
end
local NumberSequence, ColorSequence = sequenceType("NumberSequence"), sequenceType("ColorSequence")
local NumberSequenceKeypoint = {
	new = function(time, value, envelope)
		return { Time = time, Value = value, Envelope = envelope or 0 }
	end,
}
local ColorSequenceKeypoint = {
	new = function(time, value)
		return { Time = time, Value = value }
	end,
}
local TweenInfo = {
	new = function(time)
		return { Time = time }
	end,
}
local CFrame = {}
local frameMeta = {}
local IDENTITY = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function frame(position, r)
	return setmetatable({ _type = "CFrame", Position = position, r = r }, frameMeta)
end
local function rotate(r, v)
	return Vector3.new(
		r[1] * v.X + r[2] * v.Y + r[3] * v.Z,
		r[4] * v.X + r[5] * v.Y + r[6] * v.Z,
		r[7] * v.X + r[8] * v.Y + r[9] * v.Z
	)
end
local function multiply(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7],
		a[1] * b[2] + a[2] * b[5] + a[3] * b[8],
		a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7],
		a[4] * b[2] + a[5] * b[5] + a[6] * b[8],
		a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7],
		a[7] * b[2] + a[8] * b[5] + a[9] * b[8],
		a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end
local frameMethods = {}
function frameMethods.Inverse(self)
	local r = self.r
	local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	return frame(-rotate(t, self.Position), t)
end
function frameMethods.ToObjectSpace(self, other)
	return self:Inverse() * other
end
function frameMethods.Lerp(a, b, t)
	-- Component lerp, re-orthogonalised; enough for short test arcs.
	local r = {}
	for i = 1, 9 do
		r[i] = a.r[i] + (b.r[i] - a.r[i]) * t
	end
	local x = Vector3.new(r[1], r[4], r[7]).Unit
	local y = Vector3.new(r[2], r[5], r[8])
	local z = x:Cross(y).Unit
	y = z:Cross(x)
	return frame(a.Position:Lerp(b.Position, t), { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z })
end
frameMeta.__index = function(self, key)
	local r = rawget(self, "r")
	if key == "Rotation" then
		return frame(Vector3.zero, r)
	elseif key == "LookVector" then
		return Vector3.new(-r[3], -r[6], -r[9])
	elseif key == "UpVector" then
		return Vector3.new(r[2], r[5], r[8])
	elseif key == "RightVector" then
		return Vector3.new(r[1], r[4], r[7])
	end
	return frameMethods[key]
end
frameMeta.__mul = function(a, b)
	if b._type == "Vector3" then
		return a.Position + rotate(a.r, b)
	end
	return frame(a.Position + rotate(a.r, b.Position), multiply(a.r, b.r))
end
function CFrame.fromMatrix(position, x, y, z)
	z = z or x:Cross(y)
	return frame(position, { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z })
end
function CFrame.lookAt(position, target, up)
	local look = (target - position).Unit
	local right = look:Cross(up or Vector3.yAxis).Unit
	return CFrame.fromMatrix(position, right, right:Cross(look), -look)
end
function CFrame.new(x, y, z)
	if type(x) == "number" then
		return frame(Vector3.new(x, y, z), IDENTITY)
	elseif y then
		return CFrame.lookAt(x, y)
	end
	return frame(x or Vector3.zero, IDENTITY)
end
CFrame.identity = CFrame.new()
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local x, y, z =
		{ 1, 0, 0, 0, cx, -sx, 0, sx, cx }, { cy, 0, sy, 0, 1, 0, -sy, 0, cy }, { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return frame(Vector3.zero, multiply(multiply(x, y), z))
end
function CFrame.fromAxisAngle(axis, angle)
	local u, c, s = axis.Unit, math.cos(angle), math.sin(angle)
	local i = 1 - c
	return frame(Vector3.zero, {
		c + u.X * u.X * i,
		u.X * u.Y * i - u.Z * s,
		u.X * u.Z * i + u.Y * s,
		u.Y * u.X * i + u.Z * s,
		c + u.Y * u.Y * i,
		u.Y * u.Z * i - u.X * s,
		u.Z * u.X * i - u.Y * s,
		u.Z * u.Y * i + u.X * s,
		c + u.Z * u.Z * i,
	})
end
local colorMeta = {}
local Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ _type = "Color3", R = r or 0, G = g or 0, B = b or 0 }, colorMeta)
end
function Color3.fromRGB(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3.fromHex(hex)
	hex = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
colorMeta.__index = {
	Lerp = function(a, b, t)
		return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
	end,
	ToHex = function(c)
		return string.format("%02x%02x%02x", c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5)
	end,
}
colorMeta.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
-- Enum.X.Y is the string "X.Y".
local Enum = setmetatable({ RenderPriority = { Camera = { Value = 200 } } }, {
	__index = function(_, kind)
		return setmetatable({}, {
			__index = function(_, item)
				return kind .. "." .. item
			end,
		})
	end,
})
local Content = {
	fromObject = function(object)
		return object
	end,
}
-- EditableMesh stand-ins: async calls yield like the engine; `denied` mimics a game without
-- "Allow Mesh & Image APIs", `failBake`/`failPart` an async call that errors.
local assets = { denied = false, failBake = false, failPart = false, builds = 0, destroyed = 0, live = 0 }
local function editableMesh()
	local positions, faces = {}, {}
	local mesh = {}
	assets.live += 1
	function mesh:AddVertex(p)
		table.insert(positions, p)
		return #positions
	end
	function mesh:GetPosition(id)
		return positions[id]
	end
	function mesh:SetPosition(id, p)
		positions[id] = p
	end
	function mesh:GetVertices()
		local ids = {}
		for id in positions do
			table.insert(ids, id)
		end
		return ids
	end
	function mesh:AddTriangle(a, b, c)
		table.insert(faces, { a, b, c })
		return #faces
	end
	function mesh:GetFaces()
		local ids = {}
		for id in faces do
			table.insert(ids, id)
		end
		return ids
	end
	function mesh:GetFaceVertices(face)
		return faces[face]
	end
	function mesh:AddColor()
		return 1
	end
	function mesh:SetFaceColors() end
	function mesh:Destroy()
		assets.destroyed += 1
		assets.live -= 1
	end
	return mesh
end
function assets:CreateEditableMesh()
	if self.denied then
		error("EditableMesh APIs are not enabled for this experience")
	end
	return editableMesh()
end
function assets:CreateEditableMeshAsync()
	task.wait(0.05)
	if self.failBake then
		error("bake failed")
	end
	return editableMesh()
end
function assets:CreateMeshPartAsync()
	task.wait(0.05)
	if self.failPart then
		error("mesh part failed")
	end
	self.builds += 1
	return Instance.new("MeshPart")
end
services.AssetService = assets
local function typeof(value)
	return type(value) == "table" and value._type or type(value)
end
local workspace = Instance.new("Folder")
workspace.Name = "Workspace"
services.Workspace = workspace
services.Lighting = Instance.new("Folder")
services.SoundService = Instance.new("Folder")
services.GuiService = {
	GetGuiInset = function()
		return Vector2.new(0, 36), Vector2.zero
	end,
	GetPropertyChangedSignal = function()
		return signal()
	end,
}
services.UserInputService = { GamepadEnabled = false, InputChanged = signal() }
services.ContextActionService = {
	bound = {},
	BindAction = function(self, name, fn)
		self.bound[name] = fn
	end,
	UnbindAction = function(self, name)
		self.bound[name] = nil
	end,
}
-- Starting a tween cancels the one running on that instance, like the engine does per property.
local runningTweens = {}
services.TweenService = {
	Create = function(_, inst, info, props)
		local tween = { Completed = signal() }
		local state = "idle"
		function tween:Play()
			local running = runningTweens[inst]
			if running and running ~= tween then
				running:Cancel()
			end
			runningTweens[inst] = tween
			state = "playing"
			task.delay(info.Time, function()
				if state == "playing" then
					state = "done"
					for key, value in props do
						inst[key] = value
					end
					tween.Completed:Fire(Enum.PlaybackState.Completed)
				end
			end)
		end
		function tween:Cancel()
			if state == "playing" then
				state = "cancelled"
				tween.Completed:Fire(Enum.PlaybackState.Cancelled)
			end
		end
		return tween
	end,
}
local tagged = {}
local tagSignals = {}
services.CollectionService = {
	GetTagged = function(_, tag)
		return table.clone(tagged[tag] or {})
	end,
	GetInstanceAddedSignal = function(_, tag)
		tagSignals[tag] = tagSignals[tag] or signal()
		return tagSignals[tag]
	end,
	AddTag = function(self, inst, tag)
		tagged[tag] = tagged[tag] or {}
		table.insert(tagged[tag], inst)
		self:GetInstanceAddedSignal(tag):Fire(inst)
	end,
}

local function event()
	return signal()
end
local function environment()
	services.Players = {
		PlayerAdded = event(),
		PlayerRemoving = event(),
		GetPlayers = function()
			return {}
		end,
	}
	local close
	game.BindToClose = function(_, fn)
		close = fn
	end
	services.DataStoreService.GetDataStore = function()
		error("unexpected real DataStore access")
	end
	local player = {
		Name = "Test",
		UserId = 1,
		Parent = services.Players,
		FindFirstChild = function()
			return nil
		end,
		Kick = function(self)
			self.kicked = true
		end,
	}
	return services.Players, player, function()
		assert(close, "no shutdown handler")
		close()
	end
end

local modules, suites, loadPlayerData, loadNet
services.Players.PlayerRemoving = event()
-- MODULES --

local passed, failed = 0, 0
local t = {}
t.loadNet = loadNet
-- Engine stand-ins for creative specs that only run headless.
t.fixtures = {
	instances = created,
	assets = assets,
	services = services,
	game = game,
	runtime = runtime,
	warnings = warnings,
	frame = function(seconds)
		task.wait(seconds)
	end,
}
function t.eq(actual, expected, msg)
	assert(actual == expected, (msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
function t.ok(value, msg)
	assert(value, msg or "expected truthy")
end
function t.fails(fn, contains)
	local ok, err = pcall(fn)
	assert(not ok, "expected failure")
	assert(not contains or tostring(err):find(contains, 1, true), tostring(err))
end
function t.require(name)
	assert(modules[name], "unknown module " .. tostring(name))
	return modules[name]
end
function t.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
task.spawn(function()
	for _, suite in suites do
		suite(t)
	end
	-- Lifecycle tests use fresh module state and mock services; the shipped implementation runs unchanged.
	t.test("Studio defaults to memory without contacting any DataStore", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		data.start({ template = { Coins = 0 } })
		players.PlayerAdded:Fire(player)
		t.eq(data.get(player).Coins, 0)
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
		t.eq(data.get(player), nil)
		close()
	end)
	t.test("data updates roll back errors, yields and invalid values", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		data.start({ template = { Coins = 1 } })
		players.PlayerAdded:Fire(player)
		local original = data.get(player)
		t.eq(
			data.update(player, function(d)
				d.Coins = 999
				error("bad callback")
			end),
			false
		)
		t.eq(original.Coins, 1)
		t.eq(
			data.update(player, function(d)
				d.Coins = 999
				coroutine.yield()
				d.Coins = 888
			end),
			false
		)
		t.eq(original.Coins, 1)
		t.eq(
			data.update(player, function(d)
				d.Coins = math.huge
			end),
			false
		)
		t.eq(original.Coins, 1)
		t.eq(
			data.update(player, function(d)
				d.Coins += 5
			end),
			true
		)
		t.eq(data.get(player), original)
		t.eq(original.Coins, 6)
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
		close()
	end)
	t.test("failed leave saves remain available for shutdown retry", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		local store = data.memoryStore()
		data.start({ template = { Coins = 0 }, store = store })
		players.PlayerAdded:Fire(player)
		data.set(player, "Coins", 25)
		local original = store.UpdateAsync
		store.UpdateAsync = function()
			error("provider outage")
		end
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
		for _ = 1, 100 do
			task.wait()
		end
		t.eq(data.get(player), nil, "closing data is inaccessible")
		store.UpdateAsync = original
		close()
		t.eq(store.values.Player_1.data.Coins, 25)
		t.eq(store.values.Player_1.lock, nil)
	end)
	t.test("a lost player session rejects data access and kicks instead of allowing unsaved play", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		local store = data.memoryStore()
		data.start({ template = { Coins = 5 }, store = store })
		players.PlayerAdded:Fire(player)
		store.values.Player_1.lock = { job = "other", token = "other", time = os.time() }
		t.eq(data.save(player), false)
		t.eq(data.get(player), nil)
		t.eq(player.kicked, true)
		t.eq(store.values.Player_1.data.Coins, 5)
		close()
	end)
	t.test("shutdown waits for a player who leaves while still loading", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		local store = data.memoryStore()
		local original = store.UpdateAsync
		store.UpdateAsync = function(self, key, fn)
			task.wait(0.05)
			return original(self, key, fn)
		end
		data.start({ template = { Coins = 7 }, store = store })
		players.PlayerAdded:Fire(player)
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
		close()
		t.eq(store.values.Player_1.data.Coins, 7)
		t.eq(store.values.Player_1.lock, nil)
	end)
	t.test("failed leave-during-load release is retained and retried by shutdown", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		local store = data.memoryStore()
		local original, calls = store.UpdateAsync, 0
		store.UpdateAsync = function(self, key, fn)
			calls += 1
			if calls == 1 then
				task.wait(0.01)
				return original(self, key, fn)
			end
			if calls <= 4 then
				error("temporary release outage")
			end
			return original(self, key, fn)
		end
		data.start({ template = { Coins = 7 }, store = store })
		players.PlayerAdded:Fire(player)
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
		-- The first release exhausts three retries, then the provider recovers before shutdown.
		task.wait(10)
		t.ok(store.values.Player_1.lock ~= nil)
		close()
		t.eq(store.values.Player_1.data.Coins, 7)
		t.eq(store.values.Player_1.lock, nil)
	end)
	t.test("set/increment reject unsaveable values and a bad leave still releases the lock", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		local store = data.memoryStore()
		data.start({ template = { Coins = 0 }, store = store })
		players.PlayerAdded:Fire(player)
		t.eq(data.increment(player, "Coins", 4), 4)
		t.eq(data.increment(player, "Coins", math.huge), nil)
		data.set(player, "Coins", 0 / 0)
		t.eq(data.get(player).Coins, 4, "rejected writes leave data unchanged")
		t.ok(data.save(player))
		data.get(player).Coins = math.huge -- direct mutation bypasses set/increment
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
		t.eq(store.values.Player_1.lock, nil, "lock released despite invalid data")
		t.eq(store.values.Player_1.data.Coins, 4, "last good save kept")
		close()
	end)
	t.test("loaded listeners get the live data table and can disconnect", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		local store = data.memoryStore()
		data.start({ template = { Coins = 0 }, store = store })
		local calls, onceCalls = 0, 0
		data.loaded:Connect(function(_, loaded)
			calls += 1
			loaded.Coins += 50
		end)
		data.loaded:Once(function()
			onceCalls += 1
		end)
		local dropped = data.loaded:Connect(function()
			error("disconnected listener ran")
		end)
		dropped:Disconnect()
		t.eq(dropped.Connected, false)
		players.PlayerAdded:Fire(player)
		t.eq(data.get(player).Coins, 50, "listener changed the live table")
		t.ok(data.save(player))
		t.eq(store.values.Player_1.data.Coins, 50, "listener change saved")
		local second = { Name = "Second", UserId = 2, Parent = players, FindFirstChild = player.FindFirstChild }
		players.PlayerAdded:Fire(second)
		t.eq(calls, 2)
		t.eq(onceCalls, 1, "Once fires a single time")
		close()
	end)
	t.test("live data that becomes unsaveable kicks by default and keeps the last good save", function()
		local players, player, close = environment()
		local data = loadPlayerData()
		local store = data.memoryStore()
		data.start({ template = { Coins = 0 }, store = store })
		players.PlayerAdded:Fire(player)
		data.set(player, "Coins", 9)
		t.ok(data.save(player))
		data.get(player).Coins = 0 / 0 -- direct mutation bypasses set/increment
		t.eq(data.save(player), false)
		t.eq(player.kicked, true, "player kicked instead of playing on without saves")
		t.eq(store.values.Player_1.data.Coins, 9)
		close()

		players, player, close = environment()
		data = loadPlayerData()
		local reason
		data.start({
			template = { Coins = 0 },
			store = data.memoryStore(),
			onSaveInvalid = function(_, why)
				reason = why
			end,
		})
		players.PlayerAdded:Fire(player)
		data.get(player).Coins = math.huge
		t.eq(data.save(player), false)
		t.ok(reason and reason:find("non-finite", 1, true), tostring(reason))
		t.eq(player.kicked, nil, "callback replaces the default kick")
		close()
	end)
	t.test(
		"invalid saved data: default refuses without writing; onInvalidData recovers through the Player API",
		function()
			local players, player, close = environment()
			local data = loadPlayerData()
			local store = data.memoryStore()
			store.values.Player_1 = { data = { Coins = 0 / 0, Gems = 3 } }
			local reason
			data.start({
				template = { Coins = 0, Gems = 0 },
				store = store,
				onLoadFailed = function(_, why)
					reason = why
				end,
			})
			players.PlayerAdded:Fire(player)
			t.ok(reason and reason:find("onInvalidData", 1, true), tostring(reason))
			t.eq(data.wait(player, 1), nil)
			t.ok(store.values.Player_1.data.Coins ~= store.values.Player_1.data.Coins, "original NaN untouched")
			t.eq(store.values.Player_1.lock, nil)
			close()

			players, player, close = environment()
			data = loadPlayerData()
			data.start({ template = { Coins = 0, Gems = 0 }, store = store, onInvalidData = data.sanitize })
			players.PlayerAdded:Fire(player)
			t.eq(data.get(player).Coins, 0, "dropped value refilled from template")
			t.eq(data.get(player).Gems, 3)
			t.eq(#store.values.Player_1.backups, 1)
			player.Parent = nil
			players.PlayerRemoving:Fire(player)
			t.eq(store.values.Player_1.lock, nil)
			t.eq(store.values.Player_1.data.Gems, 3)
			close()
		end
	)
end)
for _ = 1, 10000 do
	if #queue == 0 then
		break
	end
	table.sort(queue, function(a, b)
		return a.at < b.at
	end)
	local item = table.remove(queue, 1)
	now = item.at
	resume(item.thread, 0.01)
end
assert(#queue == 0, "headless scheduler step limit exceeded")
for _, err in workerErrors do
	print("WORKER FAIL " .. err)
end
print(string.format("%d passed, %d failed, %d worker errors (headless)", passed, failed, #workerErrors))
assert(passed > 0 and failed == 0 and #workerErrors == 0, "headless tests failed")
