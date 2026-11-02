--!strict
-- Scheduler: one shared frame loop for Fx, Motion and Pose, instead of one connection per effect.
-- Jobs are functions `step(dt) -> boolean`; returning true finishes the job. Errors are reported once
-- and the job is dropped, so one broken effect never stops the others.
--
--   local stop = Scheduler.every(function(dt) ... return done end)            -- Heartbeat
--   local stop = Scheduler.every(fn, "PreSimulation")                         -- before physics (poses)
local RunService = game:GetService("RunService")

-- Studio only: MCP code has its own copy of every module, so `K.freeze`/`K.step` reach the game's copy
-- through these attributes on ReplicatedStorage (instances are shared; module state is not).
local TIME_SCALE_ATTRIBUTE = "MoonbrickTimeScale"
local STEP_ATTRIBUTE = "MoonbrickStep" -- Vector2(sequence, seconds): the sequence makes repeats fire

local Scheduler = {}

export type Phase = "Heartbeat" | "PreSimulation"
type Job = { step: (number) -> boolean, alive: boolean }

local queues: { [Phase]: { Job } } = { Heartbeat = {}, PreSimulation = {} }
local timeScale = 1
local connections: { [Phase]: RBXScriptConnection? } = {}
local scaleListeners: { (number) -> () } = {}

local function run(phase: Phase, dt: number)
	local jobs = queues[phase]
	local i = 1
	while i <= #jobs do
		local job = jobs[i]
		local done = true
		if job.alive then
			local ok, result = pcall(job.step, dt)
			if ok then
				done = result == true
			else
				warn(`Scheduler: job failed and was removed: {result}`)
			end
		end
		if done then
			job.alive = false
			jobs[i] = jobs[#jobs]
			jobs[#jobs] = nil
		else
			i += 1
		end
	end
	if #jobs == 0 then
		local connection = connections[phase]
		if connection then
			connection:Disconnect()
			connections[phase] = nil
		end
	end
end

-- Runs `step(dt)` every frame until it returns true or the returned function is called.
function Scheduler.every(step: (number) -> boolean, phase: Phase?): () -> ()
	local which: Phase = phase or "Heartbeat"
	local job: Job = { step = step, alive = true }
	table.insert(queues[which], job)
	if not connections[which] then
		local signal = if which == "PreSimulation" then RunService.PreSimulation else RunService.Heartbeat
		connections[which] = signal:Connect(function(dt: number)
			run(which, dt * timeScale)
		end)
	end
	return function()
		job.alive = false
	end
end

-- Global time scale for every job: 0 freezes Fx/Pose/Motion (frame captures), 0.2 is slow motion.
function Scheduler.setTimeScale(scale: number)
	timeScale = math.clamp(scale, 0, 4)
	for _, listener in scaleListeners do
		listener(timeScale)
	end
end

-- Calls `fn(scale)` after every time scale change (Fx uses it to hold its particle emitters).
function Scheduler.onTimeScale(fn: (number) -> ())
	table.insert(scaleListeners, fn)
end

function Scheduler.getTimeScale(): number
	return timeScale
end

-- Number of live jobs (for tests and leak checks).
function Scheduler.count(phase: Phase?): number
	local total = 0
	for name, jobs in queues do
		if phase == nil or phase == name then
			for _, job in jobs do
				if job.alive then
					total += 1
				end
			end
		end
	end
	return total
end

-- Advances jobs by `dt` without waiting for a frame (default: both phases, physics phase first), for
-- deterministic tests and frame captures. `dt` follows the time scale, except while frozen (scale 0),
-- when it applies as given: that is how a capture steps a frozen frame.
function Scheduler.advance(dt: number, phase: Phase?)
	local scaled = if timeScale == 0 then dt else dt * timeScale
	if phase then
		run(phase, scaled)
	else
		run("PreSimulation", scaled)
		run("Heartbeat", scaled)
	end
end

if RunService:IsStudio() then
	local host = game:GetService("ReplicatedStorage")
	host:GetAttributeChangedSignal(TIME_SCALE_ATTRIBUTE):Connect(function()
		local scale = host:GetAttribute(TIME_SCALE_ATTRIBUTE)
		Scheduler.setTimeScale(if type(scale) == "number" then scale else 1)
	end)
	host:GetAttributeChangedSignal(STEP_ATTRIBUTE):Connect(function()
		local step = host:GetAttribute(STEP_ATTRIBUTE)
		if typeof(step) == "Vector2" then
			Scheduler.advance(step.Y)
		end
	end)
end

return Scheduler
