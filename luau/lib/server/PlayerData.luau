--!strict
-- PlayerData: load and save per-player data safely (server only).
--  * Session locking: only the server that loaded a player's data may write it, so hopping servers
--    can't duplicate items or roll progress back.
--  * Retries with backoff, autosave, save on leave and on server shutdown.
--  * Template reconcile: fields you add to the template later appear in old saves.
--  * Studio uses memory by default. Real DataStore access requires studioStore = "live" in a test place.
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
	UpdateAsync: (self: any, key: string, transform: (any, any?) -> ...any) -> any,
}

export type Config = {
	template: { [string]: any },
	name: string?, -- DataStore name (default "PlayerData"); change it to start fresh
	leaderstats: { string }?, -- template keys to show on the leaderboard
	autosave: number?, -- seconds between autosaves (default 60)
	store: Store?, -- override the DataStore (tests use PlayerData.memoryStore())
	studioStore: ("memory" | "live")?, -- default memory; never point Studio at production stores
	onLoadFailed: ((Player, string) -> ())?, -- default: kick with a friendly message
	onSessionLost: ((Player, string) -> ())?, -- default: kick rather than allow unsaved play
	-- Saved data that fails validation is never loaded or overwritten by default (the player gets
	-- onLoadFailed). To recover, return replacement data from a copy, e.g. `onInvalidData = PlayerData.sanitize`.
	-- Must not yield. Return nil to keep refusing. The original is kept in the record's `backups` list.
	onInvalidData: ((data: any, reason: string) -> { [string]: any }?)?,
}

export type Migrate = (data: any, reason: string) -> { [string]: any }?

local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
local LOCK_TIMEOUT = 600 -- a lock not refreshed for this long belongs to a dead server
local IN_STUDIO = RunService:IsStudio()

local function deepCopy<T>(value: T, seen: { [any]: any }?): T
	if type(value) ~= "table" then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		return visited[value]
	end
	local copy = {}
	visited[value] = copy
	for k, v in value :: any do
		copy[deepCopy(k, visited)] = deepCopy(v, visited)
	end
	return copy :: any
end
PlayerData.deepCopy = deepCopy

-- Reject values DataStore serialization could drop, corrupt, or fail to encode.
local function validate(value: any, ancestors: { [any]: boolean }?, depth: number?)
	local kind = type(value)
	if kind == "number" then
		assert(value == value and math.abs(value) < math.huge, "data contains a non-finite number")
	elseif kind == "string" then
		assert(utf8.len(value) ~= nil, "data contains invalid UTF-8")
	elseif kind == "table" then
		local stack = ancestors or {}
		local level = depth or 0
		assert(level < 64, "data nesting exceeds 64 levels")
		assert(not stack[value], "data contains a cycle")
		assert(getmetatable(value) == nil, "data contains a metatable")
		stack[value] = true
		local strings, numbers, largest = 0, 0, 0
		for key, item in value do
			if type(key) == "string" then
				strings += 1
				validate(key)
			else
				assert(
					type(key) == "number" and key >= 1 and key < math.huge and key % 1 == 0,
					"data has an invalid table key"
				)
				numbers += 1
				largest = math.max(largest, key)
			end
			validate(item, stack, level + 1)
		end
		assert(strings == 0 or numbers == 0, "data has mixed array/dictionary keys")
		assert(numbers == 0 or largest == numbers, "data has a sparse array")
		stack[value] = nil
	else
		assert(kind == "boolean", "data contains unsupported value type: " .. kind)
	end
end
PlayerData.validate = validate

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

