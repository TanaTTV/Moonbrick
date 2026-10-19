--!strict
-- Element Brawl server: owns every fighter's percent, stocks, cooldowns, hits, KOs and the round.
-- Clients only ask to attack; the server decides who is hit and tells each client how it was launched.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ServerScriptService.Kit
local PlayerData = require(Kit.PlayerData)
local Cooldown = require(Kit.Cooldown)
local Round = require(Kit.Round)
local DebugHooks = require(Kit.DebugHooks)
local Net = require(ReplicatedStorage.Kit.Net)
local VFX = require(ReplicatedStorage.Kit.VFX)
local Elements = require(ReplicatedStorage.Shared.Elements)
local Rules = require(script.Parent.Rules)

type Fighter = {
	name: string,
	player: Player?,
	model: Model?,
	element: string,
	percent: number,
	stocks: number,
	lastHitBy: Fighter?,
	lastHitAt: number,
	stunUntil: number,
	invulnerableUntil: number,
	out: boolean,
	bot: boolean,
	passive: boolean,
	nextThink: number,
	dir: number,
}

local SPAWNS = { Vector3.new(-26, 24, 0), Vector3.new(26, 24, 0), Vector3.new(0, 40, 0), Vector3.new(-8, 6, 0) }
local BOT_NAMES = { Fire = "Ember", Ice = "Frost", Storm = "Volt", Wind = "Gust" }
local RESPAWN_DELAY = 1.8
local INVULNERABLE = 1.5
local KO_CREDIT = 6 -- seconds a hit still counts as the KO

local fighters: { Fighter } = {}
local byPlayer: { [Player]: Fighter } = {}
local strikeGate = Cooldown.new()
local specialGate = Cooldown.new()
local paused = false -- Studio DebugHooks can hold the round for controlled tests
local round = Round.new({ intermission = 8, duration = 120, results = 7, minPlayers = 1 })

local fighterFolder = Instance.new("Folder")
fighterFolder.Name = "Bots"
fighterFolder.Parent = workspace

for _, name in { "BrawlState", "Hit", "KO", "Winner", "Knockback", "Dash", "Blink", "Slow" } do
	Net.declare(name)
end

Players.CharacterAutoLoads = false
PlayerData.start({ template = { Wins = 0, KOs = 0 }, leaderstats = { "Wins", "KOs" } })

local function rootOf(f: Fighter): BasePart?
	local model = f.model
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(f: Fighter): Humanoid?
	local model = f.model
	return model and model:FindFirstChildOfClass("Humanoid")
end

local function facing(f: Fighter): number
	local root = rootOf(f)
	return if root and root.CFrame.LookVector.X < 0 then -1 else 1
end

local function color(f: Fighter): Color3
	return Elements.byId[f.element].color
end

local function snapshot(): { any }
	local list = {}
	for _, f in fighters do
		table.insert(list, {
			name = f.name,
			element = f.element,
			percent = math.floor(f.percent),
			stocks = f.stocks,
			bot = f.bot,
			passive = f.passive,
			userId = if f.player then f.player.UserId else 0,
			out = f.out,
		})
	end
	return list
end

local function broadcast()
	Net.fireAll("BrawlState", snapshot(), round:snapshot())
end

local function standings(): { Rules.Standing }
	local list = {}
	for _, f in fighters do
		if not f.passive then
			table.insert(list, { name = f.name, stocks = f.stocks, percent = f.percent })
		end
	end
	return list
end

-- Element tint: an outline and a soft light, so every fighter reads at a glance from the side camera.
local function dress(f: Fighter, model: Model)
	local highlight = VFX.highlight(model, { color = color(f) })
	highlight.FillTransparency = 0.82
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness, light.Shadows = color(f), 10, 0.6, false
		light.Parent = root
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 24
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = 9
		humanoid.BreakJointsOnDeath = false
	end
	model:SetAttribute("Element", f.element)
	model:SetAttribute("Fighting", true)
end

local function protect(f: Fighter, seconds: number)
	f.invulnerableUntil = os.clock() + seconds
	local model = f.model
	if model then
		local shield = VFX.highlight(model, { color = Color3.new(1, 1, 1) })
		shield.FillTransparency = 0.6
		task.delay(seconds, function()
			shield:Destroy()
		end)
	end
