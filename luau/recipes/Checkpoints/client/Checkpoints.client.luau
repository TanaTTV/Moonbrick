--!strict
-- A toast and a burst when the server records a new checkpoint.
local Players = game:GetService("Players")
local Kit = game:GetService("ReplicatedStorage"):WaitForChild("Kit")
local UI = require(Kit:WaitForChild("UI"))
local VFX = require(Kit:WaitForChild("VFX"))

local player = Players.LocalPlayer
player:GetAttributeChangedSignal("Checkpoint"):Connect(function()
	local order = player:GetAttribute("Checkpoint")
	if type(order) ~= "number" then
		return
	end
	UI.toast(`Checkpoint {order}`, { color = UI.Theme.success })
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		VFX.burst(root.Position, { count = 24 })
	end
end)
