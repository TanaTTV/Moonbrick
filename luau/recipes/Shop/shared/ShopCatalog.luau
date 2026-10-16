--!strict
-- Shown by the client; the server uses the same table, so clients never send prices.
export type Catalog = { [string]: { price: number } }

local catalog: Catalog = {
	Sword = { price = 10 },
	Shield = { price = 25 },
}
return catalog
