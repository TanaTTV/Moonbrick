--!strict
-- The look of each named zone, as a Scene look (see the world card). Zones without an entry only announce
-- themselves. The server never reads this: moods are presentation.
local moods: { [string]: { [string]: any } } = {
	Cave = {
		lighting = { Brightness = 0.4, OutdoorAmbient = Color3.fromRGB(40, 44, 60) },
		atmosphere = { Density = 0.5, Haze = 2 },
	},
	Meadow = {
		lighting = { Brightness = 2.4 },
		colorCorrection = { Saturation = 0.15 },
	},
}
return moods
