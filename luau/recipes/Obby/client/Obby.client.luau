--!strict
-- Stage counter and running timer, plus a toast at the finish.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Kit = game:GetService("ReplicatedStorage"):WaitForChild("Kit")
local UI = require(Kit:WaitForChild("UI"))

local player = Players.LocalPlayer
local hud = UI.hud("Obby")
local group = UI.anchor({ parent = hud, corner = "topLeft", size = UDim2.fromOffset(220, 72) })
local stage = UI.label({ parent = group, text = "Stage 0", size = UDim2.new(1, 0, 0, 32), scaled = true })
local timer = UI.label({
	parent = group,
	text = "",
	position = UDim2.fromOffset(0, 36),
	size = UDim2.new(1, 0, 0, 28),
	scaled = true,
})

player:GetAttributeChangedSignal("ObbyStage"):Connect(function()
	stage.Text = `Stage {player:GetAttribute("ObbyStage") or 0}`
end)
player:GetAttributeChangedSignal("ObbyFinished"):Connect(function()
	local seconds = player:GetAttribute("ObbyFinished")
	if type(seconds) == "number" then
		UI.toast(string.format("Finished in %.1f s!", seconds), { color = UI.Theme.success })
	end
end)

RunService.Heartbeat:Connect(function()
	local start = player:GetAttribute("ObbyStarted")
	timer.Text = if type(start) == "number" then string.format("%.1f s", workspace:GetServerTimeNow() - start) else ""
end)
