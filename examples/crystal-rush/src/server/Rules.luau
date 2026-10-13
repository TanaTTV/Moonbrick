--!strict
local Rules = {}
function Rules.canCollect(
	state: string,
	loaded: boolean,
	alive: boolean,
	distance: number,
	claimed: boolean
): (boolean, string)
	if state ~= "Playing" then
		return false, "Wait for the next round"
	end
	if not loaded then
		return false, "Your data is loading"
	end
	if not alive then
		return false, "Respawn to collect"
	end
	if distance ~= distance or distance < 0 or distance > 10 then
		return false, "Move closer"
	end
	if claimed then
		return false, "Already collected"
	end
	return true, "Collected"
end

-- Characters are simulated by their client, so the server checks travel between its own samples.
-- `distance` is horizontal (falling is fine); jitter allows for bursty replication and latency.
Rules.SPEED_TOLERANCE = 1.5
Rules.JITTER = 4
function Rules.plausibleMove(distance: number, elapsed: number, walkSpeed: number): boolean
	if distance ~= distance or elapsed ~= elapsed or walkSpeed ~= walkSpeed then
		return false
	end
	local window = math.clamp(elapsed, 0, 2)
	return distance <= math.max(walkSpeed, 0) * Rules.SPEED_TOLERANCE * window + Rules.JITTER
end
return Rules
