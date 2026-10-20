--!strict
-- Showcase stage: the Astromancer (an NPC caster, so the demo runs without a player avatar) and three
-- sandstone Sentinels to hit. Sentinels get back up after a knockdown.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local function rig(
	name: string,
	colors: { head: Color3, torso: Color3, arms: Color3, legs: Color3 },
	at: CFrame
): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor, description.TorsoColor = colors.head, colors.torso
	description.LeftArmColor, description.RightArmColor = colors.arms, colors.arms
	description.LeftLegColor, description.RightLegColor = colors.legs, colors.legs
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn(`Stage: could not build {name}: {model}`)
		return nil
	end
	model.Name = name
	model:PivotTo(at)
	return model
end

local stage = Instance.new("Folder")
stage.Name = "Stage"
stage.Parent = workspace

local caster = rig("Astromancer", {
	head = Color3.fromRGB(226, 190, 150),
	torso = Color3.fromRGB(34, 44, 86),
	arms = Color3.fromRGB(196, 160, 80),
	legs = Color3.fromRGB(24, 30, 60),
}, CFrame.new(0, 4.2, 14))
if caster then
	(caster:FindFirstChild("HumanoidRootPart") :: BasePart).Anchored = true
	caster.Parent = stage
end

for i, x in { -6, 0, 6 } do
	local sentinel = rig(`Sentinel{i}`, {
		head = Color3.fromRGB(196, 150, 104),
		torso = Color3.fromRGB(170, 124, 84),
		arms = Color3.fromRGB(150, 108, 74),
		legs = Color3.fromRGB(130, 92, 62),
	}, CFrame.new(x, 4.2, if x == 0 then -14 else -11) * CFrame.Angles(0, math.pi, 0))
	if sentinel then
		local humanoid = sentinel:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.BreakJointsOnDeath = false
		humanoid.MaxHealth, humanoid.Health = 200, 200
		CollectionService:AddTag(sentinel, "CollapseTarget")
		sentinel.Parent = stage
		local home = sentinel:GetPivot()
		humanoid.HealthChanged:Connect(function(health)
			if health <= 0 then
				task.delay(2.5, function()
					humanoid.Health = humanoid.MaxHealth
					sentinel:PivotTo(home)
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end)
	end
end
