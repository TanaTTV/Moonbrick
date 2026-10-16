--!strict
-- Parts tagged "Coin" (CollectionService) award REWARD saved coins when a player touches them.
-- The server checks distance (touches can be faked) and hides the part until it respawns.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Kit = game:GetService("ServerScriptService").Kit
local PlayerData = require(Kit.PlayerData)
local DebugHooks = require(Kit.DebugHooks)
local VFX = require(game:GetService("ReplicatedStorage").Kit.VFX)

local TAG = "Coin"
local REWARD = 1
local RESPAWN = 5
local MAX_DISTANCE = 12

local taken: { [BasePart]: boolean } = {}

local function collect(player: Player, coin: BasePart): string
	if taken[coin] then
		return "already taken"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or (root.Position - coin.Position).Magnitude > MAX_DISTANCE then
		return "too far"
	end
	if not PlayerData.get(player) then
		return "data not loaded"
	end
	taken[coin] = true
	PlayerData.increment(player, "Coins", REWARD)
	VFX.burst(coin.Position, { count = 20 })
	local transparency = coin.Transparency
	coin.Transparency, coin.CanTouch = 1, false
	task.delay(RESPAWN, function()
		coin.Transparency, coin.CanTouch = transparency, true
		taken[coin] = nil
	end)
	return "collected"
end

local function setup(instance: Instance)
	if not instance:IsA("BasePart") then
		warn("Pickups: tagged instance is not a BasePart:", instance:GetFullName())
		return
	end
	local coin = instance
	VFX.glow(coin)
	coin.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			collect(player, coin)
		end
	end)
end

for _, instance in CollectionService:GetTagged(TAG) do
	setup(instance)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(setup)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
	if instance:IsA("BasePart") then
		taken[instance] = nil
	end
end)

DebugHooks.register("Pickups", {
	-- Move the first player onto the nearest free coin and collect it.
	collectNearest = function(): string
		local player = Players:GetPlayers()[1]
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not (player and root and root:IsA("BasePart")) then
			return "no player"
		end
		local best: BasePart?, bestDistance = nil, math.huge
		for _, instance in CollectionService:GetTagged(TAG) do
			if instance:IsA("BasePart") and not taken[instance] then
				local distance = (instance.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = instance, distance
				end
			end
		end
		if not best then
			return "no free coin"
		end
		root.CFrame = CFrame.new(best.Position)
		return collect(player, best)
	end,
	coins = function(): string
		local player = Players:GetPlayers()[1]
		local data = player and PlayerData.get(player)
		return if data then tostring(data.Coins) else "no data"
	end,
})
