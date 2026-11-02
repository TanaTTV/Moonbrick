--!strict
-- Announces the zone the server reports and blends each zone's mood around the camera.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = ReplicatedStorage:WaitForChild("Kit")
local Scene = require(Kit:WaitForChild("Scene"))
local UI = require(Kit:WaitForChild("UI"))
-- WaitForChild loses the module's type; restate the shape.
local Moods = (
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZoneMoods")) :: any
) :: { [string]: Scene.Look }

local TAG = "Zone"
local removers: { [Instance]: () -> () } = {}

local function setup(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local attribute = instance:GetAttribute("ZoneName")
	local name = if type(attribute) == "string" then attribute else instance.Name
	local mood = Moods[name]
	if mood then
		removers[instance] = Scene.zone(name, instance, mood, { edge = 12, fade = 1 })
	end
end

for _, instance in CollectionService:GetTagged(TAG) do
	setup(instance)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(setup)
-- With streaming on, zone parts come and go; the zone returns with its part.
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
	local remove = removers[instance]
	if remove then
		remove()
		removers[instance] = nil
	end
end)
Scene.follow()

local player = Players.LocalPlayer
player:GetAttributeChangedSignal(TAG):Connect(function()
	local zone = player:GetAttribute(TAG)
	if type(zone) == "string" then
		UI.toast(zone)
	end
end)
