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

-- The rig that owns a part (accessories nest models, so walk up to the one with a Humanoid).
local function rigOf(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorOfClass("Model")
	end
	return model
end

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
	local seen: { [Model]: boolean } = {}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	-- A radius query finds rigs wherever they live (Workspace.World, a map folder), not just at the top level.
	for _, part in workspace:GetPartBoundsInRadius(origin, RADIUS, overlap) do
		local model = rigOf(part)
		local target = model and model:FindFirstChildOfClass("Humanoid")
		local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
		if
			model
			and not seen[model]
			and target
			and target.Health > 0
			and targetRoot
			and targetRoot:IsA("BasePart")
			and (targetRoot.Position - origin).Magnitude <= RADIUS
		then
			seen[model] = true
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
