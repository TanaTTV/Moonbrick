--!strict
-- Area attack: the client only asks; the server checks the cooldown, finds targets and applies damage.
local Players = game:GetService("Players")
local Kit = game:GetService("ServerScriptService").Kit
local Cooldown = require(Kit.Cooldown)
local DebugHooks = require(Kit.DebugHooks)
local SharedKit = game:GetService("ReplicatedStorage").Kit
local Net = require(SharedKit.Net)
local VFX = require(SharedKit.VFX)

local COOLDOWN = 3
local RADIUS = 14
local DAMAGE = 25
local COLOR = Color3.fromRGB(255, 70, 90)

local gate = Cooldown.new()
Net.declare("AbilityFx")

local function cast(player: Player): string
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return "not alive"
	end
	local ready, remaining = gate:use(player, COOLDOWN)
	if not ready then
		return string.format("cooldown %.1fs", remaining)
	end
	local origin = root.Position
	local hits = 0
	for _, model in workspace:GetChildren() do
		local target = model:FindFirstChildOfClass("Humanoid")
		local targetRoot = model:FindFirstChild("HumanoidRootPart")
		if
			model ~= character
			and target
			and target.Health > 0
			and targetRoot
			and targetRoot:IsA("BasePart")
			and (targetRoot.Position - origin).Magnitude <= RADIUS
		then
			target:TakeDamage(DAMAGE)
			hits += 1
		end
	end
	VFX.impact(origin, { color = COLOR, size = RADIUS * 2 })
	Net.fireAll("AbilityFx", origin, RADIUS)
	return "hit " .. hits
end

Net.on("Ability", {}, function(player)
	cast(player)
end, { rate = 2 })

Players.PlayerRemoving:Connect(function(player)
	gate:clear(player)
end)

DebugHooks.register("Ability", {
	cast = function(): string
		local player = Players:GetPlayers()[1]
		return if player then cast(player) else "no player"
	end,
	reset = function(): string
		for _, player in Players:GetPlayers() do
			gate:clear(player)
		end
		return "cooldowns cleared"
	end,
})
