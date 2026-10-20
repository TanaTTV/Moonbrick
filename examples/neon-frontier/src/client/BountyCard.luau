--!strict
-- The bounty board card: the same composition as other Moonbrick reward cards (panel, banner, stat,
-- flavour, buttons) dressed in this town's look: sharp corners, outline buttons, typewriter body,
-- scanlines and a glitch-in. Applying the theme here keeps the look in one place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Scheduler = require(Kit:WaitForChild("Scheduler"))
local UI = require(Kit:WaitForChild("UI"))
local Frontier = (require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Frontier")) :: any) :: {
	bounties: { { name: string, crime: string, reward: number, threat: number } },
	money: (number) -> string,
}

local BountyCard = {}

local CYAN = Color3.fromRGB(60, 240, 255)
local MAGENTA = Color3.fromRGB(255, 70, 190)
local AMBER = Color3.fromRGB(255, 170, 70)
local INK = Color3.fromRGB(232, 226, 246)
UI.useTheme({
	primary = CYAN,
	secondary = MAGENTA,
	surface = Color3.fromRGB(16, 12, 24),
	text = INK,
	textOutline = Color3.fromRGB(16, 12, 24),
	font = Enum.Font.SpecialElite,
	displayFont = Enum.Font.Sarpanch,
	corner = 2,
	stroke = 2,
	buttonFill = "outline",
	buttonStroke = CYAN,
	panelStroke = CYAN,
	panelTransparency = 0.1,
	textStrokeWidth = 0,
	labelStroke = 0,
})

local gui = UI.screen("FrontierHUD")
local card: Frame? = nil
local page = 1

local function scanlines(parent: GuiObject)
	local lines = Instance.new("Frame")
	lines.Name = "Scanlines"
	lines.BackgroundTransparency = 1
	lines.Size = UDim2.fromScale(1, 1)
	lines.ZIndex = 5
	for i = 0, 79 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = CYAN
		line.BackgroundTransparency = 0.94
		line.Position = UDim2.fromScale(0, i / 80)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.ZIndex = 5
		line.Parent = lines
	end
	lines.Parent = parent
end

function BountyCard.close()
	local current = card
	card = nil
	if current then
		UI.show(current, false)
		task.delay(0.3, function()
			current:Destroy()
		end)
	end
end

function BountyCard.show(i: number)
	BountyCard.close()
	local bounty = Frontier.bounties[i]
	-- A holder carries the panel and the scanline overlay (the panel's list layout would place it).
	local holder = Instance.new("Frame")
	holder.Name = "BountyCard"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(360, 300)
	holder.Position = UDim2.new(1, -40, 0.5, 0)
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Parent = gui
	local panel = UI.panel({
		parent = holder,
		name = "Panel",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		anchor = Vector2.zero,
		title = "WANTED",
	})
	local title = panel:FindFirstChild("Title") :: TextLabel
	title.TextColor3 = MAGENTA
	title.TextSize = 40

	-- Banner: the outlaw's name on a hard-edged strip with threat pips.
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.new(1, 0, 0, 40)
	banner.BackgroundColor3 = Color3.fromRGB(40, 16, 44)
	banner.BorderSizePixel = 0
	banner.LayoutOrder = 1
	local edge = Instance.new("UIStroke")
	edge.Color = MAGENTA
	edge.Thickness = 1
	edge.Parent = banner
	local name = UI.label({
		parent = banner,
		text = `{string.rep("◆", bounty.threat)}  {string.upper(bounty.name)}`,
		textSize = 18,
		color = INK,
		size = UDim2.fromScale(1, 1),
	})
	name.Font = Enum.Font.Sarpanch
	banner.Parent = panel

	local reward = UI.label({ parent = panel, text = Frontier.money(bounty.reward), textSize = 34, color = AMBER, size = UDim2.new(1, 0, 0, 40) })
	reward.Font = Enum.Font.Sarpanch
	reward.LayoutOrder = 2
	local crime = UI.label({ parent = panel, text = bounty.crime, textSize = 18, size = UDim2.new(1, -10, 0, 46) })
	crime.TextWrapped = true
	crime.LayoutOrder = 3

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 56)
	row.LayoutOrder = 4
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 12)
	list.Parent = row
	row.Parent = panel
	local nextButton = UI.button({
		parent = row,
		text = "NEXT",
		size = UDim2.fromOffset(130, 50),
		textSize = 22,
		onClick = function()
			page = page % #Frontier.bounties + 1
			BountyCard.show(page)
		end,
	})
	local close = UI.button({ parent = row, text = "CLOSE", style = "secondary", size = UDim2.fromOffset(130, 50), textSize = 22, onClick = BountyCard.close })
	nextButton.LayoutOrder, close.LayoutOrder = 1, 2
	scanlines(holder)

	card = holder
	UI.show(holder, true)
	-- Glitch in: a few hard horizontal jumps before it settles.
	local home = holder.Position
	local start = os.clock()
	Scheduler.every(function()
		if not holder.Parent then
			return true
		end
		local t = os.clock() - start
		if t > 0.3 then
			holder.Position = home
			return true
		end
		local jump = if math.floor(t * 30) % 2 == 0 then math.random(-10, 10) else 0
		holder.Position = home + UDim2.fromOffset(jump, 0)
		return false
	end)
end


-- Opens the current bounty, or closes the card if it is open.
function BountyCard.toggle()
	if card then
		BountyCard.close()
	else
		BountyCard.show(page)
	end
end

return BountyCard