end

local ko: (Fighter) -> ()

local function watchDeath(f: Fighter, model: Model)
	local humanoid = model:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			if f.model == model and not f.out then
				ko(f)
			end
		end)
	end
end

local function spawnBot(f: Fighter, at: Vector3)
	local description = Instance.new("HumanoidDescription")
	local tone = color(f)
	description.HeadColor, description.TorsoColor = tone, tone:Lerp(Color3.new(0, 0, 0), 0.35)
	description.LeftArmColor, description.RightArmColor = tone, tone
	description.LeftLegColor, description.RightLegColor =
		tone:Lerp(Color3.new(0, 0, 0), 0.5), tone:Lerp(Color3.new(0, 0, 0), 0.5)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn(`Brawl: could not build bot {f.name}: {model}`)
		return
	end
	model.Name = f.name
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, math.rad(if at.X > 0 then -90 else 90), 0))
	model.Parent = fighterFolder
	f.model = model
	dress(f, model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root:SetNetworkOwner(nil)
	end
	watchDeath(f, model)
end

local function respawn(f: Fighter, index: number?)
	f.out, f.stunUntil = false, 0
	local at = SPAWNS[index or math.random(1, 3)]
	if f.player then
		local player = f.player
		task.spawn(function()
			player:LoadCharacterAsync()
		end)
		-- CharacterAdded positions and dresses the new character.
	else
		local old = f.model
		f.model = nil
		if old then
			old:Destroy()
		end
		spawnBot(f, at)
		protect(f, INVULNERABLE)
	end
	broadcast()
end

-- Launches are applied by whoever simulates the character: the owning client for players, the server for bots.
local function launch(f: Fighter, velocity: Vector3, stun: number)
	if f.player then
		Net.fire(f.player, "Knockback", velocity, stun)
		return
	end
	local root, humanoid = rootOf(f), humanoidOf(f)
	if root and humanoid then
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = velocity
		root.AssemblyAngularVelocity =
			Vector3.new(0, 0, (if velocity.X > 0 then -1 else 1) * math.min(velocity.Magnitude / 12, 14))
		local model = f.model
		task.delay(stun, function()
			if f.model == model and humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
end

local function hit(attacker: Fighter, target: Fighter, move: Rules.Move, side: number, tint: Color3)
	local now = os.clock()
	if target == attacker or target.out or target.invulnerableUntil > now then
		return
	end
	local root = rootOf(target)
	if not root then
		return
	end
	target.percent = Rules.addDamage(target.percent, move.damage)
	local velocity = Rules.launch(target.percent, move, side)
	local stun = Rules.hitstun(velocity.Magnitude)
	target.stunUntil = now + stun
	target.lastHitBy, target.lastHitAt = attacker, now
	launch(target, velocity, stun)
	local power = math.clamp(velocity.Magnitude / 140, 0.15, 1)
	VFX.burst(
		root.Position,
		{ color = tint, color2 = Color3.new(1, 1, 1), count = math.floor(10 + 30 * power), size = 1.2 + power }
	)
	if power > 0.55 then
		VFX.shockwave(root.Position, { color = tint, size = 10 + 20 * power, time = 0.35 })
	end
	Net.fireAll("Hit", target.name, attacker.name, power)
	broadcast()
end

local function others(f: Fighter): { Fighter }
	local list = {}
	for _, other in fighters do
		if other ~= f and not other.out and rootOf(other) then
			table.insert(list, other)
		end
	end
	return list
end

local function side(from: Vector3, to: Vector3, fallback: number): number
	local dx = to.X - from.X
	return if math.abs(dx) < 0.5 then fallback elseif dx < 0 then -1 else 1
end

local specials: { [string]: (Fighter, BasePart, number) -> () } = {}

specials.Fire = function(f, root, dir)
	local move = Elements.byId.Fire.special
	if f.player then
		Net.fire(f.player, "Dash", dir)
	else
		root.AssemblyLinearVelocity = Vector3.new(dir * 95, 12, 0)
	end
	local start = root.Position
	for step = 0, 4 do
		local at = start + Vector3.new(dir * step * 4, 0, 0)
		VFX.burst(at, {
			color = Elements.byId.Fire.color,
			color2 = Elements.byId.Fire.glow,
			texture = VFX.Textures.Fire,
			count = 14,
			size = 2.4,
		})
	end
	task.wait(0.08)
	for _, target in others(f) do
		local troot = rootOf(target)
		if troot and Rules.inSweep(start, dir, troot.Position, 18, 5) then
			hit(f, target, move, dir, Elements.byId.Fire.color)
		end
	end
end

specials.Ice = function(f, root, dir)
	local move = Elements.byId.Ice.special
	local shard = Instance.new("Part")
	shard.Name = "FrostLance"
	shard.Anchored, shard.CanCollide, shard.CanQuery, shard.CanTouch = true, false, false, false
	shard.Material, shard.Color, shard.Transparency = Enum.Material.Glass, Elements.byId.Ice.color, 0.15
	shard.Size = Vector3.new(4.5, 0.9, 0.9)
	shard.CFrame = CFrame.new(root.Position + Vector3.new(dir * 3, 0.5, 0))
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Elements.byId.Ice.glow, 9, 1.2
	light.Parent = shard
	shard.Parent = workspace
	local travelled, speed = 0, 120
	local done = false
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		if done then
			return
		end
		travelled += speed * dt
		shard.CFrame = shard.CFrame + Vector3.new(dir * speed * dt, 0, 0)
		for _, target in others(f) do
			local troot = rootOf(target)
			if troot and Rules.inRadius(shard.Position, troot.Position, 3.5) then
				done = true
				hit(f, target, move, dir, Elements.byId.Ice.color)
				if target.player then
					Net.fire(target.player, "Slow", 1.2)
				else
					local humanoid = humanoidOf(target)
					if humanoid then
						humanoid.WalkSpeed = 8
						task.delay(1.2, function()
							humanoid.WalkSpeed = 24
						end)
					end
				end
				VFX.burst(shard.Position, { color = Elements.byId.Ice.color, color2 = Color3.new(1, 1, 1), count = 30 })
				break
			end
		end
		if done or travelled > 70 then
			done = true
			connection:Disconnect()
			VFX.tween(shard, 0.15, { Transparency = 1, Size = shard.Size * 1.6 })
			task.delay(0.2, function()
				shard:Destroy()
			end)
		end
	end)
end

specials.Storm = function(f, root, dir)
	local move = Elements.byId.Storm.special
	local x = Rules.blinkX(root.Position.X, dir, 16)
	local landing = Vector3.new(x, root.Position.Y, 0)
	VFX.burst(root.Position, { color = Elements.byId.Storm.color, color2 = Elements.byId.Storm.glow, count = 20 })
	if f.player then
		Net.fire(f.player, "Blink", x)
	else
		root.CFrame = CFrame.new(landing) * root.CFrame.Rotation
	end
	task.wait(0.12)
	VFX.pillar(landing, { color = Elements.byId.Storm.glow, color2 = Elements.byId.Storm.color, size = 7, time = 0.5 })
	VFX.shockwave(landing - Vector3.new(0, 2.5, 0), { color = Elements.byId.Storm.color, size = 22, time = 0.4 })
	for _, target in others(f) do
		local troot = rootOf(target)
		if troot and Rules.inRadius(landing, troot.Position, 9) then
			hit(f, target, move, side(landing, troot.Position, dir), Elements.byId.Storm.glow)
		end
	end
end

specials.Wind = function(f, root, dir)
	local move = Elements.byId.Wind.special
	local center = root.Position
	VFX.shockwave(center - Vector3.new(0, 2.5, 0), { color = Elements.byId.Wind.color, size = 30, time = 0.45 })
	VFX.sphere(center, { color = Elements.byId.Wind.glow, size = 18, time = 0.35 })
	for _, target in others(f) do
		local troot = rootOf(target)
		if troot and Rules.inRadius(center, troot.Position, 13) then
			hit(f, target, move, side(center, troot.Position, dir), Elements.byId.Wind.color)
		end
	end
end

local function canAct(f: Fighter): boolean
	local humanoid = humanoidOf(f)
	return not f.out
		and f.stunUntil <= os.clock()
		and humanoid ~= nil
		and humanoid.Health > 0
		and round:snapshot().state ~= "Results"
end

local function attack(f: Fighter, kind: string)
	if not canAct(f) then
		return
	end
	local root = rootOf(f)
	if not root then
		return
	end
	local dir = facing(f)
	if kind == "strike" then
		if not strikeGate:use(f, Elements.strike.cooldown) then
			return
		end
		VFX.burst(root.Position + Vector3.new(dir * 3.5, 0.5, 0), { color = color(f), count = 8, size = 1 })
		for _, target in others(f) do
			local troot = rootOf(target)
			if troot and Rules.inStrike(root.Position, dir, troot.Position) then
				hit(f, target, Elements.strike, dir, color(f))
			end
		end
	elseif kind == "special" then
		if not specialGate:use(f, Elements.byId[f.element].special.cooldown) then
			return
		end
		specials[f.element](f, root, dir)
	end
end

ko = function(f: Fighter)
	if f.out then
		return
	end
	f.out = true
	local root = rootOf(f)
	local now = os.clock()
	local playing = round:snapshot().state == "Playing" and not f.passive
	if root then
		local p = root.Position
		local b = Rules.BLAST
		local at = Vector3.new(math.clamp(p.X, b.left + 30, b.right - 30), math.clamp(p.Y, b.bottom + 25, 90), 0)
		VFX.impact(at, { color = color(f), color2 = Color3.new(1, 1, 1), size = 26, pillar = true })
	end
	local killer = if f.lastHitBy and now - f.lastHitAt < KO_CREDIT then f.lastHitBy else nil
	if playing then
		f.stocks = math.max(f.stocks - 1, 0)
		if killer and killer.player and killer ~= f then
			PlayerData.increment(killer.player, "KOs", 1)
		end
	end
	f.lastHitBy = nil
	Net.fireAll("KO", f.name, if killer then killer.name else nil, f.stocks)
	broadcast()
	if playing and Rules.decided(standings()) then
		round:skip()
		return
	end
	if not playing or f.stocks > 0 then
		task.delay(RESPAWN_DELAY, function()
			if f.out and table.find(fighters, f) then
				f.percent = 0
				respawn(f)
			end
		end)
	end
end

local function newFighter(name: string, element: string, player: Player?): Fighter
	local f: Fighter = {
		name = name,
		player = player,
		model = nil,
		element = element,
		percent = 0,
		stocks = Rules.STOCKS,
		lastHitBy = nil,
		lastHitAt = 0,
		stunUntil = 0,
		invulnerableUntil = 0,
		out = false,
		bot = player == nil,
		passive = false,
		nextThink = 0,
		dir = 1,
	}
	table.insert(fighters, f)
	return f
end

local function removeFighter(f: Fighter)
	local index = table.find(fighters, f)
	if index then
		table.remove(fighters, index)
	end
	strikeGate:clear(f)
	specialGate:clear(f)
	if f.bot and f.model then
		f.model:Destroy()
	end
	f.out = true
end

local function removeBots()
	for i = #fighters, 1, -1 do
		if fighters[i].bot then
			removeFighter(fighters[i])
		end
	end
end

-- A passive sandbag to practise on between rounds.
local function addSandbag()
	local f = newFighter("Sandbag", "Wind", nil)
	f.passive = true
	f.stocks = 0
	spawnBot(f, Vector3.new(14, 6, 0))
end

Players.PlayerAdded:Connect(function(player)
	local f = newFighter(player.DisplayName, "Fire", player)
	byPlayer[player] = f
	player.CharacterAdded:Connect(function(character)
		f.model = character
		character:WaitForChild("HumanoidRootPart", 5)
		local index = math.random(1, #SPAWNS)
		character:PivotTo(
			CFrame.new(SPAWNS[index]) * CFrame.Angles(0, math.rad(if SPAWNS[index].X > 0 then -90 else 90), 0)
		)
		dress(f, character)
		protect(f, INVULNERABLE)
		watchDeath(f, character)
		broadcast()
	end)
	if PlayerData.wait(player) then
		player:LoadCharacterAsync()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local f = byPlayer[player]
	byPlayer[player] = nil
	if f then
		removeFighter(f)
		broadcast()
	end
end)

Net.on("Attack", { Net.oneOf("strike", "special") }, function(player, kind)
	local f = byPlayer[player]
	if f then
		attack(f, kind)
	end
end, { rate = 8 })

Net.on("PickElement", { Net.oneOf(table.unpack(Elements.order)) }, function(player, id)
	local f = byPlayer[player]
	if not f or round:snapshot().state == "Playing" then
		return
	end
	f.element = id
	local model = f.model
	if model then
		for _, child in model:GetChildren() do
			if child:IsA("Highlight") then
				child:Destroy()
			end
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		local light = root and root:FindFirstChildOfClass("PointLight")
		if light then
			light:Destroy()
		end
		dress(f, model)
		VFX.burst(
			model:GetPivot().Position,
			{ color = color(f), color2 = Elements.byId[id].glow, count = 40, size = 2 }
		)
	end
	broadcast()
end, { rate = 4 })

Net.handle("BrawlSnapshot", {}, function()
	return snapshot(), round:snapshot()
end, { rate = 2 })

-- Bot brains: walk at the nearest rival, strike in range, use the special now and then, recover to the stage.
local function think(f: Fighter, now: number)
	local root, humanoid = rootOf(f), humanoidOf(f)
	if not root or not humanoid or f.out or f.stunUntil > now or now < f.nextThink then
		return
	end
	f.nextThink = now + 0.15 + math.random() * 0.15
	local p = root.Position
	if math.abs(p.X) > 42 or p.Y < -3 then
		f.dir = if p.X > 0 then -1 else 1
		humanoid:Move(Vector3.new(f.dir, 0, 0))
		if humanoid.FloorMaterial == Enum.Material.Air and root.AssemblyLinearVelocity.Y < 0 then
			humanoid.Jump = true
			if f.element == "Storm" or f.element == "Fire" then
				attack(f, "special")
			end
		end
		return
	end
	if f.passive then
		humanoid:Move(Vector3.zero)
		return
	end
	local nearest: Fighter?, best = nil, math.huge
	for _, other in others(f) do
		local oroot = rootOf(other)
		if oroot then
			local d = (oroot.Position - p).Magnitude + (if other.player then -10 else 0)
			if d < best then
				nearest, best = other, d
			end
		end
	end
	local target = nearest and rootOf(nearest)
	if not target then
		humanoid:Move(Vector3.zero)
		return
	end
	local dx = target.Position.X - p.X
	local dir = if dx < 0 then -1 else 1
	f.dir = dir
	humanoid:Move(if math.abs(dx) > 5 then Vector3.new(dir, 0, 0) else Vector3.zero)
	if target.Position.Y - p.Y > 6 and humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid.Jump = true
	end
	if math.abs(dx) <= 7 and math.abs(target.Position.Y - p.Y) < 6 then
		if math.random() < 0.25 then
			attack(f, "special")
		elseif math.random() < 0.55 then
			attack(f, "strike")
		end
	elseif math.abs(dx) < 18 and math.random() < 0.06 then
		attack(f, "special")
	end
end

local lastScan = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, f in fighters do
		local root = rootOf(f)
		if f.bot and root then
			if math.abs(root.Position.Z) > 0.05 then -- keep bots on the stage plane
				root.CFrame = (root.CFrame - Vector3.new(0, 0, root.Position.Z))
				root.AssemblyLinearVelocity *= Vector3.new(1, 1, 0)
			end
			local humanoid = humanoidOf(f)
			if humanoid and not humanoid.PlatformStand then -- three-quarters toward the camera, like players
				humanoid.AutoRotate = false
				root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(f.dir * 0.82, 0, 0.57))
			end
			task.spawn(think, f, now)
		end
	end
	if now - lastScan < 0.05 then
		return
	end
	lastScan = now
	for _, f in fighters do
		local root = rootOf(f)
		if root and not f.out and Rules.outOfBounds(root.Position) then
			ko(f)
		end
	end
end)

