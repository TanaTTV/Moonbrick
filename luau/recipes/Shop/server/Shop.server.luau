--!strict
-- Purchases: the server owns prices, buys inside a PlayerData.update transaction, saves, then answers.
local Players = game:GetService("Players")
local Kit = game:GetService("ServerScriptService").Kit
local PlayerData = require(Kit.PlayerData)
local Economy = require(Kit.Economy)
local DebugHooks = require(Kit.DebugHooks)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Kit.Net)
local Catalog = require(ReplicatedStorage.Shared.ShopCatalog)

local ids: { string } = {}
for id in Catalog do
	table.insert(ids, id)
end
Net.declare("ShopResult")

local function buy(player: Player, itemId: string): string
	local bought, reason = false, "data not loaded"
	local ok, err = PlayerData.update(player, function(data)
		bought, reason = Economy.buy(data :: any, Catalog, itemId)
	end)
	if not ok then
		bought, reason = false, err or "update failed"
	end
	if bought and not PlayerData.save(player) then
		warn("Shop: purchase applied but save failed; autosave will retry")
	end
	Net.fire(player, "ShopResult", bought, if bought then itemId else reason)
	return if bought then "bought " .. itemId else reason
end

Net.on("Buy", { Net.oneOf(table.unpack(ids)) }, function(player, itemId)
	buy(player, itemId)
end, { rate = 3 })

DebugHooks.register("Shop", {
	buy = function(itemId: string?): string
		local player = Players:GetPlayers()[1]
		return if player then buy(player, itemId or ids[1]) else "no player"
	end,
})
