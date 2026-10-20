--!strict
-- Mythic Hatch client: dresses the grove, plays every hatch the server announces, and shows the owner a
-- reward card styled for this game (cream paper, soft ink, a rarity ribbon) rather than the Kit default.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = ReplicatedStorage:WaitForChild("Kit")
local Audio = require(Kit:WaitForChild("Audio"))
local Motion = require(Kit:WaitForChild("Motion"))
local Net = require(Kit:WaitForChild("Net"))
local Scheduler = require(Kit:WaitForChild("Scheduler"))
local Tex = require(Kit:WaitForChild("Tex"))
local UI = require(Kit:WaitForChild("UI"))

-- Effect textures and sounds: local previews from `python scripts/fxtex.py preview` and
-- `python scripts/sfx.py preview` in Studio. A published game needs the owner to upload them first.
if RunService:IsStudio() then
	Tex.usePreview()
end
local Grove = require(script.Parent:WaitForChild("Grove"))
local HatchPlayer = require(script.Parent:WaitForChild("HatchPlayer"))
local Hatch = (require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Hatch")) :: any) :: {
	looks: { [string]: any },
}

local player = Players.LocalPlayer
local world = workspace:WaitForChild("World")
local scene = world:WaitForChild("Scene")
Grove.dress(scene)
Grove.dress(world:WaitForChild("Backdrop"))
local pedestal = scene:WaitForChild("Pedestal") :: BasePart
local Creature = require(script.Parent:WaitForChild("Creature"))
Audio.loop("rbxasset://sounds/moonbrick/wind.wav", nil, { volume = 0.25, fade = 2 })

-- The game's art direction, applied once: cream paper, plum ink, flat pill buttons, storybook type.
local INK = Color3.fromRGB(70, 44, 74)
UI.useTheme({
	primary = Color3.fromRGB(120, 92, 170),
	secondary = Color3.fromRGB(226, 196, 150),
	surface = Color3.fromRGB(252, 244, 228),
	text = Color3.fromRGB(255, 250, 240), -- button text; card labels pass INK
	textOutline = INK,
	font = Enum.Font.Nunito,
	displayFont = Enum.Font.Kalam,
	corner = 22,
	stroke = 2,
	buttonFill = "flat",
	buttonStroke = Color3.fromRGB(252, 244, 228),
	panelStroke = Color3.fromRGB(226, 196, 150),
	panelTransparency = 0,
	textStrokeWidth = 0,
	labelStroke = 0,
})

-- The waiting egg: neutral colours (the rarity shows only once it starts to hatch), a slow breathe and turn.
local idleEgg = Creature.egg({
	name = "Idle",
	shell = Color3.fromRGB(226, 218, 206),
	speckle = Color3.fromRGB(128, 108, 176),
}):Clone()
idleEgg.Name = "IdleEgg"
idleEgg.Size *= 1.35
idleEgg.Anchored, idleEgg.CanCollide = true, false
idleEgg.Parent = workspace
local idleGlow = Instance.new("PointLight")
idleGlow.Color = Color3.fromRGB(200, 180, 255)
idleGlow.Range = 9
idleGlow.Shadows = false
idleGlow.Parent = idleEgg
local idleT = 0
Scheduler.every(function(dt)
	idleT += dt
	local top = pedestal.CFrame * CFrame.new(0, pedestal.Size.Y / 2, 0)
	idleEgg.CFrame = top
		* CFrame.new(0, idleEgg.Size.Y / 2 + 0.15 + math.sin(idleT * 1.6) * 0.12, 0)
		* CFrame.Angles(0, idleT * 0.4, 0)
	idleGlow.Brightness = 0.45 + math.sin(idleT * 1.6) * 0.25
	return false
end)

local gui = UI.screen("HatchHUD")
local busy = false
local cancelCurrent: (() -> ())? = nil

local function request()
	if not busy then
		Net.fireServer("Hatch")
	end
end

local hatchButton = UI.button({
	parent = gui,
	name = "HatchButton",
	text = "HATCH",
	size = UDim2.fromOffset(200, 64),
	position = UDim2.new(0.5, 0, 1, -40),
	anchor = Vector2.new(0.5, 1),
	textSize = 30,
	pulse = true,
	onClick = request,
})

