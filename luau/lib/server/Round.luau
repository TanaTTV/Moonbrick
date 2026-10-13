--!strict
-- Deterministic server state machine for arenas, collection rounds, obbies and survival games.
-- Call step(serverPlayerCount) on one bounded loop. Broadcast snapshot only on changes/whole seconds.
local Round = {}
Round.__index = Round
export type State = "Waiting" | "Intermission" | "Playing" | "Results"
export type Config = {
	intermission: number?,
	duration: number?,
	results: number?,
	minPlayers: number?,
	clock: (() -> number)?,
}
export type Snapshot = { state: State, remaining: number, roundId: number }
export type Controller = typeof(setmetatable(
	{} :: {
		state: State,
		deadline: number,
		roundId: number,
		clock: () -> number,
		lastTime: number,
		intermission: number,
		duration: number,
		results: number,
		minPlayers: number,
	},
	Round
))

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end
local function time(self: Controller): number
	local now = self.clock()
	assert(finite(now), "Round clock must be finite")
	self.lastTime = math.max(self.lastTime, now)
	return self.lastTime
end
function Round.new(config: Config?): Controller
	local cfg: Config = config or {}
	local intermission, duration, results = cfg.intermission or 10, cfg.duration or 60, cfg.results or 5
	local minPlayers = cfg.minPlayers or 2
	for _, seconds in { intermission, duration, results } do
		assert(finite(seconds) and seconds > 0, "Round durations must be finite and positive")
	end
	assert(
		finite(minPlayers) and minPlayers >= 1 and minPlayers % 1 == 0,
		"Round minPlayers must be a positive integer"
	)
	return setmetatable({
		state = "Waiting" :: State,
		deadline = 0,
		roundId = 0,
		clock = cfg.clock or os.clock,
		lastTime = -math.huge,
		intermission = intermission,
		duration = duration,
		results = results,
		minPlayers = minPlayers,
	}, Round)
end
function Round.snapshot(self: Controller): Snapshot
	return {
		state = self.state,
		remaining = if self.state == "Waiting" then 0 else math.max(0, self.deadline - time(self)),
		roundId = self.roundId,
	}
end
function Round.step(self: Controller, playerCount: number): (Snapshot, boolean)
	assert(
		finite(playerCount) and playerCount >= 0 and playerCount % 1 == 0,
		"Round playerCount must be a nonnegative integer"
	)
	local now, previous = time(self), self.state
	if self.state == "Waiting" then
		if playerCount >= self.minPlayers then
			self.state = "Intermission"
			self.deadline = now + self.intermission
		end
	elseif self.state == "Intermission" then
		if playerCount < self.minPlayers then
			self.state = "Waiting"
		elseif now >= self.deadline then
			self.state = "Playing"
			self.roundId += 1
			self.deadline = now + self.duration
		end
	elseif self.state == "Playing" then
		if playerCount < self.minPlayers or now >= self.deadline then
			self.state = "Results"
			self.deadline = now + self.results
		end
	elseif now >= self.deadline then
		self.state = "Waiting"
	end
	return self:snapshot(), self.state ~= previous
end
function Round.skip(self: Controller): boolean
	if self.state == "Waiting" then
		return false
	end
	self.deadline = time(self)
	return true
end
return Round
