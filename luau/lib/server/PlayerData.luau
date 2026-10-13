--!strict
-- PlayerData: load and save per-player data safely (server only).
--  * Session locking: only the server that loaded a player's data may write it, so hopping servers
--    can't duplicate items or roll progress back.
--  * Retries with backoff, autosave, save on leave and on server shutdown.
--  * Template reconcile: fields you add to the template later appear in old saves.
--  * Studio without API access falls back to an in-memory store (one warning) so playtests still run.
--
--   PlayerData.start({ template = { Coins = 0, Inventory = {} }, leaderstats = { "Coins" } })
--   local data = PlayerData.wait(player)          -- table, or nil if the player left / load failed
--   PlayerData.increment(player, "Coins", 5)      -- updates the data and the leaderstat
--   PlayerData.update(player, function(data) table.insert(data.Inventory, "Sword") end)
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerData = {}

export type Store = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

export type Config = {
	template: { [string]: any },
	name: string?, -- DataStore name (default "PlayerData"); change it to start fresh
	leaderstats: { string }?, -- template keys to show on the leaderboard
	autosave: number?, -- seconds between autosaves (default 60)
	store: Store?, -- override the DataStore (tests use PlayerData.memoryStore())
	onLoadFailed: ((Player, string) -> ())?, -- default: kick with a friendly message
}

local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
local LOCK_TIMEOUT = 600 -- a lock not refreshed for this long belongs to a dead server
local IN_STUDIO = RunService:IsStudio()

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy :: any
end
PlayerData.deepCopy = deepCopy

-- Fill keys missing from `data` with copies of the template's values (recursively for dictionaries).
local function reconcile(data: { [any]: any }, template: { [any]: any }): { [any]: any }
	for k, v in template do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil and #v == 0 then
			reconcile(data[k], v)
		end
	end
	return data
end
PlayerData.reconcile = reconcile

-- In-memory store with DataStore-like copy semantics. Used for tests and Studio without API access.
function PlayerData.memoryStore(): Store & { values: { [string]: any } }
	local store = { values = {} }
	function store.UpdateAsync(self: any, key: string, transform: (any) -> any): any
		local new = transform(deepCopy(self.values[key]))
		if new ~= nil then
			self.values[key] = deepCopy(new)
		end
		return new
	end
	return store :: any
end

-- Session: one player's data in one server. Exposed for tests; games use the Player API below.
local Session = {}
Session.__index = Session
PlayerData.Session = Session

export type Session = typeof(setmetatable(
	{} :: {
		store: Store,
		key: string,
		template: { [string]: any },
		data: { [string]: any }?,
		loaded: boolean,
		released: boolean,
		jobId: string,
		retries: number,
		retryDelay: number,
		ignoreLocks: boolean,
	},
	Session
))

function Session.new(
	store: Store,
	key: string,
	template: { [string]: any },
	opts: { jobId: string?, retries: number?, retryDelay: number?, ignoreLocks: boolean? }?
): Session
	local o: { jobId: string?, retries: number?, retryDelay: number?, ignoreLocks: boolean? } = opts or {}
	return setmetatable({
		store = store,
		key = key,
		template = template,
		data = nil,
		loaded = false,
		released = false,
		jobId = o.jobId or JOB_ID,
		retries = o.retries or 5,
		retryDelay = o.retryDelay or 2,
		ignoreLocks = if o.ignoreLocks ~= nil then o.ignoreLocks else IN_STUDIO,
	}, Session)
end

