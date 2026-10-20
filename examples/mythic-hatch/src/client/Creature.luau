--!strict
-- The egg and the Mothling (an original moth-fox), built from Geo meshes on the client and animated
-- procedurally on the shared scheduler: hover bob, wing flaps, antenna sway. No uploads, no rig.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Geo = require(Kit:WaitForChild("Geo"))
local Motion = require(Kit:WaitForChild("Motion"))
local Scheduler = require(Kit:WaitForChild("Scheduler"))
local Tex = require(Kit:WaitForChild("Tex"))

local Creature = {}

-- Egg radius at height y (egg units: base at y = -1, tip at y = 1.35): a round ellipse, fuller below
-- the middle and narrowing toward the top, like a real egg.
local function eggRadius(y: number): number
	local u = math.clamp((y + 1) / 2.35 * 2 - 1, -1, 1) -- -1 at the base, 1 at the tip
	return math.sqrt(1 - u * u) * (1 - 0.18 * u)
end

-- A speckled egg about 2 x 2.35 studs (scale the clone), coloured per rarity look.
function Creature.egg(look: any): MeshPart
	return Geo.cached("Egg" .. look.name, function(b)
		b.colorAt = function(p: Vector3): Color3
			local n = Tex.noise(p.X * 2.6 + 4, p.Y * 2.6 + p.Z * 1.9, 7, 3)
			return if n > 0.57 then look.speckle else look.shell
		end
		local profile = {}
		for i = 0, 22 do
			local y = -1 + i / 22 * 2.35
			table.insert(profile, Vector2.new(math.max(eggRadius(y), 0.001), y))
		end
		b:lathe(profile, 28)
	end, { collision = false, color = Color3.new(1, 1, 1) })
end

export type Mothling = {
	model: Model,
	root: CFrame,
	scale: number,
	setRoot: (CFrame) -> (),
	destroy: () -> (),
}

