--!strict
-- Element Brawl client: side-on camera, 2D movement with a double jump, attack input on every device,
-- launches told by the server, and a Smash-style damage HUD.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Kit = ReplicatedStorage:WaitForChild("Kit")
local Net = require(Kit:WaitForChild("Net"))
local UI = require(Kit:WaitForChild("UI"))
local VFX = require(Kit:WaitForChild("VFX"))
-- WaitForChild loses the module's type; restate the parts this script uses.
type Element = { id: string, name: string, color: Color3, glow: Color3, blurb: string, special: { name: string } }
local Elements = (require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Elements")) :: any) :: {
	order: { string },
	byId: { [string]: Element },
}

type FighterState = {
	name: string,
	element: string,
	percent: number,
	stocks: number,
	bot: boolean,
	passive: boolean?,
	userId: number,
	out: boolean,
}
type RoundState = { state: string, remaining: number, roundId: number }

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local controls = (require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any):GetControls()

local stunUntil = 0
local doubleJumpUsed = false
local lastJump = 0
local roundState: RoundState = { state = "Waiting", remaining = 0, roundId = 0 }
local fighters: { FighterState } = {}

local function character(): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and root and root:IsA("BasePart") and humanoid then
		return model, root, humanoid
	end
	return nil, nil, nil
end

-- Movement: keep the default controls (thumbstick, keys, gamepad) but only use their left/right part.
local facing = 1
RunService:BindToRenderStep("BrawlMove", Enum.RenderPriority.Input.Value + 1, function()
	local _, _, humanoid = character()
	if humanoid and os.clock() >= stunUntil then
		local move = controls:GetMoveVector()
		local x = math.clamp(move.X, -1, 1)
		if math.abs(x) > 0.2 then
			facing = if x < 0 then -1 else 1
		end
		humanoid:Move(Vector3.new(x, 0, 0), false)
	end
end)

-- Fighters live on the z = 0 plane and turn three-quarters toward the camera, like a platform fighter,
-- so the side view never shows a paper-thin profile. Look direction X still says which way they face.
RunService.Heartbeat:Connect(function()
	local model, root, humanoid = character()
	if not (model and root and humanoid and model:GetAttribute("Fighting")) then
		return
	end
	if math.abs(root.Position.Z) > 0.05 then
		root.CFrame -= Vector3.new(0, 0, root.Position.Z)
		root.AssemblyLinearVelocity *= Vector3.new(1, 1, 0)
	end
	if os.clock() >= stunUntil and not humanoid.PlatformStand then
		humanoid.AutoRotate = false
		root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(facing * 0.82, 0, 0.57))
	end
end)

UserInputService.JumpRequest:Connect(function()
	local _, root, humanoid = character()
	if not root or not humanoid or os.clock() < stunUntil or os.clock() - lastJump < 0.25 then
		return
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Freefall and not doubleJumpUsed then
		doubleJumpUsed, lastJump = true, os.clock()
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 62, 0)
		VFX.burst(root.Position - Vector3.new(0, 2.5, 0), { color = Color3.new(1, 1, 1), count = 12, size = 1.2 })
	elseif humanoid.FloorMaterial ~= Enum.Material.Air then
		lastJump = os.clock()
	end
end)

local function onCharacter(model: Model)
	local humanoid = model:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				doubleJumpUsed = false
			end
		end)
	end
	stunUntil, doubleJumpUsed = 0, false
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Attacks: mouse/keys, gamepad and on-screen touch buttons all reach the same server request.
local function bind(action: string, kind: string, title: string, ...: Enum.KeyCode | Enum.UserInputType)
	ContextActionService:BindAction(action, function(_, state)
		if state == Enum.UserInputState.Begin and os.clock() >= stunUntil then
			Net.fireServer("Attack", kind)
		end
		return Enum.ContextActionResult.Sink
	end, true, ...)
	ContextActionService:SetTitle(action, title)