-- Load and lock. Returns false + reason if the data is locked by a live server or the store keeps failing.
function Session.load(self: Session): (boolean, string?)
	local lastError = "unknown error"
	for attempt = 1, self.retries do
		local result, lockedBy = nil, nil
		local ok, err = pcall(function()
			self.store:UpdateAsync(self.key, function(stored)
				result, lockedBy = nil, nil
				stored = stored or {}
				local lock = stored.lock
				if
					lock
					and lock.job ~= self.jobId
					and os.time() - (lock.time or 0) < LOCK_TIMEOUT
					and not self.ignoreLocks
				then
					lockedBy = lock.job
					return nil -- don't write; another live server owns this data
				end
				stored.data = reconcile(stored.data or deepCopy(self.template), self.template)
				stored.lock = { job = self.jobId, time = os.time() }
				result = stored.data
				return stored
			end)
		end)
		if ok and result then
			self.data, self.loaded = result, true
			return true
		end
		lastError = if not ok then tostring(err) else `locked by another server ({lockedBy})`
		if attempt < self.retries then
			task.wait(self.retryDelay * attempt)
		end
	end
	return false, lastError
end

-- Write the data (refreshing the lock), or release the lock with `release = true`.
-- Returns false if another server has taken the lock (this session then stops saving).
function Session.save(self: Session, release: boolean?): (boolean, string?)
	if not self.loaded or self.released then
		return false, "session not active"
	end
	local data = self.data
	local lastError = "unknown error"
	for attempt = 1, math.min(self.retries, 3) do
		local lost = false
		local ok, err = pcall(function()
			self.store:UpdateAsync(self.key, function(stored)
				lost = false
				stored = stored or {}
				if stored.lock and stored.lock.job ~= self.jobId and not self.ignoreLocks then
					lost = true
					return nil
				end
				stored.data = data
				stored.lock = if release then nil else { job = self.jobId, time = os.time() }
				return stored
			end)
		end)
		if ok and lost then
			self.released = true
			return false, "lock taken by another server; not overwriting"
		elseif ok then
			if release then
				self.released = true
			end
			return true
		end
		lastError = tostring(err)
		if attempt < 3 then
			task.wait(self.retryDelay * attempt)
		end
	end
	return false, lastError
end

-- Player API ---------------------------------------------------------------------

local config: Config? = nil
local store: Store? = nil
local sessions: { [Player]: Session } = {}
local failed: { [Player]: boolean } = {}
local loadedEvent = Instance.new("BindableEvent")

-- Fires (player, data) when a player's data has loaded.
PlayerData.loaded = loadedEvent.Event

local function isApiAccessError(err: string): boolean
	local e = err:lower()
	return e:find("studio access to api", 1, true) ~= nil
		or e:find("403", 1, true) ~= nil
		or e:find("api services", 1, true) ~= nil
		or e:find("not allowed", 1, true) ~= nil
end

-- DataStore wrapper that switches to memory (with a warning) when Studio has no API access.
local function dataStore(name: string): Store
	local fallback: Store? = nil
	local gotStore, real = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	if not gotStore then
		if not IN_STUDIO then
			error(real, 0)
		end
		warn(`PlayerData: DataStores unavailable in Studio ({real}); using an in-memory store (data resets each playtest).`)
		return PlayerData.memoryStore()
	end
	local wrapper = {}
	function wrapper.UpdateAsync(_: any, key: string, transform: (any) -> any): any
		if fallback then
			return fallback:UpdateAsync(key, transform)
		end
		local ok, result = pcall(real.UpdateAsync, real, key, transform)
		if ok then
			return result
		end
		if IN_STUDIO and isApiAccessError(tostring(result)) then
			warn("PlayerData: Studio has no DataStore access, using an in-memory store (data resets each playtest). Enable 'Studio Access to API Services' in Game Settings > Security to test real saves.")
			local mem = PlayerData.memoryStore()
			fallback = mem
			return mem:UpdateAsync(key, transform)
		end
		error(result, 0)
	end
	return wrapper :: any
end

local function statValue(value: any): ValueBase?
	if type(value) == "number" then
		return if value % 1 == 0 then Instance.new("IntValue") else Instance.new("NumberValue")
	elseif type(value) == "string" then
		return Instance.new("StringValue")
	end
	return nil
end

local function syncLeaderstat(player: Player, key: string, value: any)
	local stats = player:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild(key)
	if v and v:IsA("ValueBase") then
		(v :: any).Value = value
	end
