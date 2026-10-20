--!strict
-- Neon Frontier: pure rules for the street's look, shared so tests can run them headless.
local Frontier = {}

-- Neon tube brightness (0..1) at time `t` for a sign with `amount` of flicker (0 = steady, 1 = failing).
-- Deterministic per `seed`: a few hard dropouts per second, scaled by amount, plus a slow hum.
function Frontier.flicker(t: number, amount: number, seed: number): number
	local a = math.clamp(amount, 0, 1)
	if a <= 0 then
		return 1
	end
	local slot = math.floor(t * 9)
	-- Cheap hash of (slot, seed) into 0..1.
	local h = math.abs(math.sin(slot * 12.9898 + seed * 78.233) * 43758.5453) % 1
	local hum = 0.94 + 0.06 * math.sin(t * 50 + seed)
	if h < a * 0.35 then
		return 0.08 * hum -- a dropout: the tube nearly dies for one slot
	end
	return hum
end

export type Bounty = { name: string, crime: string, reward: number, threat: number }

-- The board's contents (fiction only; nothing is saved).
Frontier.bounties = {
	{ name = "Dusty 'Glitch' Malone", crime = "Rewired the town clock to steal an hour", reward = 1200, threat = 2 },
	{ name = "The Copper Widow", crime = "Siphoned the water tower into a data farm", reward = 4800, threat = 4 },
	{ name = "Six-Volt Sally", crime = "Hot-wired the sheriff's hoverbike. Twice.", reward = 2500, threat = 3 },
} :: { Bounty }

-- "$4,800" style formatting (pure).
function Frontier.money(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-$" else "$") .. out
end

return Frontier
