--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Kit = ReplicatedStorage:WaitForChild("Kit", 10)
local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
assert(Kit and Shared and playerGui, "Crystal Rush HUD dependencies unavailable after 10s")
for _, name in { "Net", "UI", "VFX" } do
	assert(Kit:WaitForChild(name, 10), `Crystal Rush Kit.{name} unavailable after 10s`)
end
assert(Shared:WaitForChild("HUDLayout", 10), "Crystal Rush HUDLayout unavailable after 10s")
local Net, UI, VFX = require(Kit.Net), require(Kit.UI), require(Kit.VFX)
local HUDLayout = require(Shared.HUDLayout)
UI.Theme.primary = Color3.fromRGB(166, 138, 232)
UI.Theme.secondary = Color3.fromRGB(128, 182, 200)
UI.Theme.surface = Color3.fromRGB(35, 46, 72)
UI.Theme.text = Color3.fromRGB(240, 244, 255)
local screen = UI.screen("CrystalRush")
screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
screen.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
screen.ClipToDeviceSafeArea = true
local safeRoot = Instance.new("Frame")
safeRoot.Name = "DeviceSafeRoot"
safeRoot.Size = UDim2.fromScale(1, 1)
safeRoot.BackgroundTransparency = 1
safeRoot.Parent = screen
local panel = UI.panel({
	parent = safeRoot,
	size = UDim2.fromOffset(360, 104),
	position = UDim2.fromScale(0.5, 0),
	anchor = Vector2.new(0.5, 0),
	padding = 12,
})
local list = panel:FindFirstChildOfClass("UIListLayout")
assert(list, "Crystal Rush panel layout missing")
list.Padding = UDim.new(0, 4)
local scale = Instance.new("UIScale")
scale.Parent = panel
local title = UI.label({ parent = panel, text = "CRYSTAL RUSH", textSize = 24, color = UI.Theme.primary })
title.Size = UDim2.new(1, 0, 0, 24)
title.LayoutOrder = 1
local status = UI.label({ parent = panel, text = "Loading round…", textSize = 22 })
status.Size = UDim2.new(1, 0, 0, 22)
status.LayoutOrder = 2
local score = UI.label({ parent = panel, text = "Find amethyst to collect", textSize = 22, scaled = true })
score.Size = UDim2.new(1, 0, 0, 22)
score.LayoutOrder = 3
local textSize = Instance.new("UITextSizeConstraint")
textSize.MinTextSize = 14
textSize.MaxTextSize = 22
textSize.Parent = score
local notice = UI.label({ parent = panel, text = "", textSize = 20, color = UI.Theme.primary, scaled = true })
notice.Size = UDim2.new(1, 0, 0, 30)
notice.LayoutOrder = 4
notice.Visible = false
-- All HUD elements are informational; native prompts own touch/gamepad input.
for _, label in { title, status, score, notice } do
	label.Selectable = false
	label.Active = false
end
local function resize()
	local size, origin = safeRoot.AbsoluteSize, safeRoot.AbsolutePosition
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local topLeft, bottomRight = GuiService:GetGuiInset()
	-- DeviceSafeInsets already handles notches. Subtract that origin from CoreGui's top/left
	-- margins so the top bar is respected without applying the device safe area twice.
	local layout = HUDLayout.layoutFor({ width = size.X, height = size.Y }, {
		left = math.max(0, topLeft.X - origin.X),
		top = math.max(0, topLeft.Y - origin.Y),
		right = bottomRight.X,
		bottom = bottomRight.Y,
	}, notice.Visible)
	panel.Position = UDim2.fromOffset(layout.x, layout.y)
	panel.Size = UDim2.fromOffset(layout.width, layout.height)
	scale.Scale = layout.scale
end
safeRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
safeRoot:GetPropertyChangedSignal("AbsolutePosition"):Connect(resize)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(resize)
resize()
local previous = 0
local function render(snapshot: any, totals: any)
	if type(snapshot) ~= "table" or type(totals) ~= "table" then
		return
	end
	status.Text = snapshot.state .. " · " .. math.ceil(snapshot.remaining) .. "s"
	score.Text = `Crystals: {totals.caught}   Coins: {totals.coins}`
	if totals.caught > previous then
		score.TextColor3 = UI.Theme.primary
		VFX.tween(score, 0.3, { TextColor3 = UI.Theme.text })
	end
	previous = totals.caught
end
Net.listen("CrystalState", render)
local noticeToken = 0
Net.listen("CrystalToast", function(message: string)
	noticeToken += 1
	local token = noticeToken
	notice.Text = message
	notice.Visible = true
	resize()
	task.delay(2.5, function()
		if noticeToken == token then
			notice.Visible = false
			resize()
		end
	end)
end)
-- Never wait for or enumerate Workspace crystals on the client. Native replicated prompts
-- appear/disappear with streamed parts; scores/rounds come from remotes, not local part counts.
local snapshot, totals = Net.invoke("CrystalSnapshot")
render(snapshot, totals)
