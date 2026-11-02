--!strict
-- An obstacle course. Parts tagged "ObbyStage" with a number attribute `Order` are checkpoints, reached in
-- order. Parts tagged "ObbyHazard" kill, the part tagged "ObbyFinish" ends the run, awards COINS (with the Data
-- recipe) and records the best time. A fall below KILL_Y counts as a hazard. `K.hook("Obby", "build")` makes a sample course.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Kit = game:GetService("ServerScriptService").Kit
local DebugHooks = require(Kit.DebugHooks)
local PlayerData = require(Kit.PlayerData)

local STAGE, HAZARD, FINISH = "ObbyStage", "ObbyHazard", "ObbyFinish"
local COINS = 10
local KILL_Y = -40

local started: { [Player]: number } = {}

local function stageOf(player: Player): number
	local stage = player:GetAttribute(STAGE)
	return if type(stage) == "number" then stage else 0
end

local function stagePart(order: number): BasePart?
	for _, instance in CollectionService:GetTagged(STAGE) do
		if instance:IsA("BasePart") and instance:GetAttribute("Order") == order then
			return instance
		end
	end
	return nil
end

local function stageCount(): number
	local highest = 0
	for _, instance in CollectionService:GetTagged(STAGE) do
		local order = instance:GetAttribute("Order")
		if type(order) == "number" then
			highest = math.max(highest, order)
		end
	end
	return highest
end

local function kill(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

local function touchStage(player: Player, part: BasePart): string
	local order = part:GetAttribute("Order")
	-- Only the next stage counts, so a shortcut can't skip the course.
	if order ~= stageOf(player) + 1 then
		return "not the next stage"
	end
	player:SetAttribute(STAGE, order)
	if order == 1 then
		started[player] = os.clock()
		player:SetAttribute("ObbyStarted", workspace:GetServerTimeNow())
	end
	return "stage " .. tostring(order)
end

local function finish(player: Player): string
	if stageOf(player) < stageCount() then
		return "stages missing"
	end
	local seconds = os.clock() - (started[player] or os.clock())
	local best = player:GetAttribute("ObbyBest")
	if type(best) ~= "number" or seconds < best then
		player:SetAttribute("ObbyBest", seconds)
	end
	if PlayerData.get(player) then
		PlayerData.increment(player, "Coins", COINS)
	end
	player:SetAttribute(STAGE, 0)
	player:SetAttribute("ObbyStarted", nil)
	player:SetAttribute("ObbyFinished", seconds)
	started[player] = nil
	return string.format("finished in %.1f s", seconds)
end

-- Runs `fn(player, part)` when a character touches `tag`ged parts, now and for parts added later.
local function onTouch(tag: string, fn: (Player, BasePart) -> ())
	local function setup(instance: Instance)
		if not instance:IsA("BasePart") then
			return
		end
		local part = instance
		part.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
			if player and humanoid and humanoid.Health > 0 then
				fn(player, part)
			end
		end)
	end
	for _, instance in CollectionService:GetTagged(tag) do
		setup(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(setup)
end

onTouch(STAGE, function(player, part)
	touchStage(player, part)
end)
onTouch(HAZARD, kill)
onTouch(FINISH, function(player)
	finish(player)
end)

local function track(player: Player)
	player.CharacterAdded:Connect(function(character)
		local part = stagePart(stageOf(player))
		if part then
			character:WaitForChild("HumanoidRootPart")
			task.wait() -- after the engine's spawn placement
			character:PivotTo(part.CFrame + Vector3.new(0, part.Size.Y / 2 + 4, 0))
		end
	end)
end
for _, player in Players:GetPlayers() do
	track(player)
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(function(player)
	started[player] = nil
end)

task.spawn(function()
	while true do
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and root.Position.Y < KILL_Y then
				kill(player)
			end
		end
		task.wait(0.5)
	end
end)

-- A short course of pads over a gap, with a lava strip and a finish pad.
local function buildSample(): string
	local world = workspace:FindFirstChild("World") or workspace
	local folder = Instance.new("Folder")
	folder.Name = "ObbySample"
	local function pad(name: string, position: Vector3, size: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size, part.Position, part.Color = size, position, color
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = folder
		return part
	end
	local stageColor, hazardColor = Color3.fromRGB(90, 180, 240), Color3.fromRGB(240, 80, 60)
	for order = 1, 4 do
		local stage = pad(`Stage{order}`, Vector3.new(order * 24, 8 + order * 3, 0), Vector3.new(12, 1, 12), stageColor)
		stage:SetAttribute("Order", order)
		stage:AddTag(STAGE)
	end
	pad("Lava", Vector3.new(60, 2, 0), Vector3.new(120, 1, 40), hazardColor):AddTag(HAZARD)
	pad("Finish", Vector3.new(120, 24, 0), Vector3.new(14, 1, 14), Color3.fromRGB(255, 210, 90)):AddTag(FINISH)
	folder.Parent = world
	return "built " .. stageCount() .. " stages"
end

DebugHooks.register("Obby", {
	build = buildSample,
	state = function(): string
		local player = Players:GetPlayers()[1]
		return if player then `stage {stageOf(player)}/{stageCount()}` else "no player"
	end,
	-- Walks the first player through every stage and over the finish.
	run = function(): string
		local player = Players:GetPlayers()[1]
		if not player then
			return "no player"
		end
		for order = 1, stageCount() do
			local part = stagePart(order)
			if part then
				touchStage(player, part)
			end
		end
		return finish(player)
	end,
})
