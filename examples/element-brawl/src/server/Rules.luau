--!strict
-- Pure fight rules: knockback scaling, blast zones, hit boxes and the winner. No Instances, so they unit test.
local Rules = {}

export type Move = { damage: number, base: number, growth: number, angle: number }
export type Standing = { name: string, stocks: number, percent: number }

Rules.MAX_PERCENT = 999
Rules.STOCKS = 3
-- The stage spans x = -45..45 with its top at y = 0; fighters are locked to z = 0.
Rules.BLAST = { left = -150, right = 150, bottom = -60, top = 230 }

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Rules.addDamage(percent: number, damage: number): number
	if not finite(percent) or not finite(damage) then
		return if finite(percent) then percent else 0
	end
	return math.clamp(percent + math.max(damage, 0), 0, Rules.MAX_PERCENT)
end

-- Launch speed in studs per second. Smash-style: the more damage you carry, the further you fly.
function Rules.knockback(percent: number, move: Move): number
	if not finite(percent) then
		return move.base
	end
	return move.base + math.clamp(percent, 0, Rules.MAX_PERCENT) * move.growth
end

-- Launch velocity away from the attacker (`side` is +1 to the right, -1 to the left).
function Rules.launch(percent: number, move: Move, side: number): Vector3
	local speed = Rules.knockback(percent, move)
	local angle = math.rad(move.angle)
	local direction = if side < 0 then -1 else 1
	return Vector3.new(math.cos(angle) * direction * speed, math.sin(angle) * speed, 0)
end

-- Seconds without control after a hit; heavier launches stun longer.
function Rules.hitstun(speed: number): number
	if not finite(speed) then
		return 0.15
	end
	return math.clamp(speed * 0.006, 0.15, 1.2)
end

function Rules.outOfBounds(position: Vector3): boolean
	local b = Rules.BLAST
	if not (finite(position.X) and finite(position.Y)) then
		return true
	end
	return position.X < b.left or position.X > b.right or position.Y < b.bottom or position.Y > b.top
end

-- Melee box in front of the attacker: a little behind (for overlap) to 8 studs ahead, 6 studs up or down.
function Rules.inStrike(attacker: Vector3, facing: number, target: Vector3): boolean
	local ahead = (target.X - attacker.X) * (if facing < 0 then -1 else 1)
	return ahead >= -1.5 and ahead <= 8 and math.abs(target.Y - attacker.Y) <= 6
end

-- A dash or lance sweeps a segment ahead of the attacker.
function Rules.inSweep(attacker: Vector3, facing: number, target: Vector3, length: number, halfHeight: number): boolean
	local ahead = (target.X - attacker.X) * (if facing < 0 then -1 else 1)
	return ahead >= -1 and ahead <= length and math.abs(target.Y - attacker.Y) <= halfHeight
end

function Rules.inRadius(center: Vector3, target: Vector3, radius: number): boolean
	local dx, dy = target.X - center.X, target.Y - center.Y
	return math.sqrt(dx * dx + dy * dy) <= radius
end

-- Where a blink lands: `distance` ahead, but never past the blast zone's inner margin.
function Rules.blinkX(x: number, facing: number, distance: number): number
	local margin = 20
	return math.clamp(
		x + distance * (if facing < 0 then -1 else 1),
		Rules.BLAST.left + margin,
		Rules.BLAST.right - margin
	)
end

-- Most stocks wins; ties go to the lower percent; still tied means no single winner.
function Rules.winner(standings: { Standing }): string?
	local best: Standing? = nil
	local tied = false
	for _, s in standings do
		if s.stocks > 0 then
			if not best or s.stocks > best.stocks or (s.stocks == best.stocks and s.percent < best.percent) then
				best, tied = s, false
			elseif s.stocks == best.stocks and s.percent == best.percent then
				tied = true
			end
		end
	end
	return if best and not tied then best.name else nil
end

-- The round ends early once one fighter (or nobody) still has stocks.
function Rules.decided(standings: { Standing }): boolean
	local alive = 0
	for _, s in standings do
		if s.stocks > 0 then
			alive += 1
		end
	end
	return #standings > 1 and alive <= 1
end

return Rules