end
bind("BrawlStrike", "strike", "HIT", Enum.UserInputType.MouseButton1, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
bind("BrawlSpecial", "special", "POW", Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
ContextActionService:SetPosition("BrawlStrike", UDim2.new(1, -170, 1, -150))
ContextActionService:SetPosition("BrawlSpecial", UDim2.new(1, -110, 1, -210))

-- Launches from the server.
Net.listen("Knockback", function(velocity: Vector3, stun: number)
	local _, root, humanoid = character()
	if not root or not humanoid then
		return
	end
	stunUntil = os.clock() + stun
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity =
		Vector3.new(0, 0, (if velocity.X > 0 then -1 else 1) * math.min(velocity.Magnitude / 12, 14))
	local power = math.clamp(velocity.Magnitude / 140, 0.15, 1)
	VFX.shake(0.2 + power * 0.35, 0.4 + power * 1.6)
	if power > 0.6 then
		VFX.fovPunch(8 * power, 0.35)
		VFX.flash({ color = Color3.new(1, 1, 1), time = 0.12 })
	end
	task.delay(stun, function()
		if os.clock() >= stunUntil - 0.01 and humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			doubleJumpUsed = false -- one recovery jump after every launch
		end
	end)
end)

Net.listen("Dash", function(direction: number)
	local _, root = character()
	if not root then
		return
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if os.clock() - started > 0.18 or not root.Parent then
			connection:Disconnect()
			return
		end
		root.AssemblyLinearVelocity = Vector3.new(direction * 95, math.max(root.AssemblyLinearVelocity.Y, 6), 0)
	end)
	VFX.fovPunch(5, 0.25)
end)

Net.listen("Blink", function(x: number)
	local _, root = character()
	if root then
		root.CFrame = CFrame.new(x, root.Position.Y + 1, 0) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.new(0, 20, 0)
		VFX.flash({ color = Elements.byId.Storm.glow, time = 0.1 })
	end
end)

Net.listen("Slow", function(seconds: number)
	local _, _, humanoid = character()
	if humanoid then
		humanoid.WalkSpeed = 8
		task.delay(seconds, function()
			humanoid.WalkSpeed = 24
		end)
	end
end)

-- Side-on camera that frames every fighter, like a platform fighter.
camera.CameraType = Enum.CameraType.Scriptable
local view = CFrame.lookAt(Vector3.new(0, 30, 110), Vector3.new(0, 10, 0))
local function fighterRoots(): { BasePart }
	local roots = {}
	local function add(model: Instance?)
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and math.abs(root.Position.X) < 160 and root.Position.Y > -70 then
			table.insert(roots, root)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character and other.Character:GetAttribute("Fighting") then
			add(other.Character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			add(model)
		end
	end
	return roots
end
RunService:BindToRenderStep("BrawlCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	local roots = fighterRoots()
	local minX, maxX, minY, maxY = -30, 30, 0, 20
	if #roots > 0 then
		minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, root in roots do
			local p = root.Position
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
		end
	end
	local center = Vector3.new((minX + maxX) / 2, math.max((minY + maxY) / 2, -10) + 4, 0)
	local spread = math.max(maxX - minX, (maxY - minY) * 1.6)
	local distance = math.clamp(spread * 0.85 + 44, 70, 140)
	-- Aim a little below the fighters so the action sits above the damage cards.
	local aim = center - Vector3.new(0, distance * 0.14, 0)
	local goal = CFrame.lookAt(aim + Vector3.new(0, 6 + distance * 0.1, distance), aim)
	view = view:Lerp(goal, 1 - math.exp(-dt * 4))
	camera.CFrame = view * VFX.shakeOffset()
	camera.FieldOfView = 50
end)

-- HUD -------------------------------------------------------------------------------------------
local gui = UI.screen("BrawlHUD", 5)
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.ResetOnSpawn = false
local scale = Instance.new("UIScale")
scale.Parent = gui

local status = UI.label({
	parent = gui,
	text = "ELEMENT BRAWL",
	size = UDim2.fromOffset(460, 40),
	position = UDim2.new(0.5, 0, 0, 10),
	anchor = Vector2.new(0.5, 0),
	textSize = 30,
	name = "Status",
})

local cards = Instance.new("Frame")
cards.Name = "Cards"
cards.BackgroundTransparency = 1
cards.AnchorPoint = Vector2.new(0.5, 1)
cards.Size = UDim2.fromOffset(660, 104)
cards.Parent = gui
local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardLayout.Padding = UDim.new(0, 10)
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Parent = cards

local hint = UI.label({
	parent = gui,
	text = "",
	size = UDim2.fromOffset(520, 22),
	position = UDim2.new(0, 14, 1, -14),
	anchor = Vector2.new(0, 1),
	textSize = 16,
	name = "Hint",
})
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextTransparency = 0.25

local function layout()
	local viewport = camera.ViewportSize
	scale.Scale = math.clamp(viewport.X / 900, 0.55, 1)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	-- Touch players keep the thumbstick and buttons at the bottom, so their cards move under the status line.
	cards.Position = if touch then UDim2.new(0.5, 0, 0, 160) else UDim2.new(0.5, 0, 1, -40)
	hint.Visible = not touch
	local gamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	hint.Text = if gamepad
		then "Stick move · A jump (twice in the air) · R2 strike · X special"
		else "A/D move · Space jump (twice in the air) · Click or F strike · Q special"
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
UserInputService.LastInputTypeChanged:Connect(layout)
layout()

local function percentColor(percent: number): Color3
	if percent < 60 then
		return Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 214, 80), percent / 60)
	elseif percent < 120 then
		return Color3.fromRGB(255, 214, 80):Lerp(Color3.fromRGB(255, 70, 50), (percent - 60) / 60)
	end
	return Color3.fromRGB(255, 70, 50):Lerp(Color3.fromRGB(150, 10, 20), math.clamp((percent - 120) / 80, 0, 1))
