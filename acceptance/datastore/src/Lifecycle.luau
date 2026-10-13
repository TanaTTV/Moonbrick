--!strict
-- Exercise the unchanged Player API / BindToClose body in an isolated service environment.
-- No real Players are attached. Only this synthetic logical key can reach the mapper.
local Lifecycle = {}

function Lifecycle.new(factory: any, services: any, runtime: any, store: any, key: string, migrate: any?): any
	local function signal(): any
		local listeners: { any } = {}
		return {
			Connect = function(_self: any, fn: any)
				table.insert(listeners, fn)
			end,
			Fire = function(_self: any, ...: any)
				for _, fn in listeners do
					runtime.spawn(fn, ...)
				end
			end,
		}
	end
	local players: any = {
		PlayerAdded = signal(),
		PlayerRemoving = signal(),
		GetPlayers = function()
			return {}
		end,
	}
	local close: any = nil
	local proxy: any = { JobId = "acceptance-lifecycle" }
	function proxy:GetService(name: string): any
		if name == "Players" then
			return players
		end
		return services[name]
	end
	function proxy:BindToClose(fn: any)
		close = fn
	end
	local data = factory(proxy, runtime.task, runtime.Instance)
	local pause, entered, saving, saveOk = false, false, false, false
	local mapped: any = {}
	function mapped:UpdateAsync(logical: string, transform: any): any
		assert(logical == "Player_AcceptanceSynthetic", "unexpected Player API key; refused")
		if pause then
			pause = false
			entered = true
			runtime.wait(0.25) -- deterministic in-flight save, no extra provider calls
		end
		return store:UpdateAsync(key, transform)
	end
	data.start({
		template = { Coins = 0, Gems = 0 },
		store = mapped,
		studioStore = "live",
		autosave = 299,
		onInvalidData = migrate,
		onLoadFailed = function(_player: any, why: string)
			runtime.log("LOAD REFUSED: " .. why)
		end,
	})
	local player: any = {
		Name = "AcceptanceSynthetic",
		UserId = "AcceptanceSynthetic",
		Parent = players,
		FindFirstChild = function()
			return nil
		end,
		Kick = function()
			error("unexpected synthetic kick")
		end,
	}
	players.PlayerAdded:Fire(player)
	local loaded = data.wait(player, 10)
	local adapter: any = { data = data, player = player, loaded = loaded }
	function adapter:beginSave()
		assert(self.loaded, "synthetic player failed to load")
		pause, saving = true, true
		runtime.spawn(function()
			saveOk = data.save(player)
			saving = false
		end)
		for _ = 1, 100 do
			if entered then
				break
			end
			runtime.wait(0.01)
		end
		assert(entered and saving, "save was not in flight")
	end
	function adapter:close()
		assert(close, "PlayerData did not register BindToClose")
		close() -- EXACT shipped callback, not a hand-written session release
	end
	function adapter:saveResult(): boolean
		return saveOk and not saving
	end
	return adapter
end

return Lifecycle