ContextActionService:BindAction("Hatch", function(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		request()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonA)

local RIBBON = {
	Common = { Color3.fromRGB(150, 200, 160), Color3.fromRGB(214, 236, 200) },
	Rare = { Color3.fromRGB(240, 150, 70), Color3.fromRGB(255, 220, 140) },
	Mythic = { Color3.fromRGB(250, 120, 200), Color3.fromRGB(110, 220, 255) },
}
local STARS = { Common = 1, Rare = 2, Mythic = 3 }

-- Clears the newborn and puts a fresh egg back on the pedestal.
local function finish()
	if cancelCurrent then
		cancelCurrent()
		cancelCurrent = nil
	end
	idleEgg.Transparency = 0
	idleGlow.Enabled = true
	hatchButton.Visible = true
end

local card: Frame? = nil
local function closeCard()
	local current = card
	card = nil
	if current then
		UI.show(current, false)
		task.delay(0.3, function()
			current:Destroy()
		end)
	end
end

local function showCard(rarity: string, glow: number)
	closeCard()
	local look = Hatch.looks[rarity]
	local panel = UI.panel({
		parent = gui,
		name = "RewardCard",
		size = UDim2.fromOffset(340, 330),
		position = UDim2.new(1, -40, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		title = "A Mothling!",
	})
	local title = panel:FindFirstChild("Title") :: TextLabel
	title.TextColor3 = INK

	-- Rarity ribbon: a band with a slow two-colour shimmer, stars and the rarity name.
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.Size = UDim2.new(1, 0, 0, 40)
	ribbon.BackgroundColor3 = Color3.new(1, 1, 1)
	ribbon.LayoutOrder = 1
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = ribbon
	local shimmer = Instance.new("UIGradient")
	local colors = RIBBON[rarity]
	shimmer.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(0.5, colors[2]),
		ColorSequenceKeypoint.new(1, colors[1]),
	})
	shimmer.Parent = ribbon
	local stars = string.rep("★", STARS[rarity])
	local label = UI.label({
		parent = ribbon,
		text = `{stars}  {string.upper(look.title)}  {stars}`,
		textSize = 22,
		color = Color3.new(1, 1, 1),
		size = UDim2.fromScale(1, 1),
	})
	label.Font = Enum.Font.Kalam
	label.TextStrokeTransparency = 0.6
	label.TextStrokeColor3 = INK
	ribbon.Parent = panel
	local t0 = os.clock()
	Scheduler.every(function()
		if not ribbon.Parent then
			return true
		end
		shimmer.Offset = Vector2.new(math.sin((os.clock() - t0) * 1.6) * 0.5, 0)
		return false
	end)

	local stats =
		UI.label({ parent = panel, text = `Glow  {glow}`, textSize = 26, color = INK, size = UDim2.new(1, 0, 0, 34) })
	stats.LayoutOrder = 2
	local flavour = UI.label({
		parent = panel,
		text = "Hatched under the grove's moon. It hums when it's happy.",
		textSize = 19,
		color = INK,
		size = UDim2.new(1, -12, 0, 44),
	})
	flavour.TextWrapped = true
	flavour.TextTransparency = 0.15
	flavour.LayoutOrder = 3

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 56)
	row.LayoutOrder = 4
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 12)
	list.Parent = row
	row.Parent = panel
	local keep = UI.button({
		parent = row,
		text = "KEEP",
		size = UDim2.fromOffset(130, 52),
		textSize = 24,
		onClick = function()
			closeCard()
			finish()
		end,
	})
	local again = UI.button({
		parent = row,
		text = "AGAIN",
		style = "secondary",
		size = UDim2.fromOffset(130, 52),
		textSize = 24,
		onClick = function()
			closeCard()
			request()
		end,
	})

	list.SortOrder = Enum.SortOrder.LayoutOrder
	keep.LayoutOrder, again.LayoutOrder = 1, 2
	card = panel
	UI.show(panel, true)
	-- Stats count up so the number lands after the card.
	local start = os.clock()
	Scheduler.every(function()
		if not stats.Parent then
			return true
		end
		local k = Motion.ease("cubicOut", math.min((os.clock() - start) / 0.8, 1))
		stats.Text = `Glow  {math.floor(glow * k + 0.5)}`
		return k >= 1
	end)
end

Net.listen("Hatched", function(rarity: string, glow: number, owner: Player?)
	if not Hatch.looks[rarity] then
		return
	end
	if cancelCurrent then
		cancelCurrent()
	end
	closeCard()
	busy = true
	hatchButton.Visible = false
	idleEgg.Transparency = 1
	idleGlow.Enabled = false
	local mine = owner == player or owner == nil
	local playing = HatchPlayer.play(rarity, pedestal, {
		camera = mine,
		onCard = function()
			if mine then
				showCard(rarity, glow)
			end
		end,
		onDone = function()
			busy = false
			if not mine then
				finish()
			end
		end,
	})
	cancelCurrent = playing.cancel
end)