end

local cardByName: { [string]: Frame } = {}
local shownPercent: { [string]: number } = {}

local function card(f: FighterState, order: number): Frame
	local frame = cardByName[f.name]
	if not frame then
		local new = Instance.new("Frame")
		new.Name = f.name
		new.Size = UDim2.fromOffset(150, 100)
		new.BackgroundColor3 = UI.Theme.surface
		new.BackgroundTransparency = 0.15
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = new
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Thickness = 3
		stroke.Parent = new
		local function text(name: string, size: number, y: number, h: number): TextLabel
			local label = Instance.new("TextLabel")
			label.Name = name
			label.BackgroundTransparency = 1
			label.Font = UI.Theme.font
			label.TextSize = size
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.4
			label.Position = UDim2.fromOffset(0, y)
			label.Size = UDim2.new(1, 0, 0, h)
			label.Parent = new
			return label
		end
		text("Who", 16, 4, 20)
		text("Percent", 44, 22, 48)
		text("Stocks", 20, 72, 22)
		new.Parent = cards
		cardByName[f.name] = new
		frame = new
	end
	local found = frame :: Frame
	local element = Elements.byId[f.element]
	found.LayoutOrder = order
	local stroke = found:FindFirstChild("Stroke") :: UIStroke
	stroke.Color = element.color
	local who = found:FindFirstChild("Who") :: TextLabel
	who.Text = (if f.userId == player.UserId then "YOU · " else "") .. f.name
	who.TextColor3 = element.glow
	local stocks = found:FindFirstChild("Stocks") :: TextLabel
	stocks.Text = if f.passive then "practice" elseif f.stocks > 0 then string.rep("● ", f.stocks) else "OUT"
	stocks.TextColor3 = element.color
	found.BackgroundTransparency = if f.out then 0.6 else 0.15
	return found
end

