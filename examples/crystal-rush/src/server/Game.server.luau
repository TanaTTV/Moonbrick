--!strict
local Players = game:GetService("Players")
local Kit = game:GetService("ServerScriptService").Kit
local Net = require(game:GetService("ReplicatedStorage").Kit.Net)
local PlayerData = require(Kit.PlayerData)
local Round = require(Kit.Round)
local Cooldown = require(Kit.Cooldown)
local Economy = require(Kit.Economy)
local DebugHooks = require(Kit.DebugHooks)
local Rules = require(script.Parent.Rules)

PlayerData.start({
	name = "MoonbrickExample_CrystalRush",
	template = { Coins = 0, Inventory = {} },
	leaderstats = { "Coins" },
})
local round = Round.new({ minPlayers = 1, intermission = 5, duration = 45, results = 5 })
local gate = Cooldown.new()
local crystals: { [string]: BasePart } = {}
local claimed: { [string]: boolean } = {}
local scores: { [Player]: number } = {}
local lastTimer = -1
Net.declare("CrystalState")
Net.declare("CrystalToast")

local function state(player: Player)
	local data = PlayerData.get(player)
	return round:snapshot(), { coins = if data then data.Coins else 0, caught = scores[player] or 0 }
end
local function send(player: Player)
	Net.fire(player, "CrystalState", state(player))
end
local function broadcast()
	for _, player in Players:GetPlayers() do
		send(player)
	end
end
local function collect(player: Player, name: string): (boolean, string)
	local crystal = crystals[name]
	if not crystal then
		return false, "Unknown crystal"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local distance = if root and root:IsA("BasePart") then (root.Position - crystal.Position).Magnitude else math.huge
	local allowed, reason = Rules.canCollect(
		round.state,
		PlayerData.get(player) ~= nil,
		humanoid ~= nil and humanoid.Health > 0,
		distance,
		claimed[name] == true
	)
	if not allowed then
		return false, reason
	end
	if not gate:use(player, 0.15) then
		return false, "Slow down"
	end
	local awarded = false
	local updated = PlayerData.update(player, function(data)
		awarded = Economy.award(data, 1)
	end)
	if not updated or not awarded then
		return false, "Reward could not be applied"
	end
	claimed[name] = true -- no yields before claiming/rewarding; concurrent input cannot award twice
	scores[player] = (scores[player] or 0) + 1
	crystal.Transparency = 1
	local prompt = crystal:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
	send(player)
	return true, "Collected"
end
for _, child in workspace:WaitForChild("World"):WaitForChild("Arena"):WaitForChild("Crystals"):GetChildren() do
	if child:IsA("BasePart") then
		crystals[child.Name] = child
		local prompt = child:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
			prompt.Triggered:Connect(function(player)
				local ok, reason = collect(player, child.Name)
				if not ok then
					Net.fire(player, "CrystalToast", reason)
				end
			end)
		end
	end
end
Net.on("CrystalCollect", { Net.string(32) }, function(player, name)
	local ok, reason = collect(player, name)
	if not ok then
		Net.fire(player, "CrystalToast", reason)
	end
end, { rate = 5 })
Net.handle("CrystalSnapshot", {}, state, { rate = 2 })
PlayerData.loaded:Connect(send)
Players.PlayerRemoving:Connect(function(player)
	scores[player] = nil
	gate:clear(player)
end)
DebugHooks.register("CrystalRush", {
	state = function()
		return round:snapshot()
	end,
	skip = function()
		return round:skip()
	end,
	collect = function(name: string, player: Player?)
		local selected = player or Players:GetPlayers()[1]
		if not selected then
			return false, "No player"
		end
		return collect(selected, name)
	end,
})
task.spawn(function()
	while true do
		local snapshot, changed = round:step(#Players:GetPlayers())
		if changed then
			if snapshot.state == "Playing" then
				table.clear(scores)
				table.clear(claimed)
				for _, crystal in crystals do
					crystal.Transparency = 0
					local prompt = crystal:FindFirstChildOfClass("ProximityPrompt")
					if prompt then
						prompt.Enabled = true
					end
				end
			else
				for _, crystal in crystals do
					local prompt = crystal:FindFirstChildOfClass("ProximityPrompt")
					if prompt then
						prompt.Enabled = false
					end
				end
			end
		end
		local timer = math.ceil(snapshot.remaining)
		if changed or timer ~= lastTimer then
			broadcast()
			lastTimer = timer
		end
		task.wait(0.2) -- five cheap steps/s, at most one scheduled UI broadcast/s
	end
end)
