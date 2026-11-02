--!strict
-- Named areas. A part tagged "Zone" (usually invisible, CanCollide off) names an area; its `ZoneName`
-- attribute, or else its Name, is the zone. The server checks positions four times a second, so anything
-- that matters (safe zones, shop access) can trust the `Zone` attribute on the Player. Overlaps: the smallest wins.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local DebugHooks = require(game:GetService("ServerScriptService").Kit.DebugHooks)

local TAG = "Zone"
local INTERVAL = 0.25

local function contains(part: BasePart, position: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function zoneName(part: BasePart): string
	local name = part:GetAttribute("ZoneName")
	return if type(name) == "string" then name else part.Name
end

local function zoneAt(position: Vector3): string?
	local best: BasePart? = nil
	local bestVolume = math.huge
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:IsA("BasePart") and contains(instance, position) then
			local volume = instance.Size.X * instance.Size.Y * instance.Size.Z
			if volume < bestVolume then
				best, bestVolume = instance, volume
			end
		end
	end
	return if best then zoneName(best) else nil
end

task.spawn(function()
	while true do
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local zone = if root and root:IsA("BasePart") then zoneAt(root.Position) else nil
			if player:GetAttribute(TAG) ~= zone then
				player:SetAttribute(TAG, zone)
			end
		end
		task.wait(INTERVAL)
	end
end)

DebugHooks.register("Zones", {
	current = function(): string
		local player = Players:GetPlayers()[1]
		return if player then tostring(player:GetAttribute(TAG)) else "no player"
	end,
	-- Moves the first player to the middle of a zone.
	enter = function(name: string): string
		local player = Players:GetPlayers()[1]
		for _, instance in CollectionService:GetTagged(TAG) do
			if instance:IsA("BasePart") and zoneName(instance) == name and player and player.Character then
				player.Character:PivotTo(instance.CFrame)
				return "moved to " .. name
			end
		end
		return "no zone " .. name
	end,
})
