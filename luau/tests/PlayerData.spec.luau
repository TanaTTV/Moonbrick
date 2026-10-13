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
		local s =
			Session.new(flaky, "Player_1", template, { jobId = "A", retries = 3, retryDelay = 0, ignoreLocks = false })
		local ok, err = s:load()
		t.eq(ok, false)
		t.eq(calls, 3)
		t.ok(string.find(err, "throttled", 1, true), err)
	end)

	t.test("sessions in the same server still have distinct ownership", function()
		local store = PlayerData.memoryStore()
		t.ok(session(store, "same-job"):load())
		t.eq(session(store, "same-job"):load(), false)
	end)

	t.test("a missing lock cannot be recreated by an old session", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		store.values.Player_1.lock = nil
		store.values.Player_1.data.Coins = 100
		a.data.Coins = 1
		t.eq(a:save(), false)
		t.eq(store.values.Player_1.data.Coins, 100)
	end)

	t.test("same-job takeover fences the stale session by token", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		store.values.Player_1.lock.time = os.time() - 3600
		local b = session(store, "A")
		t.ok(b:load())
		b.data.Coins = 50
		t.ok(b:save())
		a.data.Coins = 1
		t.eq(a:save(), false)
		t.eq(store.values.Player_1.data.Coins, 50)
	end)

	t.test("repeated load cannot discard unsaved progress", function()
		local a = session(PlayerData.memoryStore(), "A")
		t.ok(a:load())
		a.data.Coins = 12
		t.eq(a:load(), false)
		t.eq(a.data.Coins, 12)
	end)

	t.test("UpdateAsync rerun uses its final committed result", function()
		local store = PlayerData.memoryStore()
		local original = store.UpdateAsync
		function store.UpdateAsync(self, key, fn)
			fn(nil) -- speculative callback is discarded by the service
			self.values[key] = { data = { Coins = 77 } }
			return original(self, key, fn)
		end
		local a = session(store, "A")
		t.ok(a:load())
		t.eq(a.data.Coins, 77)
	end)

	t.test("save snapshots stay stable when game data changes during a yielding write", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		a.data.Coins = 3
		local original = store.UpdateAsync
		function store.UpdateAsync(self, key, fn)
			a.data.Coins = 9
			task.wait()
			return original(self, key, fn)
		end
		t.ok(a:save())
		t.eq(store.values.Player_1.data.Coins, 3)
		t.eq(a.data.Coins, 9)
	end)

	t.test("autosave and release serialize across yielding store calls", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		local original = store.UpdateAsync
		local active, peak, done = 0, 0, 0
		function store.UpdateAsync(self, key, fn)
			active += 1
			peak = math.max(peak, active)
			task.wait()
			local value = original(self, key, fn)
			active -= 1
			return value
		end
		task.spawn(function()
			t.ok(a:save())
			done += 1
		end)
		task.spawn(function()
			t.ok(a:save(true))
			done += 1
		end)
		for _ = 1, 100 do
			if done == 2 then
				break
			end
			task.wait()
		end
		t.eq(done, 2, "save workers finished")
		t.eq(peak, 1, "one writer per session")
		t.eq(store.values.Player_1.lock, nil, "release is the final write")
		t.eq(a:save(), false, "cannot write after release")
	end)

	t.test("corrupt records are reported without replacing data", function()
		local store = PlayerData.memoryStore()
		store.values.Player_1 = { data = "corrupt" }
		local a = session(store, "A")
		t.eq(a:load(), false)
		t.eq(store.values.Player_1.data, "corrupt")
	end)
	t.test("false records cannot become empty template records", function()
		local store = PlayerData.memoryStore()
		store.values.Player_1 = false
		t.eq(session(store, "A"):load(), false)
		t.eq(store.values.Player_1, false)
	end)

	t.test("failed final saves remain retryable without allowing autosaves", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		local original = store.UpdateAsync
		store.UpdateAsync = function()
			error("temporary outage")
		end
		t.eq(a:save(true), false)
		t.eq(a:save(false), false)
		store.UpdateAsync = original
		t.ok(a:save(true))
		t.eq(store.values.Player_1.lock, nil)
	end)

	t.test("unserializable data is rejected before writing and the session stays usable", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		a.data.Coins = 0 / 0
		t.eq(a:save(), false)
		t.eq(store.values.Player_1.data.Coins, 0)
		a.data.Coins = 7
		t.ok(a:save())
	end)

	t.test("cycles, sparse arrays, mixed keys and Instances cannot silently lose data", function()
		local cycle = {}
		cycle.self = cycle
		t.fails(function()
			PlayerData.validate(cycle)
		end, "cycle")
		t.fails(function()
			PlayerData.validate({ [2] = "gap" })
		end, "sparse")
		local mixed: any = { "item" }
		mixed.Coins = 1
		t.fails(function()
			PlayerData.validate(mixed)
		end, "mixed")
		t.fails(function()
			PlayerData.validate({ Value = function() end })
		end, "unsupported")
	end)

	t.test("ambiguous successful load retry keeps the acquired token and latest committed data", function()
		local store = PlayerData.memoryStore()
		local original = store.UpdateAsync
		local calls = 0
		function store.UpdateAsync(self, key, fn)
			calls += 1
			local result = original(self, key, fn)
			if calls == 1 then
				self.values[key].data.Coins = 42
				error("response lost after commit")
			end
			return result
		end
		local a = Session.new(store, "Player_1", template, { jobId = "A", retries = 2, retryDelay = 0 })
		t.ok(a:load())
		t.eq(a.data.Coins, 42)
		t.eq(store.values.Player_1.lock.token, a.token)
	end)

	t.test("load and save preserve existing DataStore user IDs and metadata", function()
		local values = { data = { Coins = 3 } }
		local ids, metadata = { 123 }, { schema = "old" }
		local info = {
			GetUserIds = function()
				return ids
			end,
			GetMetadata = function()
				return metadata
			end,
		}
		local store = {
			UpdateAsync = function(_, _key, fn)
				local result, users, meta = fn(PlayerData.deepCopy(values), info)
				t.eq(users, ids)
				t.eq(meta, metadata)
				values = result
				return result
			end,
		}
		local a = session(store, "A")
		t.ok(a:load())
		t.ok(a:save())
		t.ok(a:save(true))
	end)
end
