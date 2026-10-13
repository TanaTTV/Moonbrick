--!strict
return function(env: any)
	local runtime, safety = env.runtime, env.safety
	local pd = env.factory(env.game, runtime.task, runtime.Instance)
	local memory = pd.memoryStore()
	local acquisitions, requests, commits, removes = 0, 0, 0, 0
	local budget = 100
	local service: any = {}
	local raw: any = {}
	function raw:UpdateAsync(key: string, transform: any): any
		requests += 1
		assert(key:match("^AcceptanceTest_"), "persistent Player/foreign key reached memory adapter")
		return memory:UpdateAsync(key, function(value: any)
			local nextValue = transform(value)
			if nextValue ~= nil then
				commits += 1
			end
			return nextValue
		end)
	end
	function raw:RemoveAsync(key: string)
		requests += 1
		removes += 1
		assert(key:match("^AcceptanceTest_"), "foreign key removed")
		memory.values[key] = nil
	end
	function service:GetDataStore(name: string): any
		assert(name == "MoonbrickAcceptance_v1", "unsafe store name")
		acquisitions += 1
		return raw
	end
	function service:GetRequestBudgetForRequestType(kind: string): number
		assert(kind == "UpdateAsync" or kind == "SetIncrementAsync", "unknown budget type")
		return budget
	end
	local context: any = { isServer = true, isStudio = true, placeId = 123, universeId = 456, confirmed = true }
	local config: any = { allowedPlaces = { [123] = 456 }, mode = "suite", runId = "" }
	local function expectRefusal(label: string, ctx: any, cfg: any)
		local before = acquisitions
		local reason = safety.refusal(ctx, cfg)
		assert(reason, "unsafe environment was accepted")
		local ok = pcall(function()
			safety.open(service, ctx, cfg, "Refuse", runtime)
		end)
		assert(not ok and acquisitions == before, "refusal acquired a store")
		print(`PASS refusal-{label}: DATASTORE ACCEPTANCE REFUSED: {reason}; no DataStore acquired`)
	end
	local missingConfirm = table.clone(context)
	missingConfirm.confirmed = nil
	expectRefusal("confirmation", missingConfirm, config)
	local missingAllowlist = table.clone(config)
	missingAllowlist.allowedPlaces = {}
	expectRefusal("allowlist", context, missingAllowlist)
	local unpublished = table.clone(context)
	unpublished.placeId = 0
	expectRefusal("unpublished", unpublished, config)
	local wrongUniverse = table.clone(context)
	wrongUniverse.universeId = 789
	expectRefusal("universe", wrongUniverse, config)
	local notStudio = table.clone(context)
	notStudio.isStudio = false
	expectRefusal("live-server", notStudio, config)
	local client = table.clone(context)
	client.isServer = false
	expectRefusal("client", client, config)
	local badRun = table.clone(config)
	badRun.runId = "foreign/key"
	expectRefusal("run-id", context, badRun)
	local function harness(runId: string): (any, any, () -> ())
		local store = safety.open(service, context, config, runId, runtime)
		local close: any = nil
		local h = env.scenarios.new({
			store = store,
			playerData = pd,
			runtime = runtime,
			factory = env.factory,
			lifecycle = env.lifecycle,
			services = env.services,
			game = env.game,
			safety = safety,
			runId = runId,
			jobId = "headless-" .. acquisitions,
			bindClose = function(fn: any)
				close = fn
			end,
		})
		return h, store, function()
			assert(close, "engine close not armed")
			close()
		end
	end
	local suite, store = harness("MemoryRun")
	suite:suite()
	assert(suite.passed == 7 and suite.failed == 0, "scenario suite failed")
	assert(next(memory.values) == nil and removes == 6, "suite left records")
	local before = requests
	for _, operation in { "UpdateAsync", "read", "remove" } do
		local ok = pcall(function()
			store[operation](store, "Player_123", function()
				return {}
			end)
		end)
		assert(not ok and requests == before, "foreign key reached raw store")
	end
	print("PASS foreign-key-rails: UpdateAsync/read/RemoveAsync refused before provider calls")
	local arm, _, close = harness("ShutdownRun")
	arm:armShutdown()
	close() -- Simulated engine boundary; invokes the shipped callback through the real arming code.
	assert(arm.failed == 0, "armed shutdown failed")
	local verify = harness("ShutdownRun")
	verify:verifyShutdown()
	assert(verify.passed == 2 and verify.failed == 0 and next(memory.values) == nil, "shutdown restart failed")
	local a = harness("TwoServer")
	local b = harness("TwoServer")
	local aDone, bDone = false, false
	runtime.spawn(function()
		a:contend("a")
		aDone = true
	end)
	runtime.spawn(function()
		b:contend("b")
		bDone = true
	end)
	for _ = 1, 100 do
		if aDone and bDone then
			break
		end
		runtime.wait(1)
	end
	assert(aDone and bDone and a.failed == 0 and b.failed == 0, "two-server coordinator failed")
	assert(next(memory.values) == nil, "two-server variant left keys")
	print("PASS two-server-workflow: both roles/coordination/cleanup passed against shared memory (not real servers)")
	local staleArm = harness("TimedStale")
	staleArm:armStale()
	local staleKey = safety.key("stale", "TimedStale")
	assert(os.time() - memory.values[staleKey].lock.time < 2, "timed fixture was backdated while arming")
	local tooEarly = harness("TimedStale")
	local log = runtime.log
	runtime.log = function(line: string)
		log("EXPECTED EARLY REFUSAL FIXTURE: " .. line)
	end
	tooEarly:verifyStale()
	runtime.log = log
	assert(tooEarly.failed == 1 and memory.values[staleKey].lock ~= nil, "early verification discarded fixture")
	-- Memory-only time fixture: no wall-clock delay, no live store access.
	memory.values[staleKey].lock.time = os.time() - 601
	local staleVerify = harness("TimedStale")
	staleVerify:verifyStale()
	assert(
		staleVerify.passed == 2 and staleVerify.failed == 0 and next(memory.values) == nil,
		"timed expiry workflow failed"
	)
	print(
		"PASS timed-expiry-workflow: arm did not backdate; early verification retained fixture; aged memory fixture recovered"
	)
	-- Budget waits are bounded; no request is sent while zero. The source Session backoff
	-- fixture above separately tests 0.05/0.10s waits after errors.
	local _, budgetStore = harness("ZeroBudget")
	budget = 0
	before = requests
	local ok = pcall(function()
		budgetStore:read(safety.key("budget", "ZeroBudget"))
	end)
	assert(not ok and requests == before, "zero-budget path sent a request")
	budget = 100
	print("PASS zero-budget: bounded 8-second wait refused without provider request")
	local _, capped = harness("RequestCap")
	local capKey = safety.key("budget", "RequestCap")
	for _ = 1, 40 do
		capped:read(capKey)
	end
	before = requests
	ok = pcall(function()
		capped:read(capKey)
	end)
	assert(not ok and requests == before, "regular request cap ineffective")
	for _ = 1, 10 do
		capped:remove(capKey)
		capped:read(capKey, true)
	end
	assert(capped:count() == 60, "cleanup reserve count wrong")
	before = requests
	ok = pcall(function()
		capped:remove(capKey)
	end)
	assert(not ok and requests == before, "60-request cap ineffective")
	print("PASS request-ceiling: regular=40, reserved cleanup=20, request 61 refused")
	local _, racing = harness("BudgetRace")
	local raceKey = safety.key("budget", "BudgetRace")
	for _ = 1, 39 do
		racing:read(raceKey)
	end
	budget = 0
	local finished, succeeded = 0, 0
	before = requests
	for _ = 1, 2 do
		runtime.spawn(function()
			local granted = pcall(function()
				racing:read(raceKey)
			end)
			if granted then
				succeeded += 1
			end
			finished += 1
		end)
	end
	budget = 100
	for _ = 1, 10 do
		if finished == 2 then
			break
		end
		runtime.wait(1)
	end
	assert(finished == 2 and succeeded == 1 and requests == before + 1, "budget wait raced past request cap")
	print("PASS budget-wait-race: two waiting workers shared one remaining allowance; excess worker refused")
	local cleaner, failedStore = harness("Leftovers")
	failedStore:UpdateAsync(safety.key("roundtrip", "Leftovers"), function()
		return { fixture = true }
	end)
	local remove = raw.RemoveAsync
	raw.RemoveAsync = function()
		error("injected RemoveAsync outage")
	end
	ok = pcall(function()
		cleaner:cleanup()
	end)
	assert(not ok and next(memory.values) ~= nil, "cleanup outage hid leftovers")
	raw.RemoveAsync = remove
	cleaner:cleanup()
	assert(next(memory.values) == nil, "cleanup retry left records")
	print("PASS leftover-reporting: failed RemoveAsync reported exact key; subsequent cleanup succeeded")
	assert(commits > 0, "no persistence logic executed")
end
