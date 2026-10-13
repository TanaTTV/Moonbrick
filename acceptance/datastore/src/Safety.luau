--!strict
local Safety = {}
Safety.storeName = "MoonbrickAcceptance_v1"
Safety.scenarios = { "roundtrip", "contention", "stale", "shutdown", "invalid", "budget", "coordinator" }

function Safety.refusal(context: any, config: any): string?
	if not context.isServer or not context.isStudio then
		return "Studio server only; live game servers and clients are refused"
	end
	if context.placeId <= 0 or context.universeId <= 0 then
		return "publish a NEW private disposable experience first (PlaceId/GameId must be nonzero)"
	end
	if context.confirmed ~= true then
		return "manually set ServerScriptService.MoonbrickAcceptanceConfirmed = true"
	end
	if config.allowedPlaces[context.placeId] ~= context.universeId then
		return "place/universe ID pair is absent from Config.allowedPlaces (empty by default)"
	end
	if
		not table.find(
			{
				"suite",
				"shutdown-arm",
				"shutdown-verify",
				"stale-arm",
				"stale-verify",
				"contender-a",
				"contender-b",
				"cleanup",
			},
			config.mode
		)
	then
		return "unknown Config.mode"
	end
	if config.mode ~= "suite" and config.runId == "" then
		return "manual modes require an explicit shared Config.runId"
	end
	if config.runId ~= "" and (#config.runId > 12 or not config.runId:match("^[%w]+$")) then
		return "Config.runId must contain 1..12 ASCII letters/digits"
	end
	return nil
end

function Safety.key(scenario: string, runId: string): string
	assert(table.find(Safety.scenarios, scenario), "unknown acceptance scenario")
	assert(#runId >= 1 and #runId <= 12 and runId:match("^[%w]+$"), "unsafe run ID")
	local key = `AcceptanceTest_{scenario}_{runId}`
	assert(#key <= 50, "DataStore key exceeds 50 characters")
	return key
end

-- Acquire only AFTER checking the same gates inside this function. No name/key override.
function Safety.open(service: any, context: any, config: any, runId: string, runtime: any): any
	local reason = Safety.refusal(context, config)
	assert(reason == nil, reason)
	local permitted: { [string]: boolean } = {}
	for _, scenario in Safety.scenarios do
		permitted[Safety.key(scenario, runId)] = true
	end
	local raw = service:GetDataStore(Safety.storeName)
	local calls, regular, cleanup = 0, 0, 0
	local touched: { [string]: boolean } = {}
	local function request(key: string, kind: string, isCleanup: boolean?)
		assert(permitted[key] == true, "refusing foreign key: " .. tostring(key))
		-- 40 regular + 20 reserved cleanup requests; one process/run can never exceed 60.
		assert(calls < 60, "60-request safety ceiling reached")
		if isCleanup then
			assert(cleanup < 20, "cleanup request reserve exhausted")
		else
			assert(regular < 40, "40-request regular ceiling reached; cleanup reserved")
		end
		local waited = 0
		while service:GetRequestBudgetForRequestType(runtime.requestTypes[kind]) < 1 do
			assert(waited < 8, "request budget stayed at zero for 8 seconds; stop instead of flooding")
			runtime.wait(1)
			waited += 1
		end
		-- Budget waits yield: another worker may have consumed the allowance meanwhile.
		assert(calls < 60, "60-request safety ceiling reached")
		assert(if isCleanup then cleanup < 20 else regular < 40, "request allowance exhausted while waiting")
		calls += 1
		if isCleanup then
			cleanup += 1
		else
			regular += 1
		end
	end
	local store: any = {}
	function store:UpdateAsync(key: string, transform: any): any
		request(key, "update")
		touched[key] = true -- includes ambiguous failures after a provider commit
		return raw:UpdateAsync(key, transform)
	end
	function store:read(key: string, isCleanup: boolean?): any
		request(key, "update", isCleanup)
		local snapshot: any = nil
		-- Read-through UpdateAsync avoids GetAsync's local cache; nil cancels EVERY invocation.
		raw:UpdateAsync(key, function(value: any)
			snapshot = value
			return nil
		end)
		return snapshot
	end
	function store:remove(key: string)
		request(key, "remove", true)
		raw:RemoveAsync(key)
	end
	function store:budget(): number
		return service:GetRequestBudgetForRequestType(runtime.requestTypes.update)
	end
	function store:count(): number
		return calls
	end
	function store:touched(): { [string]: boolean }
		return table.clone(touched)
	end
	return store
end

return Safety
