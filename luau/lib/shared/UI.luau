--!strict
-- UI: themed components with built-in juice (pop-in, hover/press feedback, pulse) that work on
-- mouse, touch and gamepad. Client-only. Change UI.Theme once to restyle every screen.
--
--   local gui = UI.screen("Shop")
--   local panel = UI.panel({ parent = gui, size = UDim2.fromOffset(420, 300), title = "Shop" })
--   UI.button({ parent = panel, text = "BUY", onClick = function() ... end })
--   UI.show(panel, true)        UI.toast("Saved!")
--
-- Layout helpers for whole screens: `UI.hud` gives a safe-area root, `UI.anchor` pins groups to its
-- edges, `UI.responsive` scales a design to any screen. `UI.bar`, `UI.tabs`, `UI.modal`, `UI.scroll` and
-- `UI.grid` build on those, and `UI.focus` gives gamepads a starting button.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = {}

UI.Theme = {
	primary = Color3.fromRGB(255, 200, 40),
	secondary = Color3.fromRGB(170, 90, 255),
	danger = Color3.fromRGB(235, 75, 75),
	success = Color3.fromRGB(70, 200, 120),
	background = Color3.fromRGB(18, 16, 28),
	surface = Color3.fromRGB(34, 30, 52),
	text = Color3.new(1, 1, 1),
	textOutline = Color3.fromRGB(45, 20, 75),
	font = Enum.Font.FredokaOne,
	corner = 14,
	stroke = 3,
	minTouchSize = 48, -- px; keeps buttons tappable on phones
	-- Shape language (defaults reproduce the V1 look; set them from the game's art direction):
	buttonFill = "gradient" :: "gradient" | "flat" | "outline",
	buttonStroke = Color3.new(1, 1, 1),
	displayFont = nil :: Enum.Font?, -- titles; defaults to `font`
	panelStroke = nil :: Color3?, -- defaults to `secondary`
	panelTransparency = 0.05,
	textStrokeWidth = 3, -- button text outline; 0 for none
	labelStroke = 2, -- label text outline; 0 for none (dark text on light panels)
}

-- Applies a partial theme (e.g. from the game's art direction) in one call.
function UI.useTheme(patch: { [string]: any })
	local theme = UI.Theme :: any
	for key, value in patch do
		assert(theme[key] ~= nil or key == "displayFont" or key == "panelStroke", `UI.useTheme: unknown key '{key}'`)
		theme[key] = value
	end
end

export type Style = "primary" | "secondary" | "danger" | "success"

local function tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t =
		TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local s = Instance.new("UIScale")
	s.Parent = gui
	return s
end

local function corner(gui: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UI.Theme.corner)
	c.Parent = gui
end

local function textStroke(gui: GuiObject, thickness: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = UI.Theme.textOutline
	s.Thickness = thickness or 2
	s.Parent = gui
end

-- Full-screen ScreenGui in the local player's PlayerGui (reused if it already exists).
function UI.screen(name: string, displayOrder: number?): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0
	gui.Parent = playerGui
	return gui
end

export type ButtonProps = {
	parent: Instance?,
	text: string,
	style: Style?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	onClick: (() -> ())?,
	pulse: boolean?, -- gentle breathing scale to draw attention
	name: string?,
}

-- Gradient button with stroke, hover/press feedback and optional pulse.
function UI.button(p: ButtonProps): TextButton
	local theme = UI.Theme
	local color = (theme :: any)[p.style or "primary"] :: Color3
	local b = Instance.new("TextButton")
	b.Name = p.name or p.text
	b.Text = p.text
	b.Font = theme.font
	b.TextSize = p.textSize or 32
	b.TextColor3 = theme.text
	b.AutoButtonColor = false
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Size = p.size or UDim2.fromOffset(240, 64)
	b.Position = p.position or UDim2.new()
	b.AnchorPoint = p.anchor or Vector2.zero
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(theme.minTouchSize, theme.minTouchSize)
	sizeConstraint.Parent = b
	corner(b)
	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = theme.buttonStroke
	border.Thickness = theme.stroke
	border.Parent = b
	if theme.buttonFill == "flat" then
		b.BackgroundColor3 = color
	elseif theme.buttonFill == "outline" then
		b.BackgroundColor3 = theme.surface
		b.BackgroundTransparency = 0.35
		b.TextColor3 = color
		border.Color = color
	else
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.35))
		gradient.Rotation = 90
		gradient.Parent = b
	end
	if theme.textStrokeWidth > 0 then
		textStroke(b, theme.textStrokeWidth)
	end

	local scale = scaleOf(b)
	local rest = 1
	local pulseTween: Tween? = nil
	local function settle(target: number)
		rest = target
		tween(scale, 0.12, { Scale = target })
	end
	b.MouseEnter:Connect(function()
		settle(1.06)
	end)
	b.MouseLeave:Connect(function()
		settle(1)
	end)
	b.SelectionGained:Connect(function()
		settle(1.06)
	end)
	b.SelectionLost:Connect(function()
		settle(1)
	end)
	b.MouseButton1Down:Connect(function()
		tween(scale, 0.06, { Scale = rest * 0.92 })
	end)
	b.MouseButton1Up:Connect(function()
		tween(scale, 0.12, { Scale = rest }, Enum.EasingStyle.Back)
	end)
	if p.onClick then
		b.Activated:Connect(p.onClick)
	end
	if p.pulse then
		pulseTween = TweenService:Create(
			scale,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.06 }
		)
		local function updatePulse()
			if not pulseTween then
				return
			end
			if b.Visible then
				pulseTween:Play()
			else
				pulseTween:Cancel()
			end
		end
		b:GetPropertyChangedSignal("Visible"):Connect(updatePulse)
		updatePulse()
	end
	b.Parent = p.parent
	return b