-- Opt-in recovery for `onInvalidData`: a valid copy that drops non-finite numbers, invalid strings and
-- unsupported values (template defaults refill dropped keys), compacts sparse arrays in index order and
-- drops the numeric keys of mixed tables. The original record is always backed up before it is replaced.
local function sanitize(value: any, depth: number): any
	local kind = type(value)
	if kind == "number" then
		return if value == value and math.abs(value) < math.huge then value else nil
	elseif kind == "string" then
		return if utf8.len(value) ~= nil then value else nil
	elseif kind == "boolean" then
		return value
	elseif kind ~= "table" or depth >= 63 then
		return nil
	end
	local strings, indices = {}, {}
	for key in value do
		if type(key) == "string" and utf8.len(key) ~= nil then
			table.insert(strings, key)
		elseif type(key) == "number" and key >= 1 and key < math.huge and key % 1 == 0 then
			table.insert(indices, key)
		end
	end
	local result: { [any]: any } = {}
	if #strings > 0 then
		for _, key in strings do
			result[key] = sanitize(value[key], depth + 1)
		end
	else
		table.sort(indices)
		for _, index in indices do
			local item = sanitize(value[index], depth + 1)
			if item ~= nil then
				table.insert(result, item)
			end
		end
	end
	return result
end
function PlayerData.sanitize(data: any, _reason: string?): { [string]: any }?
	local clean = sanitize(data, 0)
	return if type(clean) == "table" then clean else nil
end

local MAX_BACKUPS = 3 -- recoveries kept in the record; beyond this, loading refuses instead of discarding one

-- In-memory store with DataStore-like copy semantics. Used for tests and Studio without API access.
function PlayerData.memoryStore(): Store & { values: { [string]: any } }
	local store = { values = {} }
	function store.UpdateAsync(self: any, key: string, transform: (any, any?) -> ...any): any
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
		token: string,
		busy: boolean,
		closing: boolean,
		migrate: Migrate?,
	},
	Session
))

type SessionOptions =
	{ jobId: string?, retries: number?, retryDelay: number?, ignoreLocks: boolean?, migrate: Migrate? }

function Session.new(store: Store, key: string, template: { [string]: any }, opts: SessionOptions?): Session
	local o: SessionOptions = opts or {}
	validate(template)
	assert(o.retries == nil or (o.retries >= 1 and o.retries <= 10 and o.retries % 1 == 0), "retries must be 1..10")
	assert(o.retryDelay == nil or (o.retryDelay >= 0 and o.retryDelay <= 10), "retryDelay must be 0..10")
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
		ignoreLocks = false, -- retained for compatibility; ownership checks cannot be disabled
		token = HttpService:GenerateGUID(false),
		busy = false,
		closing = false,
		migrate = o.migrate,
	}, Session)
end

local function check(value: any): string?
	local ok, err = pcall(function()
		validate(value)
		return true
	end)
	return if ok then nil else tostring(err)
end

-- Run the game's recovery callback on a copy. Returns replacement data, or nil + why loading must refuse.
local function migrateData(self: Session, raw: any, reason: string): ({ [string]: any }?, string?)
	if not self.migrate then
		return nil, `saved data is invalid ({reason}); not loaded or overwritten. Set onInvalidData to recover`
	end
	local thread = coroutine.create(self.migrate)
	local ok, result = coroutine.resume(thread, deepCopy(raw), reason)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		return nil, "onInvalidData must not yield; saved data left unchanged"
	end
	if not ok then
		return nil, `onInvalidData failed ({result}); saved data left unchanged`
	end
	if result == nil then
		return nil, `saved data is invalid ({reason}); onInvalidData declined to recover it`
	end
	if type(result) ~= "table" then
		return nil, "onInvalidData must return a table or nil; saved data left unchanged"
	end
	local migrated = reconcile(result, self.template)
	local problem = check(migrated)
	if problem then
		return nil, `onInvalidData returned invalid data ({problem}); saved data left unchanged`
	end
	return migrated
end

local function lockFor(self: Session)
	return { job = self.jobId, token = self.token, time = os.time() }
end

local function owns(self: Session, lock: any): boolean
	return type(lock) == "table" and lock.job == self.jobId and lock.token == self.token
end

-- Hold this gate across yielding DataStore calls and retries, so an autosave cannot race release.
local function acquire(self: Session)
	while self.busy do
		task.wait()
	end
	self.busy = true
end

