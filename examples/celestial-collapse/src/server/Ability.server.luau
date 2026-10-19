--!strict
-- Celestial Collapse server: validates casts, picks the target from the caster's own position, applies
-- damage at the blast time and tells every client to play the presentation. Clients never send targets.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ServerScriptService.Kit
local Cooldown = require(Kit.Cooldown)
local DebugHooks = require(Kit.DebugHooks)
local Net = require(ReplicatedStorage.Kit.Net)
local Collapse = require(ReplicatedStorage.Shared.Collapse)

local RANGE = 26
local COOLDOWN = 4
local gate = Cooldown.new()
local casts = 0

Net.declare("Collapse")
Net.declare("Damage")

local function groundBelow(position: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position else Vector3.new(position.X, 0, position.Z)
end

local function targetFor(caster: Model): Vector3?
	local root = caster:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local direction = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	return groundBelow(root.Position + direction * RANGE, { caster })
end

-- Health and knockback for training targets (server-owned rigs tagged "CollapseTarget").
local function applyBlast(origin: Vector3, radius: number, caster: Model)
	for _, target in CollectionService:GetTagged("CollapseTarget") do
		if target:IsA("Model") and target ~= caster then
			local humanoid = target:FindFirstChildOfClass("Humanoid")
			local root = target:FindFirstChild("HumanoidRootPart")
			if humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
				local offset = root.Position - origin
				local amount = Collapse.damageAt(offset.Magnitude, radius)
				if amount > 0 then
					humanoid:TakeDamage(amount)
					local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.yAxis
					root.AssemblyLinearVelocity = (away * Vector3.new(1, 0, 1)) * 40 + Vector3.new(0, 45, 0)
					Net.fireAll("Damage", target, amount)
				end
			end
		end
	end
end

local function cast(caster: Model, styleName: string, key: any): (boolean, string)
	local style = Collapse.styles[styleName]
	if not style then
		return false, "unknown style"
	end
	if not gate:use(key, COOLDOWN) then
		return false, "cooling down"
	end
	local target = targetFor(caster)
	if not target then
		return false, "no caster root"
	end
	local timeline = Collapse.timeline(style)
	casts += 1
	Net.fireAll("Collapse", styleName, caster, target)
	task.delay(timeline.blast, function()
		applyBlast(target, style.blast.radius, caster)
	end)
	return true, `cast {styleName} at {math.floor(target.X)},{math.floor(target.Z)}`
end

Net.on("Collapse", { Net.oneOf("Celestial", "Abyssal") }, function(player, styleName)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		local ok, reason = cast(character, styleName, player)
		if not ok and reason ~= "cooling down" then
			warn(`Collapse: {player.Name}: {reason}`)
		end
	end
end, { rate = 2 })

Players.PlayerRemoving:Connect(function(player)
	gate:clear(player)
end)

DebugHooks.register("Collapse", {
	-- Casts from the showcase NPC (no player needed): K.hook("Collapse", "cast", "Abyssal")
	cast = function(styleName: string?)
		local npc = workspace:FindFirstChild("Astromancer", true)
		if not npc or not npc:IsA("Model") then
			return "no Astromancer"
		end
		local _, message = cast(npc, styleName or "Celestial", npc)
		return message
	end,
	state = function()
		return { casts = casts, styles = { "Celestial", "Abyssal" } }
	end,
})
