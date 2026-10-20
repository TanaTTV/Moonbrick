--!strict
-- Neon Frontier client: dresses the street, lights the neon signs (with failing tubes), strings power
-- cables between the pylons, adds drifting dust and the town's hum, and opens the bounty board.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = ReplicatedStorage:WaitForChild("Kit")
local Audio = require(Kit:WaitForChild("Audio"))
local Geo = require(Kit:WaitForChild("Geo"))
local Scheduler = require(Kit:WaitForChild("Scheduler"))
local Tex = require(Kit:WaitForChild("Tex"))

-- Effect textures and sounds: local previews from `python scripts/fxtex.py preview` and
-- `python scripts/sfx.py preview` in Studio. A published game needs the owner to upload them first.
if RunService:IsStudio() then
	Tex.usePreview()
end
require(script.Parent:WaitForChild("Props"))
local BountyCard = require(script.Parent:WaitForChild("BountyCard"))
local Frontier = (require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Frontier")) :: any) :: {
	flicker: (number, number, number) -> number,
	bounties: { { name: string, crime: string, reward: number, threat: number } },
	money: (number) -> string,
}

local world = workspace:WaitForChild("World")
local scene = world:WaitForChild("Scene")
Geo.dress(scene)
Geo.dress(world:WaitForChild("Backdrop"))

-- Neon signs: lettering on both broad faces of each plate, a coloured light on the street, and a
-- flicker job driven by the sign's Flicker attribute.
type Sign = { labels: { TextLabel }, strokes: { UIStroke }, light: PointLight, amount: number, seed: number }
local signs: { Sign } = {}

local function faces(part: BasePart): { Enum.NormalId }
	local s = part.Size
	if s.X <= s.Y and s.X <= s.Z then
		return { Enum.NormalId.Left, Enum.NormalId.Right }
	elseif s.Z <= s.Y then
		return { Enum.NormalId.Front, Enum.NormalId.Back }
	end
	return { Enum.NormalId.Top, Enum.NormalId.Bottom }
end

local function makeSign(part: BasePart, index: number)
	local text = part:GetAttribute("Sign") :: string
	local color = Color3.new(
		part:GetAttribute("SignR") :: number? or 1,
		part:GetAttribute("SignG") :: number? or 1,
		part:GetAttribute("SignB") :: number? or 1
	)
	if part:GetAttribute("Vertical") then
		text = table.concat(string.split(text, ""), "\n")
	end
	local sign: Sign = {
		labels = {},
		strokes = {},
		light = Instance.new("PointLight"),
		amount = part:GetAttribute("Flicker") :: number? or 0,
		seed = index,
	}
	-- TextScaled stops at 100 px, so size the canvas to the plate: its short side is ~130 px.
	local dims = { part.Size.X, part.Size.Y, part.Size.Z }
	table.sort(dims)
	local pixelsPerStud = math.clamp(130 / dims[2], 8, 80)
	for _, face in faces(part) do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = pixelsPerStud
		surface.LightInfluence = 0
		surface.Brightness = 2.5
		surface.Parent = part
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.92, 0.86)
		label.Position = UDim2.fromScale(0.04, 0.07)
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.Sarpanch
		label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.55) -- tube core runs hotter than its glow
		label.Parent = surface
		local glow = Instance.new("UIStroke")
		glow.Color = color
		glow.Thickness = 3
		glow.Transparency = 0.15
		glow.Parent = label
		table.insert(sign.labels, label)
		table.insert(sign.strokes, glow)
	end
	sign.light.Color = color
	sign.light.Range = 16
	sign.light.Brightness = 1.6
	sign.light.Shadows = false
	sign.light.Parent = part
	table.insert(signs, sign)
end

local index = 0
for _, root in { scene, world:WaitForChild("Backdrop") } do
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Sign") then
			index += 1
			makeSign(part, index)
		end
	end
end

local clock = 0
Scheduler.every(function(dt)
	clock += dt
	for _, sign in signs do
		if sign.amount > 0 then
			local k = Frontier.flicker(clock, sign.amount, sign.seed)
			for i, label in sign.labels do
				label.TextTransparency = 1 - k
				sign.strokes[i].Transparency = 1 - k * 0.85
			end
			sign.light.Brightness = 1.6 * k
		end
	end
	return false
end)

-- Power cables: two sagging lines between each pair of neighbouring pylons.
local pylons = {}
for _, part in scene:GetChildren() do
	if part:IsA("BasePart") and part.Name:match("^Pylon%d+$") then
		table.insert(pylons, part)
	end
end
local function order(part: BasePart): number
	return tonumber(part.Name:match("%d+")) or 0
end
table.sort(pylons, function(a, b)
	return order(a) < order(b)
end)
local function arm(pylon: BasePart, x: number): Attachment
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(x * pylon.Size.X * 0.47, pylon.Size.Y * 0.36, 0)
	a.Parent = pylon
	return a
end
for i = 1, #pylons - 1 do
	for _, x in { -1, 1 } do
		local beam = Instance.new("Beam")
		beam.Attachment0 = arm(pylons[i], x)
		beam.Attachment1 = arm(pylons[i + 1], x)
		beam.Width0, beam.Width1 = 0.09, 0.09
		beam.Color = ColorSequence.new(Color3.fromRGB(24, 20, 28))
		beam.Transparency = NumberSequence.new(0)
		beam.LightInfluence = 1
		beam.Segments = 12
		beam.CurveSize0, beam.CurveSize1 = -2.2, 2.2
		beam.FaceCamera = true
		beam.Parent = pylons[i]
	end
end

-- Dust drifting across the street on the evening wind.
local dustField = Instance.new("Part")
dustField.Name = "Dust"
dustField.Anchored, dustField.CanCollide, dustField.CanQuery, dustField.CanTouch = true, false, false, false
dustField.Transparency = 1
dustField.Size = Vector3.new(40, 4, 110)
dustField.CFrame = CFrame.new(-10, 2, 0)
local dust = Instance.new("ParticleEmitter")
dust.Shape = Enum.ParticleEmitterShape.Box
dust.Rate = 10
dust.Lifetime = NumberRange.new(5, 8)
dust.Speed = NumberRange.new(3, 6)
dust.EmissionDirection = Enum.NormalId.Right
dust.SpreadAngle = Vector2.new(15, 15)
dust.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 2),
	NumberSequenceKeypoint.new(1, 5),
})
dust.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.86),
	NumberSequenceKeypoint.new(1, 1),
})
dust.Color = ColorSequence.new(Color3.fromRGB(214, 160, 140))
dust.RotSpeed = NumberRange.new(-20, 20)
Tex.apply(dust, "smoke")
dust.Parent = dustField
dustField.Parent = workspace

Audio.loop("rbxasset://sounds/moonbrick/wind.wav", nil, { volume = 0.3, fade = 2 })
Audio.loop("rbxasset://sounds/moonbrick/buzz.wav", scene:FindFirstChild("Sign-1_0") :: BasePart?, { volume = 0.25 })

local board = scene:WaitForChild("BountyBoard")
local prompt = board:WaitForChild("Prompt") :: ProximityPrompt
prompt.Triggered:Connect(BountyCard.toggle)
