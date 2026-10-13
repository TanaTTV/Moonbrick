--!strict
-- VFX: one-call visual effects.
-- World effects (shockwave, sphere, pillar, burst, aura, highlight, impact) work on server or client:
-- called on the server everyone sees them; called on a client only that player does.
-- Screen effects (shake, flash, fovPunch, grade, title) are client-only.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local VFX = {}

-- Particle textures that ship with Roblox (no asset upload needed).
VFX.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

export type ImpactOptions = Options & { pillar: boolean? }
export type GradeOptions = Options & { contrast: number?, saturation: number?, bloom: number? }

export type Options = {
	color: Color3?, -- main colour (default gold)
	color2: Color3?, -- secondary colour for gradients (default purple)
	size: number?, -- final size in studs (effect-specific default)
	time: number?, -- duration in seconds (effect-specific default)
	count: number?, -- particle count for bursts
	texture: string?, -- particle texture (default VFX.Textures.Sparkle)
}

local GOLD = Color3.fromRGB(255, 200, 40)
local PURPLE = Color3.fromRGB(170, 90, 255)

local function tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end
VFX.tween = tween

local function effectPart(shape: Enum.PartType, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function numSeq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end
VFX.numSeq = numSeq

local function clientOnly(name: string)
	if not RunService:IsClient() then
		error(`VFX.{name} is client-only (it changes the local player's screen/camera)`, 3)
	end
end

-- World effects ---------------------------------------------------------------

-- Flat neon ring that expands outward along the ground.
function VFX.shockwave(position: Vector3, opts: Options?)
	local o: Options = opts or {}
	local time = o.time or 0.9
	local ring = effectPart(Enum.PartType.Cylinder, o.color or GOLD, Enum.Material.Neon)
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	local size = o.size or 70
	tween(ring, time, { Size = Vector3.new(0.3, size, size), Transparency = 1 }, Enum.EasingStyle.Quint)
	Debris:AddItem(ring, time + 0.1)
end

-- Translucent energy sphere that swells and fades.
function VFX.sphere(position: Vector3, opts: Options?)
	local o: Options = opts or {}
	local time = o.time or 0.7
	local ball = effectPart(Enum.PartType.Ball, o.color or PURPLE, Enum.Material.ForceField)
	ball.Size = Vector3.one * 2
	ball.Position = position
	ball.Parent = workspace
	tween(ball, time, { Size = Vector3.one * (o.size or 30), Transparency = 1 })
	Debris:AddItem(ball, time + 0.1)
end

-- Beam of light from the sky that narrows to nothing.
function VFX.pillar(position: Vector3, opts: Options?)
	local o: Options = opts or {}
	local time = o.time or 1.2
	local width = o.size or 8
	local beam = effectPart(Enum.PartType.Cylinder, o.color or Color3.new(1, 0.95, 0.75), Enum.Material.Neon)
	beam.Size = Vector3.new(400, width, width)
	beam.CFrame = CFrame.new(position + Vector3.new(0, 200, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Parent = workspace
	tween(beam, time, { Size = Vector3.new(400, 0.2, 0.2), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(beam, time + 0.1)
end

-- One-shot particle burst from a part, attachment or world position.
function VFX.burst(at: BasePart | Attachment | Vector3, opts: Options?)
	local o: Options = opts or {}
	local holder: Instance
	if typeof(at) == "Vector3" then
		local anchor = effectPart(Enum.PartType.Ball, Color3.new(), Enum.Material.SmoothPlastic)
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.1
		anchor.Position = at
		anchor.Parent = workspace
		holder = anchor
	else
		local a = Instance.new("Attachment")
		a.Parent = at
		holder = a
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.texture or VFX.Textures.Sparkle
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), o.color or GOLD)
	e.LightEmission = 1
	e.Size = numSeq({ { 0, o.size or 1.5 }, { 1, 0 } })
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(30, 60)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 4
	e.Rate = 0
	e.Parent = holder
	e:Emit(o.count or 150)
	Debris:AddItem(holder, 2)
end

-- Continuous fire + sparkle aura with a glow light. Returns a function that removes it.
function VFX.aura(part: BasePart, opts: Options?): () -> ()
	local o: Options = opts or {}
	local color, color2 = o.color or GOLD, o.color2 or PURPLE
	local scale = o.size or 1
	local a = Instance.new("Attachment")
	a.Name = "VFXAura"
	a.Position = Vector3.new(0, -part.Size.Y * 1.25, 0)
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = VFX.Textures.Fire
	fire.Color = ColorSequence.new(color, color2)
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Size = numSeq({ { 0, 3 * scale }, { 0.5, 2.5 * scale }, { 1, 0 } })
	fire.Transparency = numSeq({ { 0, 0.3 }, { 1, 1 } })
	fire.Lifetime = NumberRange.new(0.6, 1)
	fire.Rate = 80
	fire.Speed = NumberRange.new(6, 10)
	fire.SpreadAngle = Vector2.new(15, 15)
	fire.Acceleration = Vector3.new(0, 10, 0)
	fire.ZOffset = -1
	fire.Parent = a
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = VFX.Textures.Sparkle
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparkles.LightEmission = 1
	sparkles.Size = numSeq({ { 0, 0.5 * scale }, { 1, 0 } })
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Rate = 40
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Parent = a
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 6
	light.Range = 20 * scale
	light.Parent = part
	a.Parent = part
	return function()
		a:Destroy()
		light:Destroy()
	end
end

-- Gentle idle sparkle + light for pickups and interactables. Toggle with `.Enabled` on both.
function VFX.glow(part: BasePart, opts: Options?): (ParticleEmitter, PointLight)
	local o: Options = opts or {}
	local color = o.color or GOLD
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = o.size or 14
	light.Parent = part
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.texture or VFX.Textures.Sparkle
	e.Color = ColorSequence.new(color, o.color2 or PURPLE)
	e.LightEmission = 1
	e.Size = numSeq({ { 0, 0.6 }, { 1, 0 } })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = 25
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = part
	return e, light
end

-- Coloured glow outline on a model or part. Destroy the returned Highlight to remove it.
function VFX.highlight(target: Instance, opts: Options?): Highlight
	local o: Options = opts or {}
	local h = Instance.new("Highlight")
	h.FillColor = o.color or GOLD
	h.OutlineColor = o.color2 or Color3.new(1, 1, 1)
	h.FillTransparency = 0.55
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = target
	return h
end

-- Big impact combo: shockwave + energy sphere + particle burst (+ light pillar with `pillar = true`).
function VFX.impact(position: Vector3, opts: ImpactOptions?)
	local o: ImpactOptions = opts or {}
	VFX.shockwave(position, o)
	VFX.sphere(position + Vector3.new(0, 3, 0), { color = o.color2 or PURPLE })
	VFX.burst(position + Vector3.new(0, 3, 0), { color = o.color, count = o.count })
	if o.pillar then
		VFX.pillar(position)
	end
end

-- Screen effects (client only) --------------------------------------------------

local overlay: ScreenGui? = nil
local function getOverlay(): ScreenGui
	if overlay and overlay.Parent then
		return overlay
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VFXOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	overlay = gui
	return gui
end

local shakeStart, shakeDuration, shakeStrength = 0, 0, 0
local shakeBound = false

-- Current shake offset. Scripts that drive a Scriptable camera every frame should multiply it in:
-- camera.CFrame = myCFrame * VFX.shakeOffset()
function VFX.shakeOffset(): CFrame
	local elapsed = os.clock() - shakeStart
	if elapsed >= shakeDuration then
		return CFrame.identity
	end
	local k = shakeStrength * (1 - elapsed / shakeDuration)
	return CFrame.new((math.random() * 2 - 1) * k, (math.random() * 2 - 1) * k, 0)
end

-- Camera shake that decays over `duration`. Works with the default camera automatically.
function VFX.shake(duration: number, strength: number)
	clientOnly("shake")
	shakeStart, shakeDuration, shakeStrength = os.clock(), duration, strength
	if not shakeBound then
		shakeBound = true
		RunService:BindToRenderStep("VFXShake", Enum.RenderPriority.Camera.Value + 1, function()
			local camera = workspace.CurrentCamera
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CFrame *= VFX.shakeOffset()
			end
		end)
	end
end

-- Full-screen flash that fades out.
function VFX.flash(opts: Options?)
	clientOnly("flash")
	local o: Options = opts or {}
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = o.color or Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	f.Parent = getOverlay()
	local time = o.time or 0.8
	tween(f, time, { BackgroundTransparency = 1 })
	Debris:AddItem(f, time + 0.1)
end

-- Kick the field of view out by `amount` degrees and ease it back.
function VFX.fovPunch(amount: number, time: number?)
	clientOnly("fovPunch")
	local camera = workspace.CurrentCamera
	local base = camera:GetAttribute("VFXBaseFov") :: number? or camera.FieldOfView
	camera:SetAttribute("VFXBaseFov", base)
	camera.FieldOfView = base + amount
	tween(camera, time or 0.9, { FieldOfView = base }, Enum.EasingStyle.Quint).Completed:Once(function()
		camera:SetAttribute("VFXBaseFov", nil)
	end)
end

-- Temporary colour-grade + bloom spike that settles back to normal.
function VFX.grade(opts: GradeOptions?)
	clientOnly("grade")
	local o: GradeOptions = opts or {}
	local time = o.time or 1.5
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = o.color or Color3.fromRGB(255, 220, 140)
	cc.Contrast = o.contrast or 0.4
	cc.Saturation = o.saturation or 0.8
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = o.bloom or 2
	bloom.Size = 40
	bloom.Threshold = 0.8
	bloom.Parent = Lighting
	tween(cc, time, { TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0 })
	tween(bloom, time, { Intensity = 0 })
	Debris:AddItem(cc, time + 0.1)
	Debris:AddItem(bloom, time + 0.1)
end

-- Big text that slams onto the screen, holds, and fades.
function VFX.title(text: string, opts: Options?)
	clientOnly("title")
	local o: Options = opts or {}
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.25)
	label.Size = UDim2.fromScale(0.9, 0.18)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = o.color or GOLD
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = o.color2 or PURPLE
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 3
	scale.Parent = label
	label.Parent = getOverlay()
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	local hold = o.time or 1.4
	task.delay(hold, function()
		tween(label, 0.5, { TextTransparency = 1 })
		tween(stroke, 0.5, { Transparency = 1 })
	end)
	Debris:AddItem(label, hold + 0.6)
end

return VFX