local function startRound()
	removeBots()
	local taken: { [string]: boolean } = {}
	local index = 0
	for _, f in fighters do
		index += 1
		f.percent, f.stocks, f.lastHitBy = 0, Rules.STOCKS, nil
		taken[f.element] = true
		respawn(f, (index - 1) % #SPAWNS + 1)
	end
	for _, id in Elements.order do
		if #fighters >= 4 then
			break
		end
		if not taken[id] then
			index += 1
			local bot = newFighter(BOT_NAMES[id] .. " Bot", id, nil)
			spawnBot(bot, SPAWNS[(index - 1) % #SPAWNS + 1])
			protect(bot, INVULNERABLE)
		end
	end
	broadcast()
end

local function finishRound()
	local name = Rules.winner(standings())
	local winner: Fighter? = nil
	for _, f in fighters do
		if f.name == name then
			winner = f
		end
	end
	if winner and winner.player then
		PlayerData.increment(winner.player, "Wins", 1)
	end
	Net.fireAll("Winner", name, if winner then winner.element else nil)
	if winner then
		local root = rootOf(winner)
		if root then
			VFX.impact(root.Position, { color = color(winner), size = 30, pillar = true })
		end
	end
	task.delay(4, function()
		if round:snapshot().state ~= "Playing" then
			removeBots()
			addSandbag()
			for _, f in fighters do
				if f.out and f.player then -- eliminated players rejoin for practice between rounds
					f.percent = 0
					respawn(f)
				end
			end
			broadcast()
		end
	end)
end

DebugHooks.register("Brawl", {
	state = function()
		return { round = round:snapshot(), fighters = snapshot() }
	end,
	skip = function()
		return round:skip()
	end,
	pause = function(on: boolean)
		paused = on
		return round:snapshot().state
	end,
	-- Hit `targetName` with an element's special from the first player (or the first other fighter).
	hit = function(targetName: string, element: string?, percent: number?)
		local target: Fighter? = nil
		for _, f in fighters do
			if f.name == targetName then
				target = f
			end
		end
		if not target then
			return "no fighter " .. tostring(targetName)
		end
		local attacker = fighters[1] ~= target and fighters[1] or fighters[2]
		if percent then
			target.percent = percent
		end
		target.invulnerableUntil = 0
		local move = if element and Elements.byId[element] then Elements.byId[element].special else Elements.strike
		hit(attacker, target, move, 1, color(attacker))
		return target.percent
	end,
	attack = function(kind: string)
		local player = Players:GetPlayers()[1]
		local f = player and byPlayer[player]
		if not f then
			return "no player"
		end
		attack(f, kind)
		return f.element
	end,
	-- Showcase captures: take the first player out of the fight (no avatar or name on screen) and let bots brawl.
	spectate = function()
		local player = Players:GetPlayers()[1]
		local f = player and byPlayer[player]
		if not player or not f then
			return "no player"
		end
		removeFighter(f)
		byPlayer[player] = nil
		if player.Character then
			player.Character:Destroy()
		end
		local fill = newFighter("Ember Bot", "Fire", nil)
		spawnBot(fill, SPAWNS[4])
		broadcast()
		return #fighters
	end,
	pick = function(id: string)
		local player = Players:GetPlayers()[1]
		local f = player and byPlayer[player]
		if f and Elements.byId[id] then
			f.element = id
			if f.model then
				dress(f, f.model)
			end
			broadcast()
		end
		return f and f.element
	end,
})

addSandbag()
task.spawn(function()
	local lastSecond = -1
	while true do
		local snap, changed = round:snapshot(), false
		if not paused then
			snap, changed = round:step(#Players:GetPlayers())
		end
		if changed then
			if snap.state == "Playing" then
				startRound()
			elseif snap.state == "Results" then
				finishRound()
			end
		end
		local second = math.ceil(snap.remaining)
		if changed or second ~= lastSecond then
			lastSecond = second
			broadcast()
		end
		task.wait(0.2)
	end
end)
