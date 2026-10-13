return function(t: any)
	local PlayerData = t.require(game:GetService("ServerScriptService").Kit.PlayerData)
	local Session = PlayerData.Session
	local template = { Coins = 0, Inventory = {}, Settings = { Music = true } }
	local fast = { retries = 1, retryDelay = 0, ignoreLocks = false }

	local function session(store, job: string)
		return Session.new(store, "Player_1", template, {
			jobId = job,
			retries = fast.retries,
			retryDelay = fast.retryDelay,
			ignoreLocks = fast.ignoreLocks,
		})
	end

	t.test("new player gets a copy of the template, not the template itself", function()
		local s = session(PlayerData.memoryStore(), "A")
		t.ok(s:load())
		t.eq(s.data.Coins, 0)
		table.insert(s.data.Inventory, "Sword")
		t.eq(#template.Inventory, 0, "template mutated")
	end)

	t.test("saved data round-trips and missing template keys are added", function()
		local store = PlayerData.memoryStore()
		store.values.Player_1 = { data = { Coins = 42 } } -- old save without Inventory/Settings
		local s = session(store, "A")
		t.ok(s:load())
		t.eq(s.data.Coins, 42)
		t.eq(type(s.data.Inventory), "table", "Inventory reconciled")
		t.eq(s.data.Settings.Music, true, "nested key reconciled")
	end)

	t.test("a second server cannot load data locked by a live server", function()
		local store = PlayerData.memoryStore()
		t.ok(session(store, "A"):load())
		local ok, err = session(store, "B"):load()
		t.eq(ok, false)
		t.ok(string.find(err, "locked", 1, true), err)
	end)

	t.test("after release, another server can load the saved data", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		a.data.Coins = 7
		t.ok(a:save(true))
		local b = session(store, "B")
		t.ok(b:load())
		t.eq(b.data.Coins, 7)
	end)

	t.test("a stale lock from a dead server is taken over", function()
		local store = PlayerData.memoryStore()
		store.values.Player_1 = { data = { Coins = 3 }, lock = { job = "dead", time = os.time() - 3600 } }
		local s = session(store, "B")
		t.ok(s:load())
		t.eq(s.data.Coins, 3)
	end)

	t.test("a server that lost its lock does not overwrite the new owner", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		store.values.Player_1.lock = { job = "B", time = os.time() } -- B took over
		store.values.Player_1.data.Coins = 100
		a.data.Coins = 1
		local ok = a:save(false)
		t.eq(ok, false)
		t.eq(store.values.Player_1.data.Coins, 100, "B's data kept")
		t.eq(a.released, true, "A stops saving")
	end)

	t.test("store errors are retried and then reported", function()
		local calls = 0
		local flaky = {
			UpdateAsync = function(_, _key, _fn)
				calls += 1
				error("DataStore request was throttled")
			end,
		}
		local s = Session.new(flaky, "Player_1", template, { jobId = "A", retries = 3, retryDelay = 0, ignoreLocks = false })
		local ok, err = s:load()
		t.eq(ok, false)
		t.eq(calls, 3)
		t.ok(string.find(err, "throttled", 1, true), err)
	end)
end
