--!strict
-- Spawn and checkpoints. Parts tagged "Checkpoint" with a number attribute `Order` (1, 2, ...) remember the
-- furthest one each player touched, and the player respawns there. Before the first checkpoint players use the
-- place's SpawnLocation. Progress lasts the session; to keep it, store `Checkpoint` in PlayerData.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local DebugHooks = require(game:GetService("ServerScriptService").Kit.DebugHooks)

local TAG = "Checkpoint"
local MAX_DISTANCE = 24 -- touches can be faked; a real one is near the part

local function orderOf(part: BasePart): number?
	local order = part:GetAttribute("Order")
	return if type(order) == "number" then order else nil
end

local function find(order: number): BasePart?
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("BasePart") and orderOf(instance) == order then
			return instance
		end
	end
	return nil
end

local function reach(player: Player, part: BasePart): string
	local order = orderOf(part)
	if not order then
		warn("Checkpoints: no number attribute Order on", part:GetFullName())
		return "no order"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or (root.Position - part.Position).Magnitude > MAX_DISTANCE then
		return "too far"
	end
	local best = player:GetAttribute(TAG)
	if type(best) == "number" and best >= order then
		return "already reached"
	end
	player:SetAttribute(TAG, order)
	return "reached " .. order
end

local function respawn(player: Player, character: Model): string
	local order = player:GetAttribute(TAG)
	local part = if type(order) == "number" then find(order) else nil
	if not part then
		return "default spawn"
	end
	-- After the engine's own spawn placement, or the character snaps back to the SpawnLocation.
	character:WaitForChild("HumanoidRootPart")
	task.wait()
	character:PivotTo(part.CFrame + Vector3.new(0, part.Size.Y / 2 + 4, 0))
	return "at checkpoint " .. tostring(order)
end

local function setup(instance: Instance)
	if not instance:IsA("BasePart") then
		warn("Checkpoints: tagged instance is not a BasePart:", instance:GetFullName())
		return
	end
	local part = instance
	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			reach(player, part)
		end
	end)
end

for _, instance in CollectionService:GetTagged(TAG) do
	setup(instance)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(setup)

local function track(player: Player)
	player.CharacterAdded:Connect(function(character)
		respawn(player, character)
	end)
end
for _, player in Players:GetPlayers() do
	track(player)
end
Players.PlayerAdded:Connect(track)

DebugHooks.register("Checkpoints", {
	-- Stand on checkpoint `order` and touch it.
	reach = function(order: number): string
		local player = Players:GetPlayers()[1]
		local part = find(order)
		local character = player and player.Character
		if not (player and part and character) then
			return "no player or no checkpoint " .. order
		end
		character:PivotTo(part.CFrame + Vector3.new(0, 4, 0))
		return reach(player, part)
	end,
	respawn = function(): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "no player"
		end
		player:LoadCharacter()
		return "respawning at " .. tostring(player:GetAttribute(TAG))
	end,
})