end

export type LabelProps = {
	parent: Instance?,
	text: string,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	color: Color3?,
	scaled: boolean?, -- TextScaled: fills the label's box
	name: string?,
}

function UI.label(p: LabelProps): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = p.name or "Label"
	l.Text = p.text
	l.Font = UI.Theme.font
	l.TextSize = p.textSize or 28
	l.TextScaled = p.scaled == true
	l.TextColor3 = p.color or UI.Theme.text
	l.BackgroundTransparency = 1
	l.Size = p.size or UDim2.new(1, 0, 0, (p.textSize or 28) + 8)
	l.Position = p.position or UDim2.new()
	l.AnchorPoint = p.anchor or Vector2.zero
	if UI.Theme.labelStroke > 0 then
		textStroke(l, UI.Theme.labelStroke)
	end
	l.Parent = p.parent
	return l
end

export type PanelProps = {
	parent: Instance?,
	size: UDim2,
	position: UDim2?, -- default: screen centre
	anchor: Vector2?,
	title: string?,
	padding: number?,
	name: string?,
}

-- Rounded surface with stroke and padding. Children added later are laid out top-to-bottom.
function UI.panel(p: PanelProps): Frame
	local theme = UI.Theme
	local f = Instance.new("Frame")
	f.Name = p.name or p.title or "Panel"
	f.Size = p.size
	f.Position = p.position or UDim2.fromScale(0.5, 0.5)
	f.AnchorPoint = p.anchor or Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = theme.surface
	f.BackgroundTransparency = theme.panelTransparency
	corner(f, theme.corner + 4)
	local border = Instance.new("UIStroke")
	border.Color = theme.panelStroke or theme.secondary
	border.Thickness = theme.stroke
	border.Parent = f
	local pad = Instance.new("UIPadding")
	local px = UDim.new(0, p.padding or 16)
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = px, px, px, px
	pad.Parent = f
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	if p.title then
		local t = UI.label({ parent = f, text = p.title, textSize = 36, color = theme.primary, name = "Title" })
		t.Font = theme.displayFont or theme.font
		t.LayoutOrder = -1
	end
	f.Parent = p.parent
	return f
