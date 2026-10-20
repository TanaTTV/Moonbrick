--!strict
-- Client presentation of one Celestial Collapse cast: poses on the caster, the orb carried from the
-- hand, overhead and along an arc, then the implosion and explosion at the target. Purely visual: the
-- server already decided the target and applies damage at `timeline.blast`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Fx = require(Kit:WaitForChild("Fx"))
local Motion = require(Kit:WaitForChild("Motion"))
local Pose = require(Kit:WaitForChild("Pose"))
local Scheduler = require(Kit:WaitForChild("Scheduler"))
-- WaitForChild loses the module's type; the plan shape used here is restated.
local Collapse = (require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Collapse")) :: any) :: {
	build: (any) -> any,
	arc: (Vector3, Vector3, number, number) -> Vector3,
	styles: { [string]: any },
}

local CollapsePlayer = {}

local function handOf(caster: Model): BasePart?
	local hand = caster:FindFirstChild("RightHand") or caster:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

local function playPose(caster: Model, clip: any, speed: number): any
	local ok, track = pcall(Pose.play, caster, clip, { speed = speed })
	if not ok then
		warn(`CollapsePlayer: {track}`) -- e.g. an R6 caster: the effect still plays, without the pose
		return nil
	end
	return track
end

export type Options = { timeScale: number?, quality: Fx.Quality?, onImpact: ((Fx.Handle) -> ())? }

-- Plays a cast by `caster` that lands at `target`. Returns a function that cancels it.
function CollapsePlayer.play(styleName: string, caster: Model, target: Vector3, opts: Options?): () -> ()
	local o: Options = opts or {}
	local style = Collapse.styles[styleName]
	assert(style, `unknown style {styleName}`)
	local plan = Collapse.build(style)
	local timeline = plan.timeline
	local hand = handOf(caster)
	local head = caster:FindFirstChild("Head")
	if not hand or not head or not head:IsA("BasePart") then
		warn(`CollapsePlayer: {caster.Name} has no hand/head`)
		return function() end
	end
	local carrier = Instance.new("Part")
	carrier.Name = "OrbCarrier"
	carrier.Anchored, carrier.CanCollide, carrier.CanQuery, carrier.CanTouch = true, false, false, false
	carrier.Transparency = 1
	carrier.Size = Vector3.one * 0.2
	carrier.CFrame = hand.CFrame * CFrame.new(0, -1.1, -0.6)
	carrier.Parent = workspace

	local scale = o.timeScale or 1
	local orb = Fx.play(plan.orb, carrier, { quality = o.quality, timeScale = scale })
	playPose(caster, plan.poses.gather, scale)
	local cancelled = false
	local overheadFrom: Vector3? = nil
	local throwFrom: Vector3? = nil
	local elapsed = 0
	local stage = "gather"
	local stopJob = Scheduler.every(function(dt)
		if cancelled or not caster.Parent then
			return true
		end
		elapsed += dt * scale
		local overhead = (head :: BasePart).Position + Vector3.new(0, 5, 0) + caster:GetPivot().LookVector * 0.8
		if elapsed < timeline.rise then
			carrier.CFrame = (hand :: BasePart).CFrame * CFrame.new(0, -1.1, -0.6)
		elseif elapsed < timeline.throw then
			if stage == "gather" then
				stage = "rise"
				playPose(caster, plan.poses.rise, scale)
				overheadFrom = carrier.Position
			end
			local alpha = (elapsed - timeline.rise) / (timeline.throw - timeline.rise)
			local from = overheadFrom :: Vector3
			carrier.CFrame = CFrame.new(from:Lerp(overhead, Motion.ease("backOut", alpha)))
		elseif elapsed < timeline.impact then
			if stage == "rise" then
				stage = "throw"
				playPose(caster, plan.poses.throw, scale)
				throwFrom = carrier.Position
			end
			local alpha = (elapsed - timeline.throw) / (timeline.impact - timeline.throw)
			local from = throwFrom :: Vector3
			local eased = Motion.ease(plan.style.motion.throw, alpha)
			carrier.CFrame = CFrame.new(Collapse.arc(from, target + Vector3.new(0, 2, 0), 6, eased))
		else
			return true
		end
		return false
	end)

	orb:on("impact", function()
		if cancelled then
			return
		end
		orb:stop()
		carrier:Destroy()
		playPose(caster, plan.poses.recover, scale)
		local impact = Fx.play(plan.impact, CFrame.new(target), { quality = o.quality, timeScale = scale })
		impact:on("blast", function()
			-- Hitstop: hold the first frame of the detonation so the eye registers it.
			impact:freeze(plan.style.timing.hitstop)
		end)
		if o.onImpact then
			o.onImpact(impact)
		end
	end)

	return function()
		cancelled = true
		stopJob()
		orb:stop()
		if carrier.Parent then
			carrier:Destroy()
		end
		Pose.stopAll(caster, 0.1)
	end
end

return CollapsePlayer
