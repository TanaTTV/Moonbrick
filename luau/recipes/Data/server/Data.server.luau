--!strict
-- The one PlayerData.start for the whole game. Add new fields to the template; never rename/remove without a migration.
local PlayerData = require(game:GetService("ServerScriptService").Kit.PlayerData)

PlayerData.start({
	template = { Coins = 0, Inventory = {} },
	leaderstats = { "Coins" },
})