end

local showStates = setmetatable({} :: { [GuiObject]: { tween: Tween? } }, { __mode = "k" })

-- Show/hide with a pop animation. Cancel superseded animations before starting a new one.
function UI.show(gui: GuiObject, visible: boolean)
	local scale = scaleOf(gui)
	local token = (gui:GetAttribute("UIShowToken") :: number? or 0) + 1
	gui:SetAttribute("UIShowToken", token)
	local state = showStates[gui]
	if not state then
		state = { tween = nil }
		showStates[gui] = state
		gui.Destroying:Once(function()
			local current = showStates[gui]
			showStates[gui] = nil
			if current and current.tween then
				current.tween:Cancel()
			end
		end)
	end
	if state.tween then
		state.tween:Cancel()
	end
	if visible then
		gui.Visible = true
		scale.Scale = 0.6
		state.tween = tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		state.tween = tween(scale, 0.12, { Scale = 0.6 })
	end
	(state.tween :: Tween).Completed:Once(function(playback)
		if playback == Enum.PlaybackState.Completed and gui:GetAttribute("UIShowToken") == token then
			state.tween = nil
			if not visible then
				gui.Visible = false
				scale.Scale = 1
			end
		end
	end)
end

-- Short notification that stacks at the top of the screen and fades out.
function UI.toast(text: string, opts: { color: Color3?, duration: number? }?)
	local gui = UI.screen("UIToasts", 50)
	local holder = gui:FindFirstChild("Stack") :: Frame?
	if not holder then
		local h = Instance.new("Frame")
		h.Name = "Stack"
		h.BackgroundTransparency = 1
		h.Size = UDim2.fromScale(0.5, 0.4)
		h.Position = UDim2.fromScale(0.5, 0.08)
		h.AnchorPoint = Vector2.new(0.5, 0)
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 8)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Parent = h
		h.Parent = gui
		holder = h
	end
	local l = UI.label({ parent = holder, text = text, textSize = 28, color = opts and opts.color, name = "Toast" })
	l.Size = UDim2.new(1, 0, 0, 40)
	UI.show(l, true)
	task.delay(opts and opts.duration or 2.5, function()
		tween(l, 0.4, { TextTransparency = 1 })
		task.wait(0.4)
		l:Destroy()
	end)
end

----------------------------------------------------------------------------------------------------
-- Layout

export type Corner =
	"topLeft"
	| "top"
	| "topRight"
	| "left"
	| "center"
	| "right"
	| "bottomLeft"
	| "bottom"
	| "bottomRight"

local CORNERS: { [string]: Vector2 } = {
	topLeft = Vector2.new(0, 0),
	top = Vector2.new(0.5, 0),
	topRight = Vector2.new(1, 0),
	left = Vector2.new(0, 0.5),
	center = Vector2.new(0.5, 0.5),
	right = Vector2.new(1, 0.5),
	bottomLeft = Vector2.new(0, 1),
	bottom = Vector2.new(0.5, 1),
	bottomRight = Vector2.new(1, 1),
}

-- Position and AnchorPoint that pin something to a screen edge, `margin` px in (pure).
function UI.anchorFor(edge: Corner, margin: number?): (UDim2, Vector2)
	local point = CORNERS[edge]
	assert(point, `UI.anchorFor: unknown corner '{tostring(edge)}'`)
	local m = margin or 0
	return UDim2.new(point.X, (1 - 2 * point.X) * m, point.Y, (1 - 2 * point.Y) * m), point
end

-- The scale that fits a design size on a viewport, clamped so text stays legible (pure).
function UI.viewScale(viewport: Vector2, design: Vector2?, min: number?, max: number?): number
	local base = design or Vector2.new(1280, 720)
	local fit = math.min(viewport.X / base.X, viewport.Y / base.Y)
	return math.clamp(fit, min or 0.6, max or 1.5)
