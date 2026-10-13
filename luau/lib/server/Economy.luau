--!strict
-- Pure, nonyielding in-game currency rules. Call only with server catalog/data, inside PlayerData.update.
-- This is not developer-product receipt processing or proof of a durable save.
local Economy = {}
local MAX_SAFE = 9007199254740991
export type Data = { Coins: number, Inventory: { string } }
export type Item = { price: number }
local function currency(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= MAX_SAFE and value % 1 == 0
end
function Economy.award(data: Data, amount: number): (boolean, string)
	if not currency(data.Coins) or not currency(amount) or data.Coins > MAX_SAFE - amount then
		return false, "invalid amount"
	end
	data.Coins += amount
	return true, "awarded"
end
function Economy.buy(data: Data, catalog: { [string]: Item }, itemId: string): (boolean, string)
	local item = catalog[itemId]
	if not item then
		return false, "unknown item"
	end
	if not currency(item.price) or not currency(data.Coins) or type(data.Inventory) ~= "table" then
		return false, "invalid economy data"
	end
	if table.find(data.Inventory, itemId) then
		return false, "already owned"
	end
	if data.Coins < item.price then
		return false, "insufficient coins"
	end
	-- Validation completes before either mutation. No yielding/external effects here.
	data.Coins -= item.price
	table.insert(data.Inventory, itemId)
	return true, "bought"
end
return Economy
