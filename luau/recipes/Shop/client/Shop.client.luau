--!strict
-- One button per catalog item; results come back from the server as toasts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Net = require(Kit:WaitForChild("Net"))
local UI = require(Kit:WaitForChild("UI"))
local CatalogModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog")
-- WaitForChild loses the module's type; restate the shape the server also uses.
local Catalog = (require(CatalogModule) :: any) :: { [string]: { price: number } }

local gui = UI.screen("Shop")
local panel = UI.panel({ parent = gui, size = UDim2.fromOffset(260, 200), title = "Shop" })
for id, item in Catalog do
	UI.button({
		parent = panel,
		text = string.format("%s - %d", id, item.price),
		onClick = function()
			Net.fireServer("Buy", id)
		end,
	})
end
UI.show(panel, true)

Net.listen("ShopResult", function(bought: boolean, detail: string)
	UI.toast(if bought then "Bought " .. detail else detail, {
		color = if bought then UI.Theme.success else UI.Theme.danger,
	})
end)
