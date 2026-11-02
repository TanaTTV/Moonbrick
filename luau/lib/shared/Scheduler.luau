--!strict
-- Scheduler: one shared frame loop for Fx, Motion and Pose, instead of one connection per effect.
-- Jobs are functions `step(dt) -> boolean`; returning true finishes the job. Errors are reported once
-- and the job is dropped, so one broken effect never stops the others.
--
--   local stop = Scheduler.every(function(dt) ... return done end)            -- Heartbeat
--   local stop = Scheduler.every(fn, "PreSimulation")                         -- before physics (poses)
local RunService = game:GetService("RunService")

local Scheduler = {}

export type Phase = "Heartbeat" | "PreSimulation"
type Job = { step: (number) -> boolean, alive: boolean }

local queues: { [Phase]: { Job } } = { Heartbeat = {}, PreSimulation = {} }
local timeScale = 1
local connections: { [Phase]: RBXScriptConnection? } = {}

local function run(phase: Phase, rawDt: number)
	local dt = rawDt * timeScale
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
			run(which, dt)
		end)
	end
	return function()
		job.alive = false
	end
end

-- Global time scale for every job: 0 freezes Fx/Pose/Motion (frame captures), 0.2 is slow motion.
function Scheduler.setTimeScale(scale: number)
	timeScale = math.clamp(scale, 0, 4)
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

-- Advances every job by `dt` without waiting for a frame. Deterministic tests and frame captures use this.
function Scheduler.advance(dt: number, phase: Phase?)
	run(phase or "Heartbeat", dt)
end

return Scheduler
