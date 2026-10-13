--!strict
local Kit = game:GetService("ReplicatedStorage"):WaitForChild("Kit")
local Net, UI, VFX = require(Kit.Net), require(Kit.UI), require(Kit.VFX)
UI.Theme.primary = Color3.fromRGB(166, 138, 232)
UI.Theme.secondary = Color3.fromRGB(128, 182, 200)
UI.Theme.surface = Color3.fromRGB(35, 46, 72)
UI.Theme.text = Color3.fromRGB(240, 244, 255)
local screen = UI.screen("CrystalRush")
local panel = UI.panel({
	parent = screen,
	size = UDim2.fromOffset(320, 160),
	position = UDim2.fromScale(0.5, 0.04),
	anchor = Vector2.new(0.5, 0),
	title = "CRYSTAL RUSH",
})
local status = UI.label({ parent = panel, text = "Loading round…", textSize = 22 })
local score = UI.label({ parent = panel, text = "Collect glowing crystals", textSize = 18 })
local previous = 0
local function render(snapshot: any, totals: any)
	if type(snapshot) ~= "table" or type(totals) ~= "table" then
		return
	end
	status.Text = snapshot.state .. " · " .. math.ceil(snapshot.remaining) .. "s"
	score.Text = `Crystals: {totals.caught}   Coins: {totals.coins}`
	if totals.caught > previous then
		VFX.flash({ color = Color3.fromRGB(255, 215, 133), time = 0.15 })
	end
	previous = totals.caught
end
Net.listen("CrystalState", render)
Net.listen("CrystalToast", function(message: string)
	UI.toast(message)
end)
local snapshot, totals = Net.invoke("CrystalSnapshot")
render(snapshot, totals)
