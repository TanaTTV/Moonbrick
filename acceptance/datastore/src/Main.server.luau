--!strict
local Config = require(script.Parent.Config)
local Safety = require(script.Parent.Safety)
local context = {
	isServer = game:GetService("RunService"):IsServer(),
	isStudio = game:GetService("RunService"):IsStudio(),
	placeId = game.PlaceId,
	universeId = game.GameId,
	confirmed = game:GetService("ServerScriptService"):GetAttribute("MoonbrickAcceptanceConfirmed"),
}
local refusal = Safety.refusal(context, Config)
if refusal then
	warn("DATASTORE ACCEPTANCE REFUSED: " .. refusal .. "; no DataStore acquired")
	return
end

local Factory = require(script.Parent.PlayerDataFactory)
local Lifecycle = require(script.Parent.Lifecycle)
local Scenarios = require(script.Parent.Scenarios)
local service = game:GetService("DataStoreService")
local runId = if Config.runId ~= ""
	then Config.runId
	else game:GetService("HttpService"):GenerateGUID(false):gsub("-", ""):sub(1, 12)
local runtime = {
	task = task,
	Instance = Instance,
	wait = task.wait,
	spawn = task.spawn,
	log = print,
	requestTypes = {
		update = Enum.DataStoreRequestType.UpdateAsync,
		remove = Enum.DataStoreRequestType.SetIncrementAsync,
	},
}
local services = {
	DataStoreService = service,
	HttpService = game:GetService("HttpService"),
	RunService = game:GetService("RunService"),
	Players = game:GetService("Players"),
}
print(
	`DATASTORE ACCEPTANCE: mode={Config.mode}, place={game.PlaceId}, universe={game.GameId}, store={Safety.storeName}, runId={runId}`
)
local store = Safety.open(service, context, Config, runId, runtime)
local harness = Scenarios.new({
	store = store,
	playerData = Factory(game, task, Instance),
	runtime = runtime,
	factory = Factory,
	lifecycle = Lifecycle,
	services = services,
	game = game,
	safety = Safety,
	runId = runId,
	jobId = "studio-" .. game:GetService("HttpService"):GenerateGUID(false),
	bindClose = function(fn: () -> ())
		game:BindToClose(fn)
	end,
})
local ok, why = pcall(function()
	if Config.mode == "suite" then
		harness:suite()
	elseif Config.mode == "shutdown-arm" then
		harness:armShutdown()
	elseif Config.mode == "shutdown-verify" then
		harness:verifyShutdown()
	elseif Config.mode == "stale-arm" then
		harness:armStale()
	elseif Config.mode == "stale-verify" then
		harness:verifyStale()
	elseif Config.mode == "contender-a" then
		harness:contend("a")
	elseif Config.mode == "contender-b" then
		harness:contend("b")
	elseif Config.mode == "cleanup" then
		harness:check("cleanup", function()
			return harness:cleanup(true)
		end)
		harness:summary()
	end
end)
if not ok then
	warn("FAIL harness: " .. tostring(why))
	warn("LEFTOVERS: stop all servers; cleanup mode with runId=" .. runId)
	warn("DATASTORE ACCEPTANCE: 0 passed, 1 failed")
end