-- Load and lock. Returns false + reason if the data is locked by a live server or the store keeps failing.
function Session.load(self: Session): (boolean, string?)
	acquire(self)
	if self.loaded or self.released or self.closing then
		self.busy = false
		return false, "session already loaded or closed"
	end
	local lastError = "unknown error"
	for attempt = 1, self.retries do
		local result, lockedBy, refused: string? = nil, nil, nil
		local ok, err = pcall(function()
			local committed = self.store:UpdateAsync(self.key, function(stored, info)
				result, lockedBy, refused = nil, nil, nil
				if stored == nil then
					stored = {}
				end
				assert(type(stored) == "table", "invalid stored record; refusing to replace it")
				local lock = stored.lock
				if lock and not owns(self, lock) and os.time() - (lock.time or 0) < LOCK_TIMEOUT then
					lockedBy = lock.job
					return nil -- don't write; another live server owns this data
				end
				local raw = stored.data
				local data: { [string]: any }?, problem: string? = nil, nil
				if raw == nil then
					data = deepCopy(self.template)
				elseif type(raw) ~= "table" then
					problem = `saved data is a {type(raw)}, not a table`
				else
					data = reconcile(deepCopy(raw), self.template)
					problem = check(data)
				end
				if problem then
					-- Never drop the original: it goes into a bounded backup list before replacement.
					local backups = stored.backups
					if backups ~= nil and (type(backups) ~= "table" or #backups >= MAX_BACKUPS) then
						refused =
							`saved data is invalid ({problem}) and the record already holds {MAX_BACKUPS} recovery backups; inspect it manually`
						return nil
					end
					data, refused = migrateData(self, raw, problem :: string)
					if not data then
						return nil -- don't write; the record stays exactly as it was
					end
					backups = backups or {}
					table.insert(backups, { data = raw, reason = problem, time = os.time(), job = self.jobId })
					stored.backups = backups
				end
				stored.data = data
				stored.lock = lockFor(self)
				if info then
					return stored, info:GetUserIds(), info:GetMetadata()
				end
				return stored
			end)
			result = if committed and owns(self, committed.lock) then deepCopy(committed.data) else nil
		end)
		if ok and result then
			self.data, self.loaded = result, true
			self.busy = false
			return true
		end
		if ok and refused then
			self.busy = false
			return false, refused -- invalid saved data is permanent; retrying cannot help
		end
		lastError = if not ok then tostring(err) else `locked by another server ({lockedBy})`
		if attempt < self.retries then
			task.wait(self.retryDelay * attempt)
		end
	end
	self.busy = false
	return false, lastError
end

-- Write the data (refreshing the lock), or release the lock with `release = true`.
-- Returns false if another server has taken the lock (this session then stops saving).
function Session.save(self: Session, release: boolean?): (boolean, string?)
	if release then
		self.closing = true -- reject queued autosaves as soon as the final save is requested
	elseif self.closing then
		return false, "session closing"
	end
	acquire(self)
	if not self.loaded or self.released then
		self.busy = false
		return false, "session not active"
	end
	if self.closing and not release then
		self.busy = false
		return false, "session closing"
	end
	local copied, data = pcall(function()
		validate(self.data)
		return deepCopy(self.data)
	end)
	local invalid: string? = nil
	if not copied then
		if not release then
			self.busy = false
			return false, tostring(data)
		end
		-- Invalid data can never be written. Still release the lock (keeping the last good save) so the
		-- player isn't locked out of every server until LOCK_TIMEOUT.
		invalid = tostring(data)
	end
	local lastError = "unknown error"
	for attempt = 1, math.min(self.retries, 3) do
		local lost = false
		local ok, err = pcall(function()
			self.store:UpdateAsync(self.key, function(stored, info)
				lost = false
				if not stored or not owns(self, stored.lock) then
					lost = true
					return nil
				end
				if not invalid then
					stored.data = deepCopy(data) -- stable snapshot on every UpdateAsync callback invocation
				end
				stored.lock = if release then nil else lockFor(self)
				if info then
					return stored, info:GetUserIds(), info:GetMetadata()
				end
				return stored
			end)
		end)
		if ok and lost then
			self.released = true
			self.busy = false
			return false, "lock taken by another server; not overwriting"
		elseif ok then
			if release then
				self.released = true
			end
			self.busy = false
			if invalid then
				return false, `invalid data not saved (lock released, last good save kept): {invalid}`
			end
			return true
		end
		lastError = tostring(err)
		if attempt < math.min(self.retries, 3) then
			task.wait(self.retryDelay * attempt)
		end
	end
	self.busy = false
	return false, lastError
end

-- Player API ---------------------------------------------------------------------

local config: Config? = nil
local store: Store? = nil
local sessions: { [Player]: Session } = {}
local failed: { [Player]: boolean } = {}
local closing = false
local activeOperations = 0
local loadedEvent = Instance.new("BindableEvent")

-- Fires (player, data) when a player's data has loaded.
PlayerData.loaded = loadedEvent.Event

-- Never switch an acquired persistent session to memory after a transient provider failure.
local function dataStore(name: string): Store
	return DataStoreService:GetDataStore(name) :: any
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

local function onLeave(player: Player)
	local session = sessions[player]
	failed[player] = nil
	if session and session.loaded then
		session.closing = true
		local ok, err = session:save(true)
		if not ok then
			warn(`PlayerData: final save for {player.Name} failed: {err}`)
		end
	end
	-- Keep in-flight loads/saves visible to shutdown until they finish.
	if session and session.loaded and session.released then
		sessions[player] = nil
	end
end

local function onJoin(player: Player)
	if closing or sessions[player] then
		return
	end
	local cfg = config :: Config
	local session =
		Session.new(store :: Store, "Player_" .. player.UserId, cfg.template, { migrate = cfg.onInvalidData })
	sessions[player] = session
	local ok, err = session:load()
	if closing or player.Parent ~= Players then -- left or shutdown began while loading
		if ok then
			onLeave(player) -- retain failed releases for autosave/shutdown retry
		else
			sessions[player] = nil
		end
		return
	end
	if not ok then
		sessions[player] = nil
		failed[player] = true
		warn(`PlayerData: failed to load {player.Name}: {err}`)
		if cfg.onLoadFailed then
			cfg.onLoadFailed(player, err or "unknown")
		else
			player:Kick(
				"Your data couldn't be loaded right now (it may still be saving from another server). Please rejoin in a minute."
			)
		end
		return
	end
	buildLeaderstats(player, session.data :: any)
	loadedEvent:Fire(player, session.data)
end

local function tracked(fn: (Player) -> (), player: Player)
	activeOperations += 1
	local ok, err = pcall(function()
		fn(player)
		return true
	end)
	activeOperations -= 1
	if not ok then
		warn(`PlayerData: lifecycle operation for {player.Name} failed: {err}`)
	end
end

local function sessionLost(player: Player, session: Session, reason: string)
	if sessions[player] ~= session or session.closing or not session.released then
		return
	end
	sessions[player] = nil
	if player.Parent ~= Players then
		return -- already left; onLeave cleared `failed`, don't re-add a reference to a gone Player
	end
	failed[player] = true
	local callback = config and config.onSessionLost
	if callback then
		callback(player, reason)
	else
		player:Kick("Your data session ended. Please rejoin to keep your progress safe.")
	end
end

function PlayerData.start(cfg: Config)
	assert(RunService:IsServer(), "PlayerData runs on the server")
	assert(config == nil, "PlayerData.start called twice")
	assert(
		cfg.autosave == nil or (cfg.autosave >= 10 and cfg.autosave < LOCK_TIMEOUT / 2),
		"autosave must be 10..299 seconds"
	)
	local selectedStore = cfg.store
	if not selectedStore then
		if IN_STUDIO and cfg.studioStore ~= "live" then
			warn(
				"PlayerData: Studio uses memory; data resets each playtest. Use studioStore = 'live' only in a separate test experience."
			)
			selectedStore = PlayerData.memoryStore()
		else
			selectedStore = dataStore(cfg.name or "PlayerData")
		end
	end
	config = cfg
	store = selectedStore

	Players.PlayerAdded:Connect(function(player)
		tracked(onJoin, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracked(onLeave, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(tracked, onJoin, player)
	end

	task.spawn(function()
		while not closing do
			task.wait(cfg.autosave or 60)
			if closing then
				break
			end
			for player, session in sessions do
				if session.loaded and not session.released then
					if session.closing then
						task.spawn(tracked, onLeave, player) -- retry a failed leave save; still visible to shutdown
						continue
					end
					task.spawn(function()
						local ok, err = session:save(false)
						if not ok then
							warn(`PlayerData: autosave for {player.Name} failed: {err}`)
							sessionLost(player, session, err or "session ownership lost")
						end
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		closing = true
		local pending = 0
		local attempts: { [Session]: number } = {}
		local deadline = os.clock() + 25
		local unsaved = false
		repeat
			unsaved = false
			local waiting = false
			for player, session in sessions do
				if session.loaded and not session.released then
					unsaved = true
					if session.busy then
						waiting = true
					elseif (attempts[session] or 0) < 2 then
						attempts[session] = (attempts[session] or 0) + 1
						pending += 1
						task.spawn(function()
							tracked(onLeave, player)
							pending -= 1
						end)
					end
				end
			end
			if pending == 0 and activeOperations == 0 and not waiting then
				break
			end
			task.wait(0.1)
		until os.clock() >= deadline
		if unsaved or pending > 0 or activeOperations > 0 then
			-- Recompute because a synchronous successful release can remove the last retained session.
			local retained = false
			for _, session in sessions do
				if session.loaded and not session.released then
					retained = true
				end
			end
			if retained or pending > 0 or activeOperations > 0 then
				warn("PlayerData: shutdown ended with unsaved data operations after bounded retries")
			end
		end
	end)
end

-- The player's data table, or nil if not loaded (yet). Mutate it directly, or use set/increment/update.
function PlayerData.get(player: Player): { [string]: any }?
	local session = sessions[player]
	return if session and session.loaded and not session.released and not session.closing then session.data else nil
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
	local valid, reason = pcall(function()
		validate(value)
		return true
	end)
	if not valid then
		warn(`PlayerData.set({player.Name}, {key}): rejected value: {reason}`)
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
	if type(new) ~= "number" or new ~= new or math.abs(new) == math.huge then
		warn(`PlayerData.increment({player.Name}, {key}): rejected non-finite result`)
		return nil
	end
	data[key] = new
	syncLeaderstat(player, key, new)
	return new
end

-- Nonyielding transaction: callback errors, yields and invalid values never partially mutate live data.
-- Keep external effects (remotes, DataStores) outside the callback. Outer data table identity is preserved.
function PlayerData.update(player: Player, fn: ({ [string]: any }) -> ()): (boolean, string?)
	local data = PlayerData.get(player)
	if not data then
		warn(`PlayerData.update({player.Name}): data not loaded`)
		return false, "data not loaded"
	end
	local staged = deepCopy(data)
	local thread = coroutine.create(fn)
	local ok, err = coroutine.resume(thread, staged)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		warn("PlayerData.update: callback yielded; transaction cancelled")
		return false, "callback must not yield"
	end
	if not ok then
		warn(`PlayerData.update: transaction cancelled: {err}`)
		return false, tostring(err)
	end
	local valid, reason = pcall(function()
		validate(staged)
		return true
	end)
	if not valid then
		warn(`PlayerData.update: invalid data; transaction cancelled: {reason}`)
		return false, tostring(reason)
	end
	table.clear(data)
	for key, value in staged do
		data[key] = value
	end
	local keys: { string } = (config and config.leaderstats) or {}
	for _, key in keys do
		syncLeaderstat(player, key, data[key])
	end
	return true
end

-- Save now (e.g. right after a purchase). Autosave and leave/shutdown saves happen automatically.
function PlayerData.save(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	local ok, err = session:save(false)
	if not ok then
		warn(`PlayerData.save({player.Name}) failed: {err}`)
		sessionLost(player, session, err or "session ownership lost")
	end
	return ok
end

return PlayerData
