--!strict
-- Q / gamepad X / on-screen touch button asks the server to cast; shake the camera when an ability lands nearby.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local Kit = game:GetService("ReplicatedStorage"):WaitForChild("Kit")
local Net = require(Kit:WaitForChild("Net"))
local VFX = require(Kit:WaitForChild("VFX"))

ContextActionService:BindAction("Ability", function(_, state)
	if state == Enum.UserInputState.Begin then
		Net.fireServer("Ability")
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
ContextActionService:SetTitle("Ability", "Blast")

Net.listen("AbilityFx", function(origin: Vector3, radius: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - origin).Magnitude <= radius * 2 then
		VFX.shake(0.35, 0.6)
	end
end)
