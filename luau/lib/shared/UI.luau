--!strict
-- UI: themed components with built-in juice (pop-in, hover/press feedback, pulse) that work on
-- mouse, touch and gamepad. Client-only. Change UI.Theme once to restyle every screen.
--
--   local gui = UI.screen("Shop")
--   local panel = UI.panel({ parent = gui, size = UDim2.fromOffset(420, 300), title = "Shop" })
--   UI.button({ parent = panel, text = "BUY", onClick = function() ... end })
--   UI.show(panel, true)        UI.toast("Saved!")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

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
	textStroke(l)
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

return UI