end

local function buildLeaderstats(player: Player, data: { [string]: any })
	local keys = config and config.leaderstats
	if not keys or #keys == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, key in keys do
		local v = statValue(data[key])
		if v then
			v.Name = key;
			(v :: any).Value = data[key]
			v.Parent = folder
		else
			warn(`PlayerData: leaderstat '{key}' must be a number or string in the template`)
		end
	end
	folder.Parent = player
end

local function onJoin(player: Player)
	local cfg = config :: Config
	local session = Session.new(store :: Store, "Player_" .. player.UserId, cfg.template)
	sessions[player] = session
	local ok, err = session:load()
	if player.Parent ~= Players then -- left while loading
		if ok then
			session:save(true)
		end
		sessions[player] = nil
		return
	end
	if not ok then
		sessions[player] = nil
		failed[player] = true
		warn(`PlayerData: failed to load {player.Name}: {err}`)
		if cfg.onLoadFailed then
			cfg.onLoadFailed(player, err or "unknown")
		else
			player:Kick("Your data couldn't be loaded right now (it may still be saving from another server). Please rejoin in a minute.")
		end
		return
	end
	buildLeaderstats(player, session.data :: any)
	loadedEvent:Fire(player, session.data)
end

local function onLeave(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	failed[player] = nil
	if session and session.loaded then
		local ok, err = session:save(true)
		if not ok then
			warn(`PlayerData: final save for {player.Name} failed: {err}`)
		end
	end
end

function PlayerData.start(cfg: Config)
	assert(RunService:IsServer(), "PlayerData runs on the server")
	assert(config == nil, "PlayerData.start called twice")
	config = cfg
	store = cfg.store or dataStore(cfg.name or "PlayerData")

	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end

	task.spawn(function()
		while true do
			task.wait(cfg.autosave or 60)
			for player, session in sessions do
				if session.loaded and not session.released then
					task.spawn(function()
						local ok, err = session:save(false)
						if not ok then
							warn(`PlayerData: autosave for {player.Name} failed: {err}`)
						end
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				onLeave(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- The player's data table, or nil if not loaded (yet). Mutate it directly, or use set/increment/update.
function PlayerData.get(player: Player): { [string]: any }?
	local session = sessions[player]
	return if session and session.loaded then session.data else nil
end

-- Wait until the player's data has loaded. Returns nil if they leave or loading fails.
function PlayerData.wait(player: Player, timeout: number?): { [string]: any }?
	local deadline = os.clock() + (timeout or 60)
	while os.clock() < deadline and player.Parent == Players do
		local data = PlayerData.get(player)
		if data then
			return data
		end
		if failed[player] then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

function PlayerData.set(player: Player, key: string, value: any)
	local data = PlayerData.get(player)
	if not data then
		warn(`PlayerData.set({player.Name}, {key}): data not loaded`)
		return
	end
	data[key] = value
	syncLeaderstat(player, key, value)
end

function PlayerData.increment(player: Player, key: string, delta: number): number?
	local data = PlayerData.get(player)
	if not data then
		warn(`PlayerData.increment({player.Name}, {key}): data not loaded`)
		return nil
	end
	local new = (data[key] or 0) + delta
	data[key] = new
	syncLeaderstat(player, key, new)
	return new
end

-- Edit the data in a function; leaderstats are refreshed afterwards.
function PlayerData.update(player: Player, fn: ({ [string]: any }) -> ())
	local data = PlayerData.get(player)
	if not data then
		warn(`PlayerData.update({player.Name}): data not loaded`)
		return
	end
	fn(data)
	local keys: { string } = (config and config.leaderstats) or {}
	for _, key in keys do
		syncLeaderstat(player, key, data[key])
	end
end

-- Save now (e.g. right after a purchase). Autosave and leave/shutdown saves happen automatically.
function PlayerData.save(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	return (session:save(false))
end

return PlayerData
