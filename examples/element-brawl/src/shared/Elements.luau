--!strict
-- The four elements. Shared so the server's numbers and the client's HUD/picker never disagree.
-- damage is in percent; base/growth feed Rules.knockback (studs per second); angle is degrees above horizontal.
export type Move = {
	name: string,
	damage: number,
	base: number,
	growth: number,
	angle: number,
	cooldown: number,
}
export type Element = {
	id: string,
	name: string,
	color: Color3,
	glow: Color3,
	blurb: string,
	special: Move,
}

local Elements = {}

Elements.order = { "Fire", "Ice", "Storm", "Wind" }

Elements.strike = {
	name = "Strike",
	damage = 4,
	base = 16,
	growth = 0.35,
	angle = 30,
	cooldown = 0.35,
} :: Move

Elements.byId = {
	Fire = {
		id = "Fire",
		name = "Fire",
		color = Color3.fromRGB(255, 104, 46),
		glow = Color3.fromRGB(255, 196, 64),
		blurb = "Flame Dash: burst forward through everyone in your path.",
		special = { name = "Flame Dash", damage = 11, base = 30, growth = 0.75, angle = 25, cooldown = 2.5 },
	},
	Ice = {
		id = "Ice",
		name = "Ice",
		color = Color3.fromRGB(110, 214, 255),
		glow = Color3.fromRGB(220, 248, 255),
		blurb = "Frost Lance: a fast shard that slows whoever it hits.",
		special = { name = "Frost Lance", damage = 8, base = 22, growth = 0.5, angle = 15, cooldown = 2 },
	},
	Storm = {
		id = "Storm",
		name = "Storm",
		color = Color3.fromRGB(176, 120, 255),
		glow = Color3.fromRGB(240, 230, 120),
		blurb = "Thunder Blink: teleport ahead and call lightning that launches upward.",
		special = { name = "Thunder Blink", damage = 10, base = 28, growth = 0.7, angle = 75, cooldown = 3 },
	},
	Wind = {
		id = "Wind",
		name = "Wind",
		color = Color3.fromRGB(120, 240, 170),
		glow = Color3.fromRGB(230, 255, 240),
		blurb = "Gale Burst: blast everyone nearby off their feet. Perfect at the ledge.",
		special = { name = "Gale Burst", damage = 5, base = 32, growth = 0.85, angle = 35, cooldown = 3.5 },
	},
} :: { [string]: Element }

return Elements
