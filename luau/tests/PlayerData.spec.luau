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

	t.test("a final save with unserializable data still releases the lock and keeps the last good save", function()
		local store = PlayerData.memoryStore()
		local a = session(store, "A")
		t.ok(a:load())
		a.data.Coins = 5
		t.ok(a:save())
		a.data.Coins = math.huge
		local ok, err = a:save(true)
		t.eq(ok, false)
		t.ok(string.find(err, "lock released", 1, true), err)
		t.eq(a.released, true)
		t.eq(store.values.Player_1.lock, nil)
		t.eq(store.values.Player_1.data.Coins, 5)
		local b = session(store, "B")
		t.ok(b:load(), "another server can load immediately")
		t.eq(b.data.Coins, 5)
	end)

	local function migrating(store, migrate)
		return Session.new(store, "Player_1", template, { jobId = "A", retries = 3, retryDelay = 0, migrate = migrate })
	end

	t.test("invalid saved data is refused once, untouched, when no recovery is configured", function()
		local store = PlayerData.memoryStore()
		local calls, original = 0, store.UpdateAsync
		function store.UpdateAsync(self, key, fn)
			calls += 1
			return original(self, key, fn)
		end
		store.values.Player_1 = { data = { Coins = 5, Inventory = { [1] = "Sword", [3] = "Shield" } } }
		local ok, err = migrating(store, nil):load()
		t.eq(ok, false)
		t.ok(string.find(err, "onInvalidData", 1, true), err)
		t.eq(calls, 1, "a permanent problem is not retried")
		t.eq(store.values.Player_1.data.Inventory[3], "Shield", "original kept")
		t.eq(store.values.Player_1.lock, nil, "no lock left behind")
		t.eq(store.values.Player_1.backups, nil)
	end)

	t.test("onInvalidData recovers invalid saved data and backs up the original", function()
		local store = PlayerData.memoryStore()
		store.values.Player_1 = { data = { Coins = 5, Inventory = { [1] = "Sword", [3] = "Shield" } }, Other = "kept" }
		local seen
		local a = migrating(store, function(data, reason)
			seen = reason
			return PlayerData.sanitize(data)
		end)
		t.ok(a:load())
		t.ok(string.find(seen, "sparse", 1, true), seen)
		t.eq(a.data.Coins, 5)
		t.eq(#a.data.Inventory, 2)
		t.eq(a.data.Inventory[2], "Shield")
		t.eq(a.data.Settings.Music, true, "template reconciled")
		local record = store.values.Player_1
		t.eq(record.Other, "kept")
		t.eq(#record.backups, 1)
		t.eq(record.backups[1].data.Inventory[3], "Shield", "original preserved in backup")
		t.ok(string.find(record.backups[1].reason, "sparse", 1, true))
		t.ok(a:save(true))
		t.eq(#store.values.Player_1.backups, 1, "saves keep backups")
		t.ok(migrating(store, nil):load(), "recovered data loads without a callback")
	end)

	t.test("onInvalidData that declines, errors, yields or returns invalid data leaves the record untouched", function()
		local cases: { () -> any } = {
			function()
				return nil
			end,
			function()
				error("boom")
			end,
			function()
				task.wait()
				return {}
			end,
			function()
				return { Coins = 0 / 0 }
			end,
			function()
				return "nope" :: any
			end,
		}
		for i, migrate in cases do
			local store = PlayerData.memoryStore()
			store.values.Player_1 = { data = { Coins = math.huge } }
			local ok, err = migrating(store, migrate):load()
			t.eq(ok, false, `case {i}`)
			t.ok(type(err) == "string", `case {i}`)
			t.eq(store.values.Player_1.data.Coins, math.huge, `case {i}: original kept`)
			t.eq(store.values.Player_1.lock, nil, `case {i}`)
			t.eq(store.values.Player_1.backups, nil, `case {i}`)
		end
	end)

	t.test("non-table saved data can be recovered, and a full backup list refuses instead of discarding", function()
		local store = PlayerData.memoryStore()
		store.values.Player_1 = { data = "corrupt" }
		local a = migrating(store, function()
			return { Coins = 1 }
		end)
		t.ok(a:load())
		t.eq(store.values.Player_1.backups[1].data, "corrupt")
		t.ok(a:save(true))
		local full = { data = { Coins = 0 / 0 }, backups = { {}, {}, {} } }
		store.values.Player_1 = full
		local ok, err = migrating(store, PlayerData.sanitize):load()
		t.eq(ok, false)
		t.ok(string.find(err, "manually", 1, true), err)
		t.eq(#store.values.Player_1.backups, 3)
	end)

	t.test("sanitize returns valid data and keeps everything it can", function()
		local mixed: any = { "drop" }
		mixed.Keep = 1
		local clean = PlayerData.sanitize({
			Coins = 0 / 0,
			Name = "ok",
			List = { [2] = "b", [5] = "c" },
			Mixed = mixed,
			Fn = function() end,
		})
		PlayerData.validate(clean)
		t.eq(clean.Coins, nil)
		t.eq(clean.Name, "ok")
		t.eq(clean.List[1], "b")
		t.eq(clean.List[2], "c")
		t.eq(clean.Mixed.Keep, 1)
		t.eq(clean.Fn, nil)
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
