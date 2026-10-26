--!nonstrict
--!nolint LocalUnused
--!nolint FunctionUnused
--!nolint UninitializedLocal
-- Minimal deterministic scheduler and isolated remote fixtures, not Roblox engine emulation.
-- Module splicing below supplies these locals and uses the mock globals before execution.
local task = {}
local function warn(...) end -- warnings are expected in provider-failure fixtures
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
			return true
		end,
		IsClient = function()
			return false
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
	},
	Players = {},
	ServerScriptService = { Kit = { PlayerData = "PlayerData" } },
}
local game = {
	JobId = "headless",
	GetService = function(_, name)
		return services[name]
	end,
}
-- Instances are property bags; only the classes below exist, so other classes fail like a broken build.
local CLASSES = { Folder = true, Part = true, Model = true, WedgePart = true, MeshPart = true }
local created = {}
local Instance
Instance = {
	new = function(className)
		if className == "BindableEvent" then
			return { Event = {} }
		end
		assert(CLASSES[className], "headless runner does not implement " .. className)
		local inst = {
			_type = "Instance",
			ClassName = className,
			GetFullName = function()
				return className
			end,
			IsA = function(_, requested)
				return requested == className
					or (requested == "BasePart" and className ~= "Folder" and className ~= "Model")
			end,
			IsDescendantOf = function(self, ancestor)
				local parent = self.Parent
				while parent do
					if parent == ancestor then
						return true
					end
					parent = parent.Parent
				end
				return false
			end,
			Clone = function(self)
				local copy = table.clone(self)
				copy.Parent, copy.destroyed = nil, nil
				table.insert(created, copy)
				return copy
			end,
			Destroy = function(self)
				self.Parent = nil
				self.destroyed = true
			end,
		}
		table.insert(created, inst)
		return inst
	end,
}
-- Values: translation-only CFrames and componentwise vectors, enough for layout maths, not rotation.
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
vectorMeta.__index = {
	Min = function(a, b)
		return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	end,
	Max = function(a, b)
		return Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	end,
	Lerp = function(a, b, t)
		return a + (b - a) * t
	end,
}
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
local Vector2 = {
	new = function(x, y)
		return { _type = "Vector2", X = x or 0, Y = y or 0 }
	end,
}
local CFrame = {}
local frameMeta = {}
function CFrame.new(position)
	local cf = setmetatable({ _type = "CFrame", Position = position or Vector3.zero }, frameMeta)
	cf.Rotation = cf
	return cf
end
frameMeta.__index = {
	Lerp = function(a, b, t)
		return CFrame.new(a.Position:Lerp(b.Position, t))
	end,
}
frameMeta.__mul = function(a, b)
	if b._type == "Vector3" then
		return a.Position + b
	end
	return CFrame.new(a.Position + b.Position)
end
CFrame.identity = CFrame.new()
function CFrame.Angles()
	return CFrame.identity
end
function CFrame.fromAxisAngle()
	return CFrame.identity
end
local colorMeta = {}
local Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ _type = "Color3", R = r, G = g, B = b }, colorMeta)
end
function Color3.fromRGB(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end
colorMeta.__index = {
	Lerp = function(a, b, t)
		return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
	end,
}
-- Enum.X.Y is the string "X.Y".
local Enum = setmetatable({}, {
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
-- "Allow Mesh & Image APIs".
local assets = { denied = false, builds = 0 }
local function editableMesh()
	local positions, faces = {}, {}
	local mesh = {}
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
	function mesh:Destroy() end
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
	return editableMesh()
end
function assets:CreateMeshPartAsync()
	task.wait(0.05)
	self.builds += 1
	return Instance.new("MeshPart")
end
services.AssetService = assets
local function typeof(value)
	return type(value) == "table" and value._type or type(value)
end
local workspace = Instance.new("Folder")

local function event()
	local listeners = {}
	return {
		Connect = function(_, fn)
			table.insert(listeners, fn)
		end,
		Fire = function(_, ...)
			for _, fn in listeners do
				task.spawn(fn, ...)
			end
		end,
	}
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
t.fixtures = { instances = created, assets = assets }
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
