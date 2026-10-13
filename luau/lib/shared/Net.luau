--!strict
-- Net: named remotes with server-side argument validation and per-player rate limiting.
-- Clients are untrusted: every argument a client sends is checked against a validator list before
-- your handler runs, extra arguments are rejected, and NaN/inf numbers never get through.
--
-- Server:
--   Net.on("BuyItem", { Net.string(32), Net.int(1, 99) }, function(player, itemId, qty) ... end, { rate = 5 })
--   Net.handle("GetPrice", { Net.string(32) }, function(player, itemId) return 100 end)
--   Net.fire(player, "Notify", "Saved!")   Net.fireAll("RoundStarted", 3)
-- Client:
--   Net.fireServer("BuyItem", "sword", 1)   Net.listen("Notify", function(msg) ... end)
--   local price = Net.invoke("GetPrice", "sword")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

export type Validator = (value: any) -> (boolean, string?)
export type Options = {
	rate: number?, -- max calls per second per player (default 10); bursts up to the same number
}

-- Validators ---------------------------------------------------------------------

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Net.string(maxLength: number?): Validator
	return function(v)
		if type(v) ~= "string" then
			return false, "expected string"
		end
		if maxLength and #v > maxLength then
			return false, `string longer than {maxLength}`
		end
		return true
	end
end

function Net.number(min: number?, max: number?): Validator
	return function(v)
		if type(v) ~= "number" or not finite(v) then
			return false, "expected finite number"
		end
		if (min and v < min) or (max and v > max) then
			return false, `number out of range [{min or "-inf"}, {max or "inf"}]`
		end
		return true
	end
end

function Net.int(min: number?, max: number?): Validator
	local num = Net.number(min, max)
	return function(v)
		local ok, err = num(v)
		if not ok then
			return false, err
		end
		if v % 1 ~= 0 then
			return false, "expected integer"
		end
		return true
	end
end

function Net.boolean(): Validator
	return function(v)
		return type(v) == "boolean", "expected boolean"
	end
end

function Net.vector3(maxMagnitude: number?): Validator
	return function(v)
		if typeof(v) ~= "Vector3" or not (finite(v.X) and finite(v.Y) and finite(v.Z)) then
			return false, "expected finite Vector3"
		end
		if maxMagnitude and v.Magnitude > maxMagnitude then
			return false, "Vector3 too large"
		end
		return true
	end
end

-- An Instance of the given class (IsA). Optionally require it to be a descendant of `ancestor`.
function Net.instance(className: string, ancestor: Instance?): Validator
	return function(v)
		if typeof(v) ~= "Instance" or not v:IsA(className) then
			return false, `expected {className}`
		end
		if ancestor and not v:IsDescendantOf(ancestor) then
			return false, `{className} not under {ancestor:GetFullName()}`
		end
		return true
	end
end

-- One of a fixed set of values (e.g. item ids, enum-like strings).
function Net.oneOf(...: any): Validator
	local allowed = {}
	for _, v in { ... } do
		allowed[v] = true
	end
	return function(v)
		return allowed[v] == true, "value not allowed"
	end
end

function Net.optional(validator: Validator): Validator
	return function(v)
		if v == nil then
			return true
		end
		return validator(v)
	end
end

-- Check an argument list against validators. Exposed for tests and custom remotes.
function Net.check(validators: { Validator }, args: { any }, count: number): (boolean, string?)
	if count > #validators then
		return false, `too many arguments ({count} > {#validators})`
	end
	for i, validate in validators do
		local ok, err = validate(args[i])
		if not ok then
			return false, `argument {i}: {err or "invalid"}`
		end
	end
	return true
end

-- Remotes ------------------------------------------------------------------------

local FOLDER = "Remotes"

local function folder(): Instance
	local existing = ReplicatedStorage:FindFirstChild(FOLDER)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = ReplicatedStorage
		return f
	end
	return ReplicatedStorage:WaitForChild(FOLDER)
end

local function remote(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	local f = folder()
	local existing = f:FindFirstChild(name)
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local r = Instance.new(className)
		r.Name = name
		r.Parent = f
		return r
	end
	local r = f:WaitForChild(name, 10)
	if not r then
		error(`Net: remote '{name}' not found; is the server script that calls Net.on/handle('{name}') running?`, 3)
	end
	return r
end

-- Token bucket per player per remote.
local buckets: { [string]: { [Player]: { tokens: number, last: number } } } = {}
local warned: { [string]: { [Player]: boolean } } = {}

local function allow(name: string, player: Player, rate: number): boolean
	local perRemote = buckets[name]
	if not perRemote then
		perRemote = {}
		buckets[name] = perRemote
	end
	local now = os.clock()
	local b = perRemote[player]
	if not b then
		b = { tokens = rate, last = now }
		perRemote[player] = b
	end
	b.tokens = math.min(rate, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function reject(name: string, player: Player, reason: string)
	local perRemote = warned[name]
	if not perRemote then
		perRemote = {}
		warned[name] = perRemote
	end
	if not perRemote[player] then -- warn once per player per remote to avoid log spam
		perRemote[player] = true
		warn(`Net: rejected '{name}' from {player.Name}: {reason}`)
	end
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		for _, perRemote in buckets do
			perRemote[player] = nil
		end
		for _, perRemote in warned do
			perRemote[player] = nil
		end
	end)
end

-- Server: handle a client -> server event.
function Net.on(name: string, validators: { Validator }, handler: (Player, ...any) -> (), opts: Options?)
	assert(RunService:IsServer(), "Net.on is server-only; clients use Net.listen")
	local rate = (opts and opts.rate) or 10
	local r = remote(name, "RemoteEvent") :: RemoteEvent
	r.OnServerEvent:Connect(function(player, ...)
		if not allow(name, player, rate) then
			return reject(name, player, "rate limit")
		end
		local ok, err = Net.check(validators, { ... }, select("#", ...))
		if not ok then
			return reject(name, player, err or "invalid")
		end
		handler(player, ...)
	end)
end

-- Server: answer a client -> server request. Invalid or rate-limited requests return nil.
function Net.handle(name: string, validators: { Validator }, handler: (Player, ...any) -> ...any, opts: Options?)
	assert(RunService:IsServer(), "Net.handle is server-only; clients use Net.invoke")
	local rate = (opts and opts.rate) or 10
	local r = remote(name, "RemoteFunction") :: RemoteFunction
	r.OnServerInvoke = function(player, ...)
		if not allow(name, player, rate) then
			reject(name, player, "rate limit")
			return nil
		end
		local ok, err = Net.check(validators, { ... }, select("#", ...))
		if not ok then
			reject(name, player, err or "invalid")
			return nil
		end
		return handler(player, ...)
	end
end

-- Server: create an event the server fires to clients (so clients can listen before the first fire).
function Net.declare(name: string)
	remote(name, "RemoteEvent")
end

function Net.fire(player: Player, name: string, ...: any)
	(remote(name, "RemoteEvent") :: RemoteEvent):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	(remote(name, "RemoteEvent") :: RemoteEvent):FireAllClients(...)
end

-- Client side.
function Net.fireServer(name: string, ...: any)
	(remote(name, "RemoteEvent") :: RemoteEvent):FireServer(...)
end

function Net.listen(name: string, handler: (...any) -> ()): RBXScriptConnection
	return (remote(name, "RemoteEvent") :: RemoteEvent).OnClientEvent:Connect(handler)
end

function Net.invoke(name: string, ...: any): ...any
	return (remote(name, "RemoteFunction") :: RemoteFunction):InvokeServer(...)
end

return Net
