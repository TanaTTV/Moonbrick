--!strict
-- Client presentation of one hatch the server already rolled: framing camera, wobbling egg with cracks,
-- an anticipation squash, the burst with flying shell, then the creature and its rarity aura.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Audio = require(Kit:WaitForChild("Audio"))
local Fx = require(Kit:WaitForChild("Fx"))
local Geo = require(Kit:WaitForChild("Geo"))
local Motion = require(Kit:WaitForChild("Motion"))
local Scheduler = require(Kit:WaitForChild("Scheduler"))
local Creature = require(script.Parent:WaitForChild("Creature"))
-- WaitForChild loses the module's type; restate what this script uses.
local Hatch = (require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Hatch")) :: any) :: {
	looks: { [string]: any },
	timeline: (string) -> { wobble: number, burst: number, reveal: number, card: number, done: number },
	burst: (string) -> Fx.Definition,
	aura: (string) -> Fx.Definition,
}

local HatchPlayer = {}

local glint = Fx.define({
	name = "CrackGlint",
	layers = {
		{
			kind = "particles",
			texture = "spark",
			count = 6,
			speed = { 4, 9 },
			drag = 3,
			lifetime = { 0.25, 0.45 },
			size = { { 0, 0.7 }, { 1, 0 } },
			color = "glow",
		},
	},
})

local function sound(name: string): string
	return "rbxasset://sounds/moonbrick/" .. name .. ".wav"
end

-- Shell fragments: faceted shards in the egg's colours, thrown outward and faded.
local function shatter(look: any, at: Vector3, parent: Instance)
	local rng = Random.new()
	for i = 1, 14 do
		local shard = Geo.unitShard():Clone()
		shard.Size = Vector3.new(rng:NextNumber(0.4, 0.8), rng:NextNumber(0.5, 1.1), rng:NextNumber(0.3, 0.6))
		shard.Color = if i % 3 == 0 then look.speckle else look.shell
		shard.Material = Enum.Material.SmoothPlastic
		shard.Anchored = false
		shard.CanCollide = true
		shard.CFrame = CFrame.new(at + Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0.4, 2.2), rng:NextNumber(-0.6, 0.6)))
			* CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), 0)
		local angle = rng:NextNumber(0, math.pi * 2)
		shard.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * 14, rng:NextNumber(10, 20), math.sin(angle) * 14)
		shard.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-15, 15), rng:NextNumber(-15, 15), rng:NextNumber(-15, 15))
		shard.Parent = parent
		Motion.to(shard, { Transparency = 1 }, {
			time = 0.6,
			delay = 1.6,
			onDone = function()
				shard:Destroy()
			end,
		})
	end
end

export type Options = { camera: boolean?, onCard: (() -> ())?, onDone: (() -> ())? }
export type Playing = { creature: Creature.Mothling?, cancel: () -> () }

-- Plays a hatch on `pedestal` (a part whose top the egg sits on).
function HatchPlayer.play(rarity: string, pedestal: BasePart, opts: Options?): Playing
	local o: Options = opts or {}
	local look = Hatch.looks[rarity]
	local tl = Hatch.timeline(rarity)
	local folder = Instance.new("Folder")
	folder.Name = "Hatch"
	folder.Parent = workspace
	local top = pedestal.CFrame * CFrame.new(0, pedestal.Size.Y / 2, 0)

	local egg = Creature.egg(look):Clone()
	egg.Name = "Egg"
	egg.Size = egg.Size * 1.35
	egg.Anchored, egg.CanCollide = true, false
	egg.Parent = folder
	local inner = Instance.new("PointLight")
	inner.Color = look.palette.glow
	inner.Range = 8
	inner.Brightness = 0
	inner.Shadows = false
	inner.Parent = egg
	local half = egg.Size.Y / 2
	local restSize = egg.Size

	local playing: Playing = { creature = nil, cancel = function() end }
	local camera = workspace.CurrentCamera
	local cameraFrom = camera.CFrame
	local look0 = top.Position + Vector3.new(0, 1.8, 0)
	local wide = CFrame.lookAt(look0 + Vector3.new(0, 3.5, 16), look0)
	-- Push in and settle slightly below the creature's eye line, framed left of the reward card.
	local close = CFrame.lookAt(look0 + Vector3.new(-1.2, 0.6, 10), look0 + Vector3.new(1.6, 0.6, 0))
	if o.camera ~= false then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local t = 0
	local lastPeak = 0
	local burst = false
	local revealed = false
	local carded = false
	local stop = Scheduler.every(function(dt)
		if not folder.Parent then
			return true
		end
		t += dt
		-- Camera: push in during the wobble, then hold.
		if o.camera ~= false then
			local k = Motion.ease("sineInOut", math.clamp(t / tl.burst, 0, 1))
			camera.CFrame = wide:Lerp(close, k)
		end
		if not burst then
			-- Wobble: rocking about the base, harder each swing; crack and glint on every peak.
			local w = math.clamp((t - tl.wobble) / (tl.burst - tl.wobble), 0, 1)
			local swing = if t >= tl.wobble then math.sin((t - tl.wobble) * 11.5) else 0
			local amplitude = math.rad(4 + 16 * w)
			local peak = math.floor(math.max(t - tl.wobble, 0) * 11.5 / math.pi)
			if t >= tl.wobble and peak > lastPeak and peak % 2 == 1 then
				lastPeak = peak
				Audio.play(sound("crack"), egg.Position, { volume = 0.6 + 0.4 * w, pitch = 0.9 + 0.3 * w })
				Fx.play(glint, egg.CFrame * CFrame.new(0, half * 0.4, -egg.Size.Z / 2), { palette = look.palette })
			end
			inner.Brightness = 1.4 * w
			egg.Color = Color3.new(1, 1, 1):Lerp(look.palette.glow, w * 0.35)
			-- Anticipation: squash and hold still for the last moment before the burst.
			local squash = math.clamp((t - (tl.burst - 0.22)) / 0.22, 0, 1)
			if squash > 0 then
				egg.Size = restSize * Vector3.new(1 + 0.1 * squash, 1 - 0.14 * squash, 1 + 0.1 * squash)
				swing = 0
			end
			egg.CFrame = top * CFrame.Angles(0, 0, swing * amplitude) * CFrame.new(0, egg.Size.Y / 2, 0)
			if t >= tl.burst then
				burst = true
				shatter(look, top.Position, folder)
				egg:Destroy()
				Fx.play(Hatch.burst(rarity), top, { palette = look.palette })
			end
		end
		if burst and not revealed and t >= tl.reveal then
			revealed = true
			-- Built facing -Z; turn it to face the viewer (cameras sit on the +Z side of the pedestal).
			local creature = Creature.mothling(look, top * CFrame.Angles(0, math.pi, 0), folder)
			Creature.appear(creature, 0.6)
			playing.creature = creature
			Fx.play(Hatch.aura(rarity), top, { palette = look.palette })
		end
		if revealed and not carded and t >= tl.card then
			carded = true
			if o.onCard then
				task.spawn(o.onCard)
			end
		end
		if t >= tl.done then
			if o.onDone then
				task.spawn(o.onDone)
			end
			return true
		end
		return false
	end)
	playing.cancel = function()
		stop()
		folder:Destroy()
		if o.camera ~= false then
			camera.CFrame = cameraFrom
			camera.CameraType = Enum.CameraType.Custom
		end
	end
	return playing
end

return HatchPlayer
