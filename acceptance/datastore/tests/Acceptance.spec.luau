--!strict
return function(env: any)
	local runtime, safety = env.runtime, env.safety
	local pd = env.factory(env.game, runtime.task, runtime.Instance)
	local memory = pd.memoryStore()
	local acquisitions, requests, commits, removes = 0, 0, 0, 0
	local budget = 100
	local listBudget = 100
	local listings = 0
	local storeNames: { any } = {}
	local listingFinished = true
	local listingFails = false
	local lastWrites: { [string]: number } = {}
	local cooldownWaits = 0
	local returned: any = nil
	local info = {
		GetUserIds = function()
			return { 77 }
		end,
		GetMetadata = function()
			return { fixture = "metadata" }
		end,
	}
	local function waitForKey(key: string)
		while lastWrites[key] and env.clock() - lastWrites[key] < 6 do
			cooldownWaits += 1
			runtime.wait(math.max(0.01, 6 - (env.clock() - lastWrites[key])))
		end
	end
	local service: any = {}
	local raw: any = {}
	function raw:UpdateAsync(key: string, transform: any): any
		requests += 1
		assert(key:match("^AcceptanceTest_"), "persistent Player/foreign key reached memory adapter")
		waitForKey(key)
		return memory:UpdateAsync(key, function(value: any)
			returned = table.pack(transform(value, info))
			local nextValue = returned[1]
			if nextValue ~= nil then
				assert(nextValue.__moonbrickAcceptance == key:match("_([^_]+)$"), "write missing run authorship")
				commits += 1
				lastWrites[key] = env.clock()
			end
			return nextValue
		end)
	end
	function raw:RemoveAsync(key: string)
		requests += 1
		removes += 1
		assert(key:match("^AcceptanceTest_"), "foreign key removed")
		waitForKey(key)
		lastWrites[key] = env.clock()
		memory.values[key] = nil
	end
	function service:ListDataStoresAsync(prefix: string, pageSize: number): any
		assert(prefix == "" and pageSize == 100, "listing must be one unfiltered page")
		requests += 1
		listings += 1
		assert(not listingFails, "injected listing outage")
		return {
			IsFinished = listingFinished,
			GetCurrentPage = function()
				return storeNames
			end,
			AdvanceToNextPageAsync = function()
				error("listing must not fetch a second page")
			end,
		}
	end
	function service:GetDataStore(name: string): any
		assert(name == "MoonbrickAcceptance_v1", "unsafe store name")
		acquisitions += 1
		return raw
	end
	function service:GetRequestBudgetForRequestType(kind: string): number
		if kind == "StandardList" then
			return listBudget
		end
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
	local function refuseListing(label: string, expected: string)
		local before, listed = acquisitions, listings
		local ok, why = pcall(safety.open, service, context, config, "ListRefuse", runtime)
		assert(not ok and tostring(why):find(expected, 1, true), tostring(why))
		assert(
			acquisitions == before and listings == listed + 1,
			"listing refusal acquired store or fetched extra pages"
		)
		print(`PASS listing-{label}: refused before acquiring a store ({tostring(why)})`)
	end
	storeNames = { { DataStoreName = safety.storeName }, { DataStoreName = "ProductionPlayerData" } }
	refuseListing("foreign-store", "another DataStore")
	storeNames = { { DataStoreName = safety.storeName } }
	listingFinished = false
	refuseListing("incomplete-page", "exceeds one page")
	listingFinished = true
	listingFails = true
	refuseListing("outage", "listing outage")
	listingFails = false
	listBudget = 0
	local listed, acquired = listings, acquisitions
	local listingOk = pcall(safety.open, service, context, config, "ListBudget", runtime)
	assert(not listingOk and listings == listed and acquisitions == acquired, "zero listing budget sent a request")
	listBudget = 100
	print("PASS listing-zero-budget: StandardList budget bounded refusal before provider request/store acquisition")
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
	assert(store:count() == 51 and cooldownWaits > 0, "listing/ownership checks not counted or cooldown untested")
	print("PASS cooldown-suite: six-second yielding writes, Player API load/shutdown/recovery; 51/60 requests")
	storeNames = {} -- the suite above also proves the acceptance-only universe is accepted
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
		runtime.wait(60) -- exercise the documented latest B startup, plus provider cooldowns
		b:contend("b")
		bDone = true
	end)
	for _ = 1, 300 do
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
	for _ = 1, 39 do -- opening listing is the first regular request
		capped:read(capKey)
	end
	before = requests
	ok = pcall(function()
		capped:read(capKey)
	end)
	assert(not ok and requests == before, "regular request cap ineffective")
	for _ = 1, 20 do
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
	for _ = 1, 38 do
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
	local owner, marked = harness("Authorship")
	local markedKey = safety.key("roundtrip", "Authorship")
	marked:UpdateAsync(markedKey, function(value: any, keyInfo: any)
		return value or { data = { Coins = 5 }, extra = "preserved" }, keyInfo:GetUserIds(), keyInfo:GetMetadata()
	end)
	assert(returned.n == 3 and returned[2][1] == 77 and returned[3].fixture == "metadata", "metadata returns lost")
	local session = pd.Session.new(marked, markedKey, { Coins = 0 }, { retries = 1 })
	assert(session:load())
	session.data.Coins = 6
	assert(session:save(true))
	assert(memory.values[markedKey].extra == "preserved", "PlayerData discarded unknown top-level fields")
	assert(memory.values[markedKey].__moonbrickAcceptance == "Authorship", "PlayerData lost marker")
	owner:cleanup()
	print("PASS authorship-write: marker on every commit; PlayerData preserves top-level fields and metadata returns")
	local foreign, foreignStore = harness("NotOurs")
	local foreignKey = safety.key("roundtrip", "NotOurs")
	local foreignRecords: { any } = {
		{ data = { Coins = 5 } },
		{ __moonbrickAcceptance = "DifferentRun", data = {} },
		"foreign",
	}
	for _, record in foreignRecords do
		memory.values[foreignKey] = record
		local removedBefore, committedBefore = removes, commits
		local cleaned, why = pcall(function()
			foreignStore:remove(foreignKey)
		end)
		assert(not cleaned and tostring(why):find("not ours", 1, true), "cleanup accepted foreign record")
		assert(removes == removedBefore and memory.values[foreignKey] == record, "foreign record removed")
		local wrote = pcall(function()
			foreignStore:UpdateAsync(foreignKey, function()
				return {}
			end)
		end)
		assert(not wrote and commits == committedBefore, "foreign record adopted by a write")
	end
	local reported = false
	runtime.log = function(line: string)
		if line:find(foreignKey, 1, true) and line:find("not ours", 1, true) then
			reported = true
		end
		log("EXPECTED FOREIGN FIXTURE: " .. line)
	end
	local cleaned = pcall(function()
		foreign:cleanup(true)
	end)
	runtime.log = log
	assert(not cleaned and reported, "not-ours leftover missing from report")
	memory.values[foreignKey] = nil -- memory-only foreign fixture disposal, never the guarded RemoveAsync
	print("PASS authorship-cleanup: missing/wrong/non-table markers refused; exact not-ours leftover reported")
	local mainServices = table.clone(env.services)
	mainServices.DataStoreService = service
	mainServices.ServerScriptService = {
		GetAttribute = function()
			return true
		end,
	}
	local closes: { any } = {}
	local mainGame = {
		PlaceId = 123,
		GameId = 456,
		JobId = "main-headless",
		GetService = function(_self: any, name: string)
			return mainServices[name]
		end,
		BindToClose = function(_self: any, fn: any)
			table.insert(closes, fn)
		end,
	}
	local function mainMode(mode: string, runId: string, expected: string)
		local lines = env.main({ allowedPlaces = { [123] = 456 }, mode = mode, runId = runId }, mainGame)
		local found = false
		for _, line in lines do
			assert(not line:match("^FAIL"), line)
			if line:find(expected, 1, true) then
				found = true
			end
		end
		assert(found, "Main did not complete " .. mode .. ": " .. table.concat(lines, "\n"))
		return lines
	end
	mainMode("suite", "", "7 passed, 0 failed") -- exercise HttpService-generated run ID
	mainMode("cleanup", "MainCleanup", "1 passed, 0 failed")
	mainMode("shutdown-arm", "MainShutdown", "ARMED shutdown")
	assert(#closes == 1, "Main failed to bind the engine wrapper for the captured library callback")
	closes[1]()
	mainMode("shutdown-verify", "MainShutdown", "2 passed, 0 failed")
	mainMode("stale-arm", "MainStale", "ARMED stale")
	memory.values[safety.key("stale", "MainStale")].lock.time = os.time() - 601
	mainMode("stale-verify", "MainStale", "2 passed, 0 failed")
	local mainADone, mainBDone = false, false
	runtime.spawn(function()
		mainMode("contender-a", "MainPair", "2 passed, 0 failed")
		mainADone = true
	end)
	runtime.spawn(function()
		mainMode("contender-b", "MainPair", "1 passed, 0 failed")
		mainBDone = true
	end)
	for _ = 1, 300 do
		if mainADone and mainBDone then
			break
		end
		runtime.wait(1)
	end
	assert(mainADone and mainBDone and next(memory.values) == nil, "Main allowed workflow left fixtures")
	storeNames = { { DataStoreName = "ProductionPlayerData" } }
	acquired = acquisitions
	mainMode("suite", "MainRefuse", "DATASTORE ACCEPTANCE REFUSED")
	assert(acquisitions == acquired, "Main foreign-universe refusal acquired store")
	storeNames = {}
	print(
		"PASS Main-allowed: actual entry script ran suite/generated ID, cleanup, shutdown/restart, stale, A/B; listing refusal"
	)
	assert(commits > 0, "no persistence logic executed")
end
