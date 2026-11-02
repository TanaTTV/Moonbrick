--!strict
-- A full round loop on Kit.Round: players wait in the lobby, move to the arena when a round starts, and come
-- back for results. Tag parts "ArenaSpawn" and "LobbySpawn". Players who join mid-round wait in the lobby.
-- End a round early from game code with `controller:skip()` (last player standing, goal reached).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Kit = game:GetService("ServerScriptService").Kit
local DebugHooks = require(Kit.DebugHooks)
local Round = require(Kit.Round)
local Net = require(ReplicatedStorage.Kit.Net)

local ARENA, LOBBY = "ArenaSpawn", "LobbySpawn"
local DURATIONS = { Intermission = 10, Playing = 60, Results = 5 }

-- One player is enough to test alone in Studio; a real server waits for two.
local controller = Round.new({
	intermission = DURATIONS.Intermission,
	duration = DURATIONS.Playing,
	results = DURATIONS.Results,
	minPlayers = if RunService:IsStudio() then 1 else 2,
})
Net.declare("RoundState")

local playing: { [Player]: boolean } = {}
local nextSpawn = 0

local function moveTo(player: Player, tag: string): boolean
	local character = player.Character
	local spawns = CollectionService:GetTagged(tag)
	if not character or #spawns == 0 then
		if #spawns == 0 then
			warn(`Round: no part tagged {tag}`)
		end
		return false
	end
	nextSpawn += 1
	local spawn = spawns[nextSpawn % #spawns + 1]
	if not spawn:IsA("BasePart") then
		return false
	end
	character:PivotTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 4, 0))
	return true
end

local function startRound()
	for _, player in Players:GetPlayers() do
		playing[player] = moveTo(player, ARENA)
	end
end

local function endRound()
	for player in playing do
		moveTo(player, LOBBY)
	end
	table.clear(playing)
end

local function broadcast(state: string, remaining: number)
	Net.fireAll("RoundState", state, math.ceil(remaining), (DURATIONS :: any)[state] or 0)
end

local function changed(state: string)
	if state == "Playing" then
		startRound()
	elseif state == "Results" then
		endRound()
	end
end

task.spawn(function()
	local lastSecond = -1
	while true do
		local snapshot, moved = controller:step(#Players:GetPlayers())
		if moved then
			changed(snapshot.state)
		end
		local second = math.ceil(snapshot.remaining)
		if moved or second ~= lastSecond then
			lastSecond = second
			broadcast(snapshot.state, snapshot.remaining)
		end
		task.wait(0.25)
	end
end)

local function track(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait() -- after the engine's spawn placement
		moveTo(player, if playing[player] then ARENA else LOBBY)
	end)
end
for _, player in Players:GetPlayers() do
	track(player)
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(function(player)
	playing[player] = nil
end)

DebugHooks.register("Round", {
	state = function(): string
		local snapshot = controller:snapshot()
		return `{snapshot.state} {math.ceil(snapshot.remaining)}s round {snapshot.roundId}`
	end,
	skip = function(): boolean
		return controller:skip()
	end,
})
