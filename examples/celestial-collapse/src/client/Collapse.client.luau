--!strict
-- Celestial Collapse client: input, the style plate HUD, damage numbers, and playing every cast the
-- server announces (yours and the Astromancer's).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = ReplicatedStorage:WaitForChild("Kit")
local Motion = require(Kit:WaitForChild("Motion"))
local Net = require(Kit:WaitForChild("Net"))
local Tex = require(Kit:WaitForChild("Tex"))

-- Effect textures: the local preview from `python scripts/fxtex.py preview` in Studio; stock textures in a
-- published game until you upload the PNGs and call Tex.useFiles({ ... }).
if RunService:IsStudio() then
	Tex.usePreview()
end
local CollapsePlayer = require(script.Parent:WaitForChild("CollapsePlayer"))

local player = Players.LocalPlayer
local STYLES = { "Celestial", "Abyssal" }
-- The HUD's type and colour follow each style's art direction, not one shared theme.
local LOOK = {
	Celestial = {
		title = "CELESTIAL COLLAPSE",
		caption = "Gather a star. Bring it down.",
		font = Enum.Font.Fondamento,
		ink = Color3.fromRGB(255, 244, 220),
		accent = Color3.fromRGB(96, 214, 255),
		plate = Color3.fromRGB(46, 34, 28),
	},
	Abyssal = {
		title = "ABYSSAL COLLAPSE",
		caption = "Call the deep up through the ground.",
		font = Enum.Font.GrenzeGotisch,
		ink = Color3.fromRGB(200, 255, 186),
		accent = Color3.fromRGB(86, 210, 120),
		plate = Color3.fromRGB(10, 14, 12),
	},
}
local selected = 1

local gui = Instance.new("ScreenGui")
gui.Name = "CollapseHUD"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.Parent = player:WaitForChild("PlayerGui")

local plate = Instance.new("Frame")
plate.AnchorPoint = Vector2.new(0.5, 1)
plate.Position = UDim2.new(0.5, 0, 1, -24)
plate.Size = UDim2.fromOffset(420, 86)
plate.BackgroundTransparency = 0.12
plate.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = plate
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Parent = plate

local function text(name: string, y: number, height: number, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.TextSize = size
	label.Parent = plate
	return label
end
local title = text("Title", 10, 34, 30)
local caption = text("Caption", 44, 20, 16)
local hint = text("Hint", 64, 18, 13)
hint.TextTransparency = 0.35

local cooldownBar = Instance.new("Frame")
cooldownBar.Name = "Cooldown"
cooldownBar.AnchorPoint = Vector2.new(0, 1)
cooldownBar.Position = UDim2.fromScale(0, 1)
cooldownBar.Size = UDim2.fromOffset(0, 3)
cooldownBar.BorderSizePixel = 0
cooldownBar.Parent = plate

local function render()
	local look = LOOK[STYLES[selected]]
	plate.BackgroundColor3 = look.plate
	stroke.Color = look.accent
	title.Text, title.Font, title.TextColor3 = look.title, look.font, look.ink
	caption.Text, caption.Font, caption.TextColor3 = look.caption, look.font, look.ink
	hint.Text, hint.Font, hint.TextColor3 = "Q / X / tap  cast    ·    T / Y  switch style", Enum.Font.Gotham, look.ink
	cooldownBar.BackgroundColor3 = look.accent
end
render()

local function cast(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		Net.fireServer("Collapse", STYLES[selected])
		cooldownBar.Size = UDim2.new(1, 0, 0, 3)
		Motion.to(cooldownBar, { Size = UDim2.fromOffset(0, 3) }, { time = 4, ease = "linear" })
	end
	return Enum.ContextActionResult.Sink
end
local function switch(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		selected = selected % #STYLES + 1
		render()
		plate.Size = UDim2.fromOffset(440, 92)
		Motion.to(plate, { Size = UDim2.fromOffset(420, 86) }, { time = 0.25, ease = "backOut" })
	end
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("CollapseCast", cast, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
ContextActionService:BindAction("CollapseStyle", switch, true, Enum.KeyCode.T, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("CollapseCast", "CAST")
ContextActionService:SetTitle("CollapseStyle", "STYLE")

Net.listen("Collapse", function(styleName: string, caster: Model, target: Vector3)
	if caster and caster.Parent then
		CollapsePlayer.play(styleName, caster, target)
	end
end)

-- Damage numbers rise and fade over the target.
Net.listen("Damage", function(target: Model, amount: number)
	local head = target and target:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local look = LOOK[STYLES[selected]]
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(120, 48)
	board.StudsOffset = Vector3.new(0, 2.5, 0)
	board.AlwaysOnTop = true
	board.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = tostring(amount)
	label.Font = look.font
	label.TextScaled = true
	label.TextColor3 = look.ink
	label.TextStrokeTransparency = 0.3
	label.Parent = board
	board.Parent = gui
	Motion.to(board, { StudsOffset = Vector3.new(0, 5.5, 0) }, { time = 0.9, ease = "cubicOut" })
	Motion.to(label, { TextTransparency = 1, TextStrokeTransparency = 1 }, {
		time = 0.4,
		delay = 0.6,
		onDone = function()
			board:Destroy()
		end,
	})
end)
