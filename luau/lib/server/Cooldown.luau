--!strict
-- Server-owned cooldowns for abilities, pickups, interaction and shop actions.
-- One gate per action family; key by Player. Clear on PlayerRemoving (or prune expired entries).
local Cooldown = {}
Cooldown.__index = Cooldown
export type Gate = typeof(setmetatable(
	{} :: {
		clock: () -> number,
		deadlines: { [any]: number },
	},
	Cooldown
))

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

function Cooldown.new(clock: (() -> number)?): Gate
	return setmetatable({ clock = clock or os.clock, deadlines = {} }, Cooldown)
end

function Cooldown.remaining(self: Gate, key: any): number
	local now = self.clock()
	assert(finite(now), "Cooldown clock must be finite")
	return math.max(0, (self.deadlines[key] or now) - now)
end

function Cooldown.use(self: Gate, key: any, seconds: number): (boolean, number)
	assert(key ~= nil and (type(key) ~= "number" or finite(key)), "Cooldown key must be nonnil and finite")
	assert(finite(seconds) and seconds >= 0, "Cooldown duration must be finite and nonnegative")
	local now = self.clock()
	assert(finite(now), "Cooldown clock must be finite")
	local remaining = math.max(0, (self.deadlines[key] or now) - now)
	if remaining > 0 then
		return false, remaining
	end
	self.deadlines[key] = now + seconds
	return true, 0
end

function Cooldown.clear(self: Gate, key: any)
	self.deadlines[key] = nil
end

function Cooldown.prune(self: Gate): number
	local now, removed = self.clock(), 0
	assert(finite(now), "Cooldown clock must be finite")
	for key, deadline in self.deadlines do
		if deadline <= now then
			self.deadlines[key] = nil
			removed += 1
		end
	end
	return removed
end
return Cooldown
