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
	maxInFlight: number?, -- maximum yielding request handlers per player (default 4)
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
		local ran, ok, err = pcall(validate, args[i])
		if not ran then
			return false, `argument {i}: validator failed`
		end
		if ok ~= true then
			return false, `argument {i}: {tostring(err or "invalid")}`
		end
	end
	return true
end

-- Remotes ------------------------------------------------------------------------

local FOLDER = "Remotes"

local function folder(): Instance
	local existing = ReplicatedStorage:FindFirstChild(FOLDER)
	if existing then
		assert(existing:IsA("Folder"), "Net: ReplicatedStorage.Remotes must be a Folder")
		return existing
	end
	if RunService:IsServer() then
		local f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = ReplicatedStorage
		return f
	end
	local result = ReplicatedStorage:WaitForChild(FOLDER, 10)
	assert(result and result:IsA("Folder"), "Net: Remotes folder unavailable after 10s")
	return result
end

local function remote(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	assert(#name > 0 and #name <= 64 and not name:find("%c"), "Net: remote names must be 1..64 printable characters")
	local f = folder()
	local existing = f:FindFirstChild(name)
	if existing then
		assert(existing:IsA(className), `Net: remote '{name}' is not a {className}`)
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
	assert(r:IsA(className), `Net: remote '{name}' is not a {className}`)
	return r
end

-- Token bucket per player per remote.
local buckets: { [string]: { [Player]: { tokens: number, last: number } } } = {}
local warned: { [string]: { [Player]: boolean } } = {}
local inFlight: { [string]: { [Player]: { count: number } } } = {}
local registered: { [string]: boolean } = {}

local function checkOptions(opts: Options?): number
	local rate = (opts and opts.rate) or 10
	assert(finite(rate) and rate >= 1, "Net: rate must be finite and >= 1")
	return rate
end

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
		for _, perRemote in inFlight do
			perRemote[player] = nil
		end
	end)
end

-- Server: handle a client -> server event.
function Net.on(name: string, validators: { Validator }, handler: (Player, ...any) -> (), opts: Options?)
	assert(RunService:IsServer(), "Net.on is server-only; clients use Net.listen")
	local rate = checkOptions(opts)
	assert(not registered[name], `Net: '{name}' already has a server handler`)
	local r = remote(name, "RemoteEvent") :: RemoteEvent
	registered[name] = true
	return r.OnServerEvent:Connect(function(player, ...)
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
	local rate = checkOptions(opts)
	local maxInFlight = (opts and opts.maxInFlight) or 4
	assert(
		finite(maxInFlight) and maxInFlight >= 1 and maxInFlight % 1 == 0,
		"Net: maxInFlight must be a positive integer"
	)
	assert(not registered[name], `Net: '{name}' already has a server handler`)
	local r = remote(name, "RemoteFunction") :: RemoteFunction
	registered[name] = true
	inFlight[name] = {}
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
		local perRemote = inFlight[name]
		local pending = perRemote[player] or { count = 0 }
		perRemote[player] = pending
		if pending.count >= maxInFlight then
			reject(name, player, "too many pending requests")
			return nil
		end
		pending.count += 1
		local results = table.pack(pcall(handler, player, ...))
		pending.count -= 1
		if not results[1] then
			warn(`Net: handler '{name}' failed: {tostring(results[2])}`)
			return nil
		end
		return table.unpack(results, 2, results.n)
	end
end

-- Server: create an event the server fires to clients (so clients can listen before the first fire).
function Net.declare(name: string)
	assert(RunService:IsServer(), "Net.declare is server-only")
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