end

-- Fill of a bar in 0..1 (pure). A zero or negative maximum reads as empty.
function UI.barFill(value: number, max: number): number
	if max <= 0 or value ~= value then
		return 0
	end
	return math.clamp(value / max, 0, 1)
end

-- Cell size for `columns` equal columns that fill their parent, with `gap` px between them (pure).
function UI.gridCell(columns: number, height: number, gap: number?): UDim2
	assert(columns >= 1 and columns % 1 == 0, "UI.gridCell: columns must be a positive integer")
	local g = gap or 0
	return UDim2.new(1 / columns, -g * (columns - 1) / columns, 0, height)
end

-- A root frame inside the safe area, in the ScreenGui `name`: clear of the Roblox top bar (GuiService
-- insets), and of notches through the ScreenGui's insets. Children use scale; keeps up when insets change.
function UI.hud(name: string, displayOrder: number?): Frame
	local gui = UI.screen(name, displayOrder)
	local existing = gui:FindFirstChild("Safe")
	if existing and existing:IsA("Frame") then
		return existing
	end
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local root = Instance.new("Frame")
	root.Name = "Safe"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	local pad = Instance.new("UIPadding")
	local function update()
		local topLeft, bottomRight = GuiService:GetGuiInset()
		pad.PaddingTop = UDim.new(0, topLeft.Y)
		pad.PaddingLeft = UDim.new(0, topLeft.X)
		pad.PaddingRight = UDim.new(0, bottomRight.X)
		pad.PaddingBottom = UDim.new(0, bottomRight.Y)
	end
	update()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(update)
	pad.Parent = root
	root.Parent = gui
	return root
end

export type AnchorProps = { parent: Instance, corner: Corner, size: UDim2?, margin: number?, name: string? }

-- A transparent group pinned to an edge of the parent (usually `UI.hud`). Lay children out inside it.
function UI.anchor(p: AnchorProps): Frame
	local position, point = UI.anchorFor(p.corner, p.margin or 12)
	local f = Instance.new("Frame")
	f.Name = p.name or p.corner
	f.BackgroundTransparency = 1
	f.AnchorPoint = point
	f.Position = position
	f.Size = p.size or UDim2.fromOffset(240, 80)
	f.Parent = p.parent
	return f
end

-- Scales a frame designed at `design` px to fit the screen, now and on every resize. Returns a stop function.
function UI.responsive(gui: GuiObject, design: Vector2?, min: number?, max: number?): () -> ()
	local scale = scaleOf(gui)
	local camera = workspace.CurrentCamera
	local function update()
		scale.Scale = UI.viewScale(camera.ViewportSize, design, min, max)
	end
	update()
	local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return function()
		connection:Disconnect()
	end
end

-- Puts gamepad focus on `target`, or on the first button under it, when a gamepad is in use. Returns
-- what it selected. Mouse and touch players see no change. UI.tabs and UI.modal do this for you.
function UI.focus(target: GuiObject): GuiObject?
	if not UserInputService.GamepadEnabled then
		return nil
	end
	local choice: GuiObject? = if target:IsA("GuiButton")
		then target
		else target:FindFirstChildWhichIsA("GuiButton", true)
	if choice then
		GuiService.SelectedObject = choice
	end
	return choice
end

export type BarProps = {
	parent: Instance?,
	value: number?,
	max: number?,
	color: Color3?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	label: boolean?, -- shows "value / max"
	name: string?,
}
export type Bar = { frame: Frame, fill: Frame, value: number, max: number, set: (value: number, max: number?) -> () }

