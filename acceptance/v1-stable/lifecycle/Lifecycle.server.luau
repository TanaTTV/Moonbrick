--!strict
-- Lifecycle fault harness for a new disposable local place (Studio Play only, memory only).
-- Every delay and error here is an INJECTED test fault, never a real Roblox provider outage.
-- Edit-mode attributes on this script apply from the first call: LoadDelay (s), SeedCoins (existing save).
-- At runtime: ServerStorage.FaultControl:Invoke("set", delay, failCount) / ("increment", n) / ("kick", msg)
-- / ("record", userId) / ("log").
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local PlayerData = require(game:GetService("ServerScriptService").Kit.PlayerData)

assert(RunService:IsStudio() and game.PlaceId == 0, "fault harness runs only in an unpublished local place")

local inner = PlayerData.memoryStore()
local fault = { delay = (script:GetAttribute("LoadDelay") :: number?) or 0, fail = 0, calls = 0 }
local log: { string } = {}

local function note(line: string)
	table.insert(log, line)
	print("FAULTSTORE " .. line)
end

local store = {}
function store.UpdateAsync(_self: any, key: string, transform: (any, any?) -> ...any): any
	fault.calls += 1
	local n = fault.calls
	local seed = script:GetAttribute("SeedCoins") :: number?
	if seed and inner.values[key] == nil then
		inner.values[key] = { data = { Coins = seed } } -- an existing save from an earlier session
		note(`seeded {key} Coins={seed}`)
	end
	if fault.delay > 0 then
		note(`#{n} {key} injected delay {fault.delay}s`)
		task.wait(fault.delay)
	end
	if fault.fail > 0 then
		fault.fail -= 1
		note(`#{n} {key} INJECTED outage`)
		error("INJECTED provider outage (test fault, not a real Roblox outage)")
	end
	local result = inner:UpdateAsync(key, transform)
	local record = inner.values[key]
	note(
		`#{n} {key} lock={if record and record.lock then "held" else "none"} Coins={record and record.data and record.data.Coins}`
	)
	return result
end

local control = Instance.new("BindableFunction")
control.Name = "FaultControl"
control.OnInvoke = function(action: string, a: any, b: any): any
	if action == "set" then
		fault.delay, fault.fail = a or 0, b or 0
		return true
	elseif action == "record" then
		local record = inner.values["Player_" .. tostring(a)]
		return if record then { lock = record.lock ~= nil, coins = record.data and record.data.Coins } else nil
	elseif action == "increment" then -- MCP code has its own require cache, so go through this script's PlayerData
		local player = Players:GetPlayers()[1]
		return player and PlayerData.increment(player, "Coins", a)
	elseif action == "kick" then
		local player = Players:GetPlayers()[1]
		if player then
			task.defer(player.Kick, player, a)
		end
		return player ~= nil
	elseif action == "log" then
		return table.concat(log, "\n")
	end
	error("unknown action " .. action)
end
control.Parent = ServerStorage

-- Measures how long the engine keeps the server alive after shutdown begins (does not delay shutdown).
game:BindToClose(function()
	local started = os.clock()
	task.spawn(function()
		while true do
			print(string.format("FAULTSTORE closing +%.1fs", os.clock() - started))
			task.wait(0.5)
		end
	end)
end)

PlayerData.start({ template = { Coins = 0 }, leaderstats = { "Coins" }, autosave = 10, store = store :: any })
