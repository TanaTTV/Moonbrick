--!strict
-- Round status at the top of the screen: the phase, seconds left and a bar running down.
local Kit = game:GetService("ReplicatedStorage"):WaitForChild("Kit")
local Net = require(Kit:WaitForChild("Net"))
local UI = require(Kit:WaitForChild("UI"))

local TITLES = { Waiting = "Waiting for players", Intermission = "Next round", Playing = "Fight!", Results = "Results" }

local hud = UI.hud("Round")
local group = UI.anchor({ parent = hud, corner = "top", size = UDim2.fromOffset(320, 72) })
local title = UI.label({ parent = group, text = TITLES.Waiting, size = UDim2.new(1, 0, 0, 40), scaled = true })
local bar = UI.bar({ parent = group, position = UDim2.fromOffset(0, 48), size = UDim2.new(1, 0, 0, 16) })

Net.listen("RoundState", function(state: string, remaining: number, total: number)
	local name = (TITLES :: any)[state] or state
	title.Text = if remaining > 0 then `{name}: {remaining}` else name
	bar.frame.Visible = total > 0
	bar.set(remaining, math.max(total, 1))
end)
