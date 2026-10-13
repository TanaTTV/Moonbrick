-- Minimal deterministic scheduler. This is a store/session test, not Roblox engine emulation.
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
local sequence = 0
local services = {
	DataStoreService = {},
	HttpService = { GenerateGUID = function() sequence += 1; return "test-guid-" .. sequence end },
	RunService = { IsStudio = function() return true end, IsServer = function() return true end },
	Players = {},
	ServerScriptService = { Kit = { PlayerData = "PlayerData" } },
}
local game = { JobId = "headless", GetService = function(_, name) return services[name] end }
local Instance = { new = function(className)
	assert(className == "BindableEvent", "headless runner does not implement " .. className)
	return { Event = {} }
end }

local function event()
	local listeners = {}
	return {
		Connect = function(_, fn) table.insert(listeners, fn) end,
		Fire = function(_, ...) for _, fn in listeners do task.spawn(fn, ...) end end,
	}
end
local function environment()
	services.Players = { PlayerAdded = event(), PlayerRemoving = event(), GetPlayers = function() return {} end }
	local close
	game.BindToClose = function(_, fn) close = fn end
	services.DataStoreService.GetDataStore = function() error("unexpected real DataStore access") end
	local player = { Name = "Test", UserId = 1, Parent = services.Players, FindFirstChild = function() return nil end, Kick = function(self) self.kicked = true end }
	return services.Players, player, function() assert(close, "no shutdown handler"); close() end
end

-- MODULES --

local passed, failed = 0, 0
local t = {}
function t.eq(actual, expected, msg)
	assert(actual == expected, (msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
function t.ok(value, msg) assert(value, msg or "expected truthy") end
function t.fails(fn, contains)
	local ok, err = pcall(fn)
	assert(not ok, "expected failure")
	assert(not contains or tostring(err):find(contains, 1, true), tostring(err))
end
function t.require(name) assert(modules[name], "unknown module " .. tostring(name)); return modules[name] end
function t.test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed += 1 else failed += 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
task.spawn(function()
	for _, suite in suites do suite(t) end
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
		t.eq(data.update(player, function(d) d.Coins = 999; error("bad callback") end), false)
		t.eq(original.Coins, 1)
		t.eq(data.update(player, function(d) d.Coins = 999; coroutine.yield(); d.Coins = 888 end), false)
		t.eq(original.Coins, 1)
		t.eq(data.update(player, function(d) d.Coins = math.huge end), false)
		t.eq(original.Coins, 1)
		t.eq(data.update(player, function(d) d.Coins += 5 end), true)
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
		store.UpdateAsync = function() error("provider outage") end
		player.Parent = nil
		players.PlayerRemoving:Fire(player)
		for _ = 1, 100 do task.wait() end
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
		store.UpdateAsync = function(self, key, fn) task.wait(0.05); return original(self, key, fn) end
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
		store.UpdateAsync = function(self,key,fn)
			calls += 1
			if calls == 1 then task.wait(0.01); return original(self,key,fn) end
			if calls <= 4 then error("temporary release outage") end
			return original(self,key,fn)
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
end)
for _ = 1, 10000 do
	if #queue == 0 then break end
	table.sort(queue, function(a, b) return a.at < b.at end)
	local item = table.remove(queue, 1)
	now = item.at
	resume(item.thread, 0.01)
end
assert(#queue == 0, "headless scheduler step limit exceeded")
for _, err in workerErrors do print("WORKER FAIL " .. err) end
print(string.format("%d passed, %d failed, %d worker errors (headless)", passed, failed, #workerErrors))
assert(passed > 0 and failed == 0 and #workerErrors == 0, "headless tests failed")