local function part(
	template: MeshPart,
	name: string,
	material: Enum.Material,
	color: Color3,
	parent: Instance
): MeshPart
	local p = template:Clone()
	p.Name = name
	p.Material = material
	p.Color = color
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Builds a Mothling and starts its idle animation. `root` is where its feet hover above.
function Creature.mothling(look: any, root: CFrame, parent: Instance): Mothling
	local model = Instance.new("Model")
	model.Name = "Mothling"
	local body = part(
		Geo.cached("MothBody", function(b)
			b:lathe({
				Vector2.new(0.001, -0.9),
				Vector2.new(0.55, -0.7),
				Vector2.new(0.8, -0.2),
				Vector2.new(0.72, 0.35),
				Vector2.new(0.45, 0.7),
				Vector2.new(0.001, 0.8),
			}, 20)
		end),
		"Body",
		Enum.Material.SmoothPlastic,
		look.wing:Lerp(Color3.fromRGB(200, 190, 184), 0.5), -- fur picks up the rarity's tint
		model
	)
	local head = part(
		Geo.cached("MothHead", function(b)
			b:sphere(0.62, 10, 18)
		end),
		"Head",
		Enum.Material.SmoothPlastic,
		look.wing:Lerp(Color3.fromRGB(214, 204, 198), 0.62),
		model
	)
	local ruff = part(
		Geo.cached("MothRuff", function(b)
			b:torus(0.5, 0.22, 20, 8)
		end),
		"Ruff",
		Enum.Material.SmoothPlastic,
		look.wing:Lerp(Color3.new(1, 1, 1), 0.5),
		model
	)
	local eyeTemplate = Geo.cached("MothEye", function(b)
		b:sphere(0.19, 6, 10)
	end)
	local eyes = {
		part(eyeTemplate, "EyeL", Enum.Material.SmoothPlastic, Color3.fromRGB(30, 26, 40), model),
		part(eyeTemplate, "EyeR", Enum.Material.SmoothPlastic, Color3.fromRGB(30, 26, 40), model),
	}
	local antennaTemplate = Geo.cached("MothAntenna", function(b)
		local path = {}
		for i = 0, 8 do
			local t = i / 8
			table.insert(path, Vector3.new(0, t * 0.9, -0.35 * t * t))
		end
		b:tube(path, 0.035, 6)
	end)
	local tipTemplate = Geo.cached("MothTip", function(b)
		b:sphere(0.11, 6, 10)
	end)
	local antennae = {
		part(antennaTemplate, "AntennaL", Enum.Material.SmoothPlastic, Color3.fromRGB(80, 66, 70), model),
		part(antennaTemplate, "AntennaR", Enum.Material.SmoothPlastic, Color3.fromRGB(80, 66, 70), model),
	}
	local tips = {
		part(tipTemplate, "TipL", Enum.Material.Neon, look.wingTip, model),
		part(tipTemplate, "TipR", Enum.Material.Neon, look.wingTip, model),
	}
	-- Wings: a rounded leaf outline extruded thin; colour runs from the body to the tip.
	local function wingTemplate(key: string, outline: { Vector2 }, reach: number): MeshPart
		-- Wings are big on purpose: they carry the silhouette from behind the round body.
		local scaled = {}
		for _, p in outline do
			table.insert(scaled, p * 1.5)
		end
		outline = scaled
		reach *= 1.5
		return Geo.cached(key .. look.name, function(b)
			b.colorAt = function(p: Vector3): Color3
				return look.wing:Lerp(look.wingTip, math.clamp(p.Magnitude / reach, 0, 1))
			end
			b:extrude(outline, 0.06)
		end, { color = Color3.new(1, 1, 1) })
	end
	local upper = wingTemplate("MothUpperWing", {
		Vector2.new(0, 0),
		Vector2.new(0.6, -0.35),
		Vector2.new(1.4, -0.45),
		Vector2.new(1.75, -0.1),
		Vector2.new(1.5, 0.35),
		Vector2.new(0.7, 0.3),
	}, 1.8)
	local lower = wingTemplate("MothLowerWing", {
		Vector2.new(0, 0),
		Vector2.new(0.45, 0.15),
		Vector2.new(1.0, 0.55),
		Vector2.new(0.9, 0.95),
		Vector2.new(0.4, 0.8),
	}, 1.2)
	local wings = {
		{ part = part(upper, "WingUL", Enum.Material.Glass, Color3.new(1, 1, 1), model), side = -1, lower = false },
		{ part = part(upper, "WingUR", Enum.Material.Glass, Color3.new(1, 1, 1), model), side = 1, lower = false },
		{ part = part(lower, "WingLL", Enum.Material.Glass, Color3.new(1, 1, 1), model), side = -1, lower = true },
		{ part = part(lower, "WingLR", Enum.Material.Glass, Color3.new(1, 1, 1), model), side = 1, lower = true },
	}
	for _, wing in wings do
		wing.part.Transparency = 0.15
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		end
	end
	model.Parent = parent

	local state: Mothling = {
		model = model,
		root = root,
		scale = 0,
		setRoot = function() end,
		destroy = function() end,
	}
	local base: { [BasePart]: Vector3 } = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			base[p] = p.Size
		end
	end
	local t = 0
	local stop = Scheduler.every(function(dt)
		if not model.Parent then
			return true
		end
		t += dt
		local s = state.scale
		for p, size in base do
			p.Size = size * math.max(s, 0.01)
		end
		local bob = math.sin(t * 2.4) * 0.22
		local squash = 1 + math.sin(t * 4.8) * 0.04
		local origin = state.root * CFrame.new(0, (1.8 + bob) * s, 0)
		body.CFrame = origin * CFrame.new(0, 0, 0)
		head.CFrame = origin
			* CFrame.new(0, 1.05 * s * squash, -0.15 * s)
			* CFrame.Angles(math.sin(t * 1.3) * 0.08, 0, 0)
		ruff.CFrame = origin * CFrame.new(0, 0.62 * s, -0.08 * s) * CFrame.Angles(math.rad(12), 0, 0)
		for i, eye in eyes do
			local x = if i == 1 then -0.24 else 0.24
			eye.CFrame = head.CFrame * CFrame.new(x * s, 0.06 * s, -0.55 * s)
		end
		for i, antenna in antennae do
			local x = if i == 1 then -0.22 else 0.22
			local sway = math.sin(t * 3 + i) * 0.12
			antenna.CFrame = head.CFrame
				* CFrame.new(x * s, 0.95 * s, 0)
				* CFrame.Angles(-0.25 + sway, 0, x * 1.3)
				* CFrame.new(0, 0, -0.17 * s)
			tips[i].CFrame = antenna.CFrame * CFrame.new(0, 0.48 * s, -0.2 * s)
		end
		-- Wings stand upright behind the back (the creature faces -Z) and hinge on a vertical axis: a flap
		-- folds them backward and opens them again. The flat extruded wing is turned upright first.
		local flap = (math.sin(t * 11) * 0.5 + 0.5) * 0.9 + 0.1
		for _, wing in wings do
			local fold = if wing.lower then flap * 0.6 + 0.25 else flap
			wing.part.CFrame = origin
				* CFrame.new(0, (if wing.lower then -0.05 else 0.45) * s, 0.4 * s)
				* CFrame.Angles(0, if wing.side < 0 then math.pi else 0, 0)
				* CFrame.Angles(0, -fold, 0)
				* CFrame.Angles(math.rad(if wing.lower then 70 else 100), 0, 0)
				* CFrame.new(wing.part.Size.X / 2, 0, 0)
		end
		return false
	end)
	state.setRoot = function(cf: CFrame)
		state.root = cf
	end
	state.destroy = function()
		stop()
		model:Destroy()
	end
	return state
end

-- Grows the creature from nothing with a springy overshoot.
function Creature.appear(m: Mothling, seconds: number?)
	local duration = seconds or 0.6
	local t = 0
	Scheduler.every(function(dt)
		t += dt
		m.scale = Motion.ease("backOut", t / duration)
		return t >= duration
	end)
end

return Creature
