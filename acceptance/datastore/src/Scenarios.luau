--!strict
local Scenarios = {}

function Scenarios.new(deps: any): any
	local store, pd, runtime = deps.store, deps.playerData, deps.runtime
	local sessions: { any } = {}
	local lifecycles: { any } = {}
	local function key(name: string): string
		return deps.safety.key(name, deps.runId)
	end
	local function session(name: string, job: string?, customStore: any?, options: any?): any
		local opts = options or { retries = 1, retryDelay = 0 }
		opts.jobId = job or "acceptance-session"
		local s = pd.Session.new(customStore or store, key(name), { Coins = 0, Gems = 0 }, opts)
		table.insert(sessions, s)
		return s
	end
	local function lifecycle(name: string, migrate: any?): any
		local adapter = deps.lifecycle.new(deps.factory, deps.services, runtime, store, key(name), migrate)
		table.insert(lifecycles, adapter)
		return adapter
	end
	local function requireOk(ok: boolean, reason: string?)
		assert(ok, reason or "operation failed")
	end
	local harness: any = { passed = 0, failed = 0 }
	function harness:check(name: string, fn: () -> string)
		local ok, detail = pcall(fn)
		if ok then
			self.passed += 1
		else
			self.failed += 1
		end
		runtime.log(`{if ok then "PASS" else "FAIL"} {name}: {tostring(detail)}`)
	end
	function harness:summary()
		runtime.log(`DATASTORE ACCEPTANCE: {self.passed} passed, {self.failed} failed`)
		runtime.log(`REQUESTS: {store:count()}/60 (includes listing, read-through UpdateAsync and cleanup)`)
	end
	function harness:cleanup(allKeys: boolean?): string
		-- Stop autosave loops and release any failed scenario's sessions before removing keys.
		for _, adapter in lifecycles do
			local ok, why = pcall(function()
				adapter:close()
			end)
			if not ok then
				runtime.log("cleanup close warning: " .. tostring(why))
			end
		end
		for _, s in sessions do
			if s.loaded and not s.released then
				local ok, why = s:save(true)
				if not ok then
					runtime.log("cleanup release warning: " .. tostring(why))
				end
			end
		end
		local targets = store:touched()
		if allKeys then
			for _, name in deps.safety.scenarios do
				targets[key(name)] = true
			end
		end
		local leftovers, removed = {}, 0
		for target in targets do
			local ok, why = pcall(function()
				if store:remove(target) then
					assert(store:read(target, true) == nil, "record still present")
				end
			end)
			if ok then
				removed += 1
			else
				table.insert(leftovers, target .. " (" .. tostring(why) .. ")")
			end
		end
		table.sort(leftovers)
		runtime.log("LEFTOVERS: " .. (if #leftovers == 0 then "none" else table.concat(leftovers, ", ")))
		assert(#leftovers == 0, "cleanup incomplete; use cleanup mode with run ID " .. deps.runId)
		return `{removed} keys absent; owned records removed and verified via uncached UpdateAsync`
	end
	function harness:roundtrip(): string
		local first = session("roundtrip")
		requireOk(first:load())
		first.data.Coins = 42
		requireOk(first:save(true))
		local fresh = session("roundtrip")
		requireOk(fresh:load())
		assert(fresh.token ~= first.token and fresh.data.Coins == 42, "fresh session did not restore Coins=42")
		requireOk(fresh:save(true))
		return "fresh token loaded Coins=42 after release"
	end
	function harness:contention(): string
		local first, second = session("contention", "same-job"), session("contention", "same-job")
		requireOk(first:load())
		local ok, why = second:load()
		assert(not ok and why and why:find("locked", 1, true), tostring(why))
		assert(first.token ~= second.token, "tokens collided")
		requireOk(first:save(true))
		requireOk(second:load())
		requireOk(second:save(true))
		return "second token refused while held; succeeds after release (same job ID)"
	end
	function harness:stale(): string
		store:UpdateAsync(key("stale"), function()
			return { data = { Coins = 3 }, lock = { job = "dead", token = "expired", time = os.time() - 601 } }
		end)
		local takeover = session("stale")
		requireOk(takeover:load())
		assert(takeover.data.Coins == 3, "takeover discarded data")
		requireOk(takeover:save(true))
		return "seeded 601-second-old lock taken over; fixed expiry=600s, no configurable timeout"
	end
	function harness:shutdown(): string
		local adapter = lifecycle("shutdown")
		assert(adapter.loaded, "failed shutdown fixture load")
		adapter.data.set(adapter.player, "Coins", 91)
		adapter:beginSave()
		adapter:close()
		assert(adapter:saveResult(), "in-flight save did not finish")
		local record = store:read(key("shutdown"))
		assert(record.data.Coins == 91 and record.lock == nil, "shutdown failed to flush/release")
		return "shipped BindToClose body waited for in-flight Player API save, flushed Coins=91, released lock; engine shutdown still manual"
	end
	function harness:invalid(): string
		-- The Engine DataStore API can persist infinity, which PlayerData rejects. Verify the
		-- provider retained the fixture; never mistake serialization normalization for recovery.
		store:UpdateAsync(key("invalid"), function()
			return { data = { Coins = math.huge, Gems = 3 } }
		end)
		local seeded = store:read(key("invalid"))
		assert(seeded.data.Coins == math.huge, "provider did not preserve invalid infinity fixture")
		local before = store:count()
		local refused = lifecycle("invalid")
		assert(refused.loaded == nil, "invalid saved data loaded without opt-in")
		assert(store:count() == before + 1, "permanent validation error retried")
		refused:close()
		local untouched = store:read(key("invalid"))
		assert(
			untouched.data.Coins == math.huge and untouched.lock == nil and untouched.backups == nil,
			"default refusal wrote"
		)
		local recovered = lifecycle("invalid", pd.sanitize)
		assert(recovered.loaded and recovered.loaded.Coins == 0 and recovered.loaded.Gems == 3, "sanitize failed")
		local record = store:read(key("invalid"))
		assert(#record.backups == 1 and record.backups[1].data.Coins == math.huge, "original not backed up")
		recovered:close()
		return "default refused once without writing; onInvalidData=sanitize recovered defaults/Gems and retained original backup"
	end
	function harness:budget(): string
		local before = store:budget()
		local calls, waits = 0, {}
		local retryTask: any = table.clone(runtime.task)
		retryTask.wait = function(delay: number?)
			table.insert(waits, delay or 0)
			return runtime.wait(delay)
		end
		local retryPD = deps.factory(deps.game, retryTask, runtime.Instance)
		local flaky: any = {}
		function flaky.UpdateAsync(_self: any, target: string, transform: any): any
			calls += 1
			if calls <= 2 then
				error("injected DataStore throttling (no provider request)")
			end
			return store:UpdateAsync(target, transform)
		end
		local retry = retryPD.Session.new(flaky, key("budget"), { Coins = 0 }, { retries = 3, retryDelay = 0.05 })
		table.insert(sessions, retry)
		requireOk(retry:load())
		assert(calls == 3 and #waits == 2 and waits[1] == 0.05 and waits[2] == 0.1, "retry backoff missing")
		requireOk(retry:save(true))
		return `UpdateAsync budget before={before}, after={store:budget()}; 2 injected throttles, waits=0.05s/0.10s, then success; real throttling unproven`
	end
	function harness:suite()
		-- A suite never clobbers leftovers from a prior run. Choose a fresh run ID or cleanup first.
		local ok, why = pcall(function()
			for _, name in deps.safety.scenarios do
				assert(store:read(key(name)) == nil, "run ID already exists: " .. key(name))
			end
		end)
		if not ok then
			self:check("preflight", function()
				error(tostring(why))
			end)
			self:summary()
			return
		end
		for _, name in { "roundtrip", "contention", "stale", "shutdown", "invalid", "budget" } do
			self:check(name, function()
				return self[name](self)
			end)
		end
		self:check("cleanup", function()
			return self:cleanup()
		end)
		self:summary()
	end
	function harness:armShutdown()
		assert(store:read(key("shutdown")) == nil, "shutdown key exists; cleanup or choose a fresh ID")
		local adapter = lifecycle("shutdown")
		assert(adapter.loaded, "failed shutdown load")
		adapter.data.set(adapter.player, "Coins", 91)
		-- This callback is registered with the REAL engine by Main, then invokes the shipped
		-- library's captured callback while its public save is in flight.
		deps.bindClose(function()
			self:check("engine-shutdown", function()
				adapter:beginSave()
				adapter:close()
				assert(adapter:saveResult(), "in-flight save did not finish")
				return "engine invoked shipped BindToClose body; restart in shutdown-verify mode"
			end)
			self:summary()
		end)
		runtime.log(
			"ARMED shutdown: Stop this server promptly; keep key for restart verification, runId=" .. deps.runId
		)
	end
	function harness:verifyShutdown()
		self:check("engine-shutdown-restart", function()
			local record = store:read(key("shutdown"))
			assert(
				record and record.data.Coins == 91 and record.lock == nil,
				"missing flush/release after engine shutdown"
			)
			local fresh = session("shutdown")
			requireOk(fresh:load())
			assert(fresh.data.Coins == 91, "restart lost shutdown data")
			requireOk(fresh:save(true))
			return "persisted Coins=91, no lock, fresh session restored data"
		end)
		-- Include the retained shutdown key even if verify failed before a write.
		self:check("cleanup", function()
			return self:cleanup(true)
		end)
		self:summary()
	end
	function harness:armStale()
		assert(store:read(key("stale")) == nil, "stale key exists; cleanup or choose a fresh ID")
		local holder = session("stale", "acceptance-expiring")
		requireOk(holder:load())
		-- Session API has no automatic heartbeat. Intentionally omit release/BindToClose to
		-- represent an abandoned server; no player is involved. The timestamp is NOT backdated.
		runtime.log(
			"ARMED stale: lock written now; Stop server, wait at least 601 seconds, then stale-verify with runId="
				.. deps.runId
		)
	end
	function harness:verifyStale()
		self:check("natural-lock-expiry", function()
			local record = store:read(key("stale"))
			assert(record and record.lock, "missing abandoned lock")
			local age = os.time() - record.lock.time
			assert(age >= 600, `lock is only {age}s old; wait until at least 601s after arming`)
			local takeover = session("stale", "acceptance-takeover")
			requireOk(takeover:load())
			requireOk(takeover:save(true))
			return `naturally aged {age}s lock taken over and released`
		end)
		if self.failed == 0 then
			self:check("cleanup", function()
				return self:cleanup()
			end)
		else
			runtime.log("LEFTOVERS: retained stale fixture; retry after 601s or cleanup with runId=" .. deps.runId)
		end
		self:summary()
	end
	local function coordinate(stage: string)
		store:UpdateAsync(key("coordinator"), function(record: any)
			record = record or {}
			record.stage = stage
			return record
		end)
	end
	local function awaitStage(stage: string)
		-- Ten polls, spaced by twice the ~6s per-key write cooldown: bounded 120s window.
		for _ = 1, 10 do
			local record = store:read(key("coordinator"))
			if record and record.stage == stage then
				return
			end
			runtime.wait(12)
		end
		error("coordinator timeout waiting for " .. stage .. "; stop both servers and cleanup")
	end
	function harness:contend(role: string)
		self:check("two-server-" .. role, function()
			if role == "a" then
				assert(
					store:read(key("coordinator")) == nil and store:read(key("contention")) == nil,
					"coordinator/run ID already exists"
				)
				local holder = session("contention", deps.jobId)
				requireOk(holder:load())
				holder.data.Coins = 77
				coordinate("holding")
				runtime.log("A HOLDING: start B within 60 seconds with same run ID (120-second polling window)")
				awaitStage("refused")
				requireOk(holder:save(true))
				coordinate("released")
				awaitStage("complete")
			else
				awaitStage("holding")
				local blocked = session("contention", deps.jobId)
				local ok, why = blocked:load()
				assert(not ok and why and why:find("locked", 1, true), "B must refuse live A lock: " .. tostring(why))
				runtime.log("B REFUSED live A lock")
				coordinate("refused")
				awaitStage("released")
				local fresh = session("contention", deps.jobId)
				requireOk(fresh:load())
				assert(fresh.data.Coins == 77, "B lost A's saved data")
				requireOk(fresh:save(true))
				coordinate("complete")
			end
			return "coordinator observed refusal, release and B load of Coins=77"
		end)
		if role == "a" and self.failed == 0 then
			self:check("cleanup", function()
				return self:cleanup()
			end)
		elseif self.failed > 0 then
			runtime.log("LEFTOVERS: manual cleanup required after BOTH servers stop, runId=" .. deps.runId)
		end
		self:summary()
	end
	return harness
end

return Scenarios