-- A meter (health, stamina, progress). `bar.set(value, max?)` eases to the new fill.
function UI.bar(p: BarProps): Bar
	local theme = UI.Theme
	local f = Instance.new("Frame")
	f.Name = p.name or "Bar"
	f.Size = p.size or UDim2.new(1, 0, 0, 24)
	f.Position = p.position or UDim2.new()
	f.AnchorPoint = p.anchor or Vector2.zero
	f.BackgroundColor3 = theme.surface
	f.BackgroundTransparency = theme.panelTransparency
	corner(f, 8)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = p.color or theme.primary
	corner(fill, 8)
	fill.Parent = f
	local text: TextLabel? = nil
	if p.label then
		text = UI.label({ parent = f, text = "", size = UDim2.fromScale(1, 1), scaled = true, name = "Text" })
	end
	local bar: Bar
	local function show(value: number, maximum: number)
		if text then
			text.Text = `{math.floor(value + 0.5)} / {math.floor(maximum + 0.5)}`
		end
	end
	bar = {
		frame = f,
		fill = fill,
		value = p.value or 1,
		max = p.max or 1,
		set = function(value: number, maximum: number?)
			bar.value, bar.max = value, maximum or bar.max
			tween(fill, 0.25, { Size = UDim2.fromScale(UI.barFill(bar.value, bar.max), 1) })
			show(bar.value, bar.max)
		end,
	}
	fill.Size = UDim2.fromScale(UI.barFill(bar.value, bar.max), 1)
	show(bar.value, bar.max)
	f.Parent = p.parent
	return bar
end

export type ScrollProps = {
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	padding: number?, -- gap between items
	name: string?,
}

-- A vertical list that scrolls when its children outgrow it (wheel, touch, thumbstick).
function UI.scroll(p: ScrollProps): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = p.name or "Scroll"
	s.Size = p.size or UDim2.fromScale(1, 1)
	s.Position = p.position or UDim2.new()
	s.AnchorPoint = p.anchor or Vector2.zero
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 8
	s.ScrollBarImageColor3 = UI.Theme.secondary
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, p.padding or 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = s
	s.Parent = p.parent
	return s
end

export type GridProps = {
	parent: Instance?,
	columns: number?, -- fills the width with this many columns, default 3
	cellHeight: number?, -- px, default 96
	gap: number?, -- px, default 8
	size: UDim2?,
	position: UDim2?,
	name: string?,
}

-- An item grid; children fill its cells in order. Put it in `UI.scroll` for long inventories.
function UI.grid(p: GridProps): Frame
	local gap = p.gap or 8
	local f = Instance.new("Frame")
	f.Name = p.name or "Grid"
	f.BackgroundTransparency = 1
	f.Size = p.size or UDim2.fromScale(1, 0)
	f.Position = p.position or UDim2.new()
	f.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UI.gridCell(p.columns or 3, p.cellHeight or 96, gap)
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = f
	f.Parent = p.parent
	return f
end

export type TabsProps = {
	parent: Instance?,
	tabs: { { id: string, text: string } },
	selected: string?, -- default: the first tab
	onSelect: ((string) -> ())?,
	size: UDim2?,
	position: UDim2?,
	name: string?,
}
export type Tabs = {
	frame: Frame,
	pages: { [string]: Frame }, -- put each tab's content here
	buttons: { [string]: TextButton },
	selected: string,
	select: (id: string) -> (),
}