local function render()
	local seen: { [string]: boolean } = {}
	for i, f in fighters do
		seen[f.name] = true
		local frame = card(f, i)
		local label = frame:FindFirstChild("Percent") :: TextLabel
		local previous = shownPercent[f.name] or 0
		shownPercent[f.name] = f.percent
		label.Text = `{f.percent}%`
		label.TextColor3 = percentColor(f.percent)
		if f.percent > previous then -- punch the number like a fighting game
			label.TextSize = 54
			VFX.tween(label, 0.25, { TextSize = 44 }, Enum.EasingStyle.Back)
		end
	end
	for name, frame in cardByName do
		if not seen[name] then
			frame:Destroy()
			cardByName[name] = nil
			shownPercent[name] = nil
		end
	end
	local s = roundState
	local seconds = math.max(0, math.ceil(s.remaining))
	status.Text = if s.state == "Playing"
		then string.format("%d:%02d", seconds // 60, seconds % 60)
		elseif s.state == "Intermission" then `Next brawl in {seconds}`
		elseif s.state == "Results" then "Results"
		else "Waiting for fighters"
end

-- Element picker between rounds.
local picker = UI.panel({
	parent = gui,
	size = UDim2.fromOffset(300, 330),
	position = UDim2.new(0, 20, 0.4, 0),
	anchor = Vector2.new(0, 0.5),
	title = "Element",
	name = "Picker",
})
local blurb = UI.label({
	parent = picker,
	text = "Pick before the round starts.",
	size = UDim2.new(1, 0, 0, 44),
	textSize = 14,
	name = "Blurb",
})
blurb.TextWrapped = true
for _, id in Elements.order do
	local element = Elements.byId[id]
	local button = UI.button({
		parent = picker,
		text = `{element.name} · {element.special.name}`,
		size = UDim2.new(1, 0, 0, 40),
		textSize = 18,
		name = id,
		onClick = function()
			Net.fireServer("PickElement", id)
			blurb.Text = element.blurb
			UI.toast(`{element.name} chosen`, { color = element.color })
		end,
	})
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(element.glow, element.color)
	end
end
local pickerShown = false
local function updatePicker()
	local want = roundState.state ~= "Playing"
	if want ~= pickerShown then
		pickerShown = want
		UI.show(picker, want)
	end
end

local function apply(list: { FighterState }?, snap: RoundState?)
	if list then
		fighters = list
	end
	if snap then
		roundState = snap
	end
	render()
	updatePicker()
end

Net.listen("BrawlState", apply)
task.spawn(function()
	local list, snap = Net.invoke("BrawlSnapshot")
	apply(list, snap)
end)

local function isMe(name: string?): boolean
	for _, f in fighters do
		if f.name == name and f.userId == player.UserId then
			return true
		end
	end
	return false
end

local function elementOf(name: string?): Element
	for _, f in fighters do
		if f.name == name then
			return Elements.byId[f.element]
		end
	end
	return Elements.byId.Fire
end

Net.listen("Hit", function(victim: string, attacker: string, power: number)
	if isMe(attacker) then
		VFX.shake(0.12 + power * 0.2, 0.3 + power)
	end
	local frame = cardByName[victim]
	if frame then
		local shake = frame:FindFirstChild("Percent") :: TextLabel
		shake.Rotation = (math.random() - 0.5) * 16 * power
		VFX.tween(shake, 0.2, { Rotation = 0 })
	end
end)

Net.listen("KO", function(victim: string, killer: string?, stocks: number)
	local element = elementOf(victim)
	if isMe(victim) then
		VFX.title("KO!", { color = element.color })
		VFX.shake(0.6, 2.5)
	elseif isMe(killer) then
		VFX.title("KO!", { color = elementOf(killer).color })
		VFX.grade({ saturation = 0.4, bloom = 0.6, time = 0.6 })
	end
	local text = if killer then `{killer} launched {victim}!` else `{victim} fell!`
	if roundState.state == "Playing" and stocks == 0 then
		text ..= " Eliminated."
	end
	UI.toast(text, { color = element.color, duration = 2.5 })
end)

Net.listen("Winner", function(name: string?, elementId: string?)
	local element = if elementId then Elements.byId[elementId] else nil
	VFX.flash({ color = if element then element.glow else Color3.new(1, 1, 1), time = 0.3 })
	VFX.title(
		if name then `{string.upper(name)} WINS!` else "DRAW!",
		{ color = if element then element.color else nil }
	)
end)
