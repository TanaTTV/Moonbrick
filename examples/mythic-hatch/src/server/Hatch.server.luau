--!strict
-- Mythic Hatch server: owns the roll. A client only asks to hatch; the server checks the cooldown and that
-- the pedestal is free, rolls rarity and stats from its own RNG, saves the pet, then tells every client
-- what hatched so they all see the same ceremony.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ServerScriptService.Kit
local Cooldown = require(Kit.Cooldown)
local DebugHooks = require(Kit.DebugHooks)
local PlayerData = require(Kit.PlayerData)
local Net = require(ReplicatedStorage.Kit.Net)
local Hatch = require(ReplicatedStorage.Shared.Hatch)

local COOLDOWN = 2
local MAX_PETS = 50
local gate = Cooldown.new()
local rng = Random.new()
local busyUntil = 0
local hatches = 0
local counts: { [string]: number } = { Common = 0, Rare = 0, Mythic = 0 }

PlayerData.start({ template = { Pets = {} } })
Net.declare("Hatched")

-- One ceremony at a time on the shared pedestal. Returns the rarity, or nil and a reason.
local function hatch(owner: Player?, forced: Hatch.Rarity?): (Hatch.Rarity?, string)
	local now = os.clock()
	if now < busyUntil then
		return nil, "pedestal busy"
	end
	local rarity = forced or Hatch.roll(rng:NextNumber())
	local glow = Hatch.glowFor(rarity, rng:NextNumber())
	if owner then
		local ok, err = PlayerData.update(owner, function(data)
			if #data.Pets < MAX_PETS then
				table.insert(data.Pets, { kind = "Mothling", rarity = rarity, glow = glow })
			end
		end)
		if not ok then
			return nil, `could not save: {err}`
		end
	end
	busyUntil = now + Hatch.timeline(rarity).done
	hatches += 1
	counts[rarity] += 1
	Net.fireAll("Hatched", rarity, glow, owner)
	return rarity, `hatched {rarity} (glow {glow})`
end

Net.on("Hatch", {}, function(player)
	if not gate:use(player, COOLDOWN) then
		return
	end
	local rarity, reason = hatch(player)
	if not rarity and reason ~= "pedestal busy" then
		warn(`Hatch: {reason}`)
	end
end, { rate = 2 })

Players.PlayerRemoving:Connect(function(player)
	gate:clear(player)
end)

DebugHooks.register("Hatch", {
	-- K.hook("Hatch", "hatch", "Mythic") — forced rarity, no owner, nothing saved.
	hatch = function(rarity: string?)
		local forced = if rarity and Hatch.looks[rarity] then rarity else nil
		busyUntil = 0
		local _, message = hatch(nil, forced)
		return message
	end,
	state = function()
		local saved = 0
		for _, player in Players:GetPlayers() do
			local data = PlayerData.get(player)
			saved += if data then #data.Pets else 0
		end
		return { hatches = hatches, counts = counts, busy = os.clock() < busyUntil, savedPets = saved }
	end,
})