-- A row of tab buttons over swapping pages.
function UI.tabs(p: TabsProps): Tabs
	assert(#p.tabs > 0, "UI.tabs needs at least one tab")
	local f = Instance.new("Frame")
	f.Name = p.name or "Tabs"
	f.BackgroundTransparency = 1
	f.Size = p.size or UDim2.fromScale(1, 1)
	f.Position = p.position or UDim2.new()
	local height = UI.Theme.minTouchSize
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, height)
	row.Parent = f
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	local tabs: Tabs
	tabs = {
		frame = f,
		pages = {},
		buttons = {},
		selected = p.selected or p.tabs[1].id,
		select = function(id: string)
			assert(tabs.pages[id], `UI.tabs: no tab '{id}'`)
			tabs.selected = id
			for key, page in tabs.pages do
				page.Visible = key == id
				tabs.buttons[key].BackgroundTransparency = if key == id then 0 else 0.5
			end
			if p.onSelect then
				p.onSelect(id)
			end
		end,
	}
	local width = UDim2.new(1 / #p.tabs, -6 * (#p.tabs - 1) / #p.tabs, 1, 0)
	for order, tab in p.tabs do
		local button = UI.button({
			parent = row,
			text = tab.text,
			style = "secondary",
			size = width,
			textSize = 22,
			name = tab.id,
			onClick = function()
				tabs.select(tab.id)
			end,
		})
		button.LayoutOrder = order
		tabs.buttons[tab.id] = button
		local page = Instance.new("Frame")
		page.Name = tab.id
		page.BackgroundTransparency = 1
		page.Position = UDim2.fromOffset(0, height + 8)
		page.Size = UDim2.new(1, 0, 1, -(height + 8))
		page.Visible = false
		page.Parent = f
		tabs.pages[tab.id] = page
	end
	tabs.select(tabs.selected)
	f.Parent = p.parent
	UI.focus(tabs.buttons[tabs.selected])
	return tabs
end

export type ModalProps = {
	title: string?,
	text: string?,
	size: UDim2?, -- default 50% by 40% of the screen, never below 320 by 200 px
	buttons: { { text: string, style: Style?, onClick: (() -> ())? } }?, -- each closes the modal
	onClose: (() -> ())?,
	dismissable: boolean?, -- false: only the buttons close it; default true (gamepad B)
	parent: Instance?, -- default its own top-level ScreenGui
}
export type Modal = { frame: Frame, panel: Frame, close: () -> () }

local modalCount = 0

-- A centred dialog over a dimmed screen that blocks input behind it. Gamepads get the first button and
-- stay inside the dialog; closing returns focus to wherever it was. Default buttons: one OK.
function UI.modal(p: ModalProps): Modal
	local dim = Instance.new("Frame")
	dim.Name = "Modal"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Active = true
	local panel = UI.panel({ parent = dim, size = p.size or UDim2.fromScale(0.5, 0.4), title = p.title })
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(320, 200)
	limit.Parent = panel
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	if p.text then
		local body = UI.label({ parent = panel, text = p.text, textSize = 24, name = "Body" })
		body.TextWrapped = true
		body.Size = UDim2.new(1, 0, 1, -(UI.Theme.minTouchSize + 64))
		body.LayoutOrder = 1
	end
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, UI.Theme.minTouchSize + 8)
	row.LayoutOrder = 2
	row.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row

	modalCount += 1
	local actionName = `UIModalBack{modalCount}`
	local previous = GuiService.SelectedObject
	local closed = false
	local modal: Modal
	modal = {
		frame = dim,
		panel = panel,
		close = function()
			if closed then
				return
			end
			closed = true
			ContextActionService:UnbindAction(actionName)
			dim:Destroy()
			if GuiService.SelectedObject == nil and previous and previous.Parent then
				GuiService.SelectedObject = previous
			end
			if p.onClose then
				p.onClose()
			end
		end,
	}
	local buttons: { { text: string, style: Style?, onClick: (() -> ())? } } = p.buttons or { { text = "OK" } }
	local first: TextButton? = nil
	for order, spec in buttons do
		local button = UI.button({
			parent = row,
			text = spec.text,
			style = spec.style,
			size = UDim2.new(1 / #buttons, -10, 1, 0),
			textSize = 24,
			onClick = function()
				modal.close()
				if spec.onClick then
					spec.onClick()
				end
			end,
		})
		button.LayoutOrder = order
		first = first or button
	end
	dim.Parent = p.parent or UI.screen("UIModals", 90)
	if p.dismissable ~= false then
		ContextActionService:BindAction(actionName, function(_, state)
			if state == Enum.UserInputState.Begin then
				modal.close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB)
	end
	if first then
		UI.focus(first)
	end
	UI.show(panel, true)
	return modal
end

return UI
