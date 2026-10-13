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
return Rules
