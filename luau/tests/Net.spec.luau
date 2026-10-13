return function(t: any)
	local Net = t.require(game:GetService("ReplicatedStorage").Kit.Net)

	t.test("number rejects NaN, infinity and non-numbers", function()
		local v = Net.number()
		t.eq(v(0 / 0), false, "NaN")
		t.eq(v(math.huge), false, "inf")
		t.eq(v(-math.huge), false, "-inf")
		t.eq(v("5"), false, "string")
		t.eq(v(5), true)
	end)

	t.test("number and int enforce ranges", function()
		t.eq(Net.number(0, 10)(11), false)
		t.eq(Net.number(0, 10)(-1), false)
		t.eq(Net.int(1, 99)(1.5), false, "fraction")
		t.eq(Net.int(1, 99)(99), true)
	end)

	t.test("string enforces type and max length", function()
		t.eq(Net.string(3)("abcd"), false)
		t.eq(Net.string(3)("abc"), true)
		t.eq(Net.string()(nil), false)
	end)

	t.test("oneOf, optional, boolean, vector3", function()
		t.eq(Net.oneOf("sword", "bow")("bow"), true)
		t.eq(Net.oneOf("sword", "bow")("axe"), false)
		t.eq(Net.optional(Net.int())(nil), true)
		t.eq(Net.optional(Net.int())(1.5), false)
		t.eq(Net.boolean()(false), true)
		t.eq(Net.boolean()(0), false)
		t.eq(Net.vector3(10)(Vector3.new(0, 0 / 0, 0)), false, "NaN vector")
		t.eq(Net.vector3(10)(Vector3.new(100, 0, 0)), false, "too large")
	end)

	t.test("instance checks class and ancestry", function()
		local folder = Instance.new("Folder")
		local part = Instance.new("Part")
		part.Parent = folder
		t.eq(Net.instance("BasePart")(part), true)
		t.eq(Net.instance("Model")(part), false)
		t.eq(Net.instance("BasePart", workspace)(part), false, "not under workspace")
		folder:Destroy()
	end)

	t.test("check rejects extra arguments and reports the bad position", function()
		local validators = { Net.string(10), Net.int() }
		t.eq(Net.check(validators, { "a", 1 } :: { any }, 2), true)
		local ok, err = Net.check(validators, { "a", 1, "extra" } :: { any }, 3)
		t.eq(ok, false)
		t.ok(string.find(err, "too many", 1, true), err)
		local ok2, err2 = Net.check(validators, { "a", 0.5 } :: { any }, 2)
		t.eq(ok2, false)
		t.ok(string.find(err2, "argument 2", 1, true), err2)
	end)

	t.test("a broken custom validator rejects instead of throwing through a remote", function()
		local ok, err = Net.check({
			function()
				error("validator bug")
			end,
		}, { "input" }, 1)
		t.eq(ok, false)
		t.ok(err:find("validator failed", 1, true))
		t.eq(
			Net.check({
				function()
					return "truthy"
				end,
			}, { "input" }, 1),
			false
		)
	end)

	-- Deterministic remote integration fixtures are supplied by the standalone test bundles.
	-- The in-game test runner still runs the engine-backed validator specs above.
	if not t.loadNet then
		return
	end
	local function fixture()
		local now = 0
		local warnings: { string } = {}
		local remotes: { [string]: any } = {}
		local removing: any = {}
		function removing:Connect(fn: any)
			self.callback = fn
		end
		local players = { PlayerRemoving = removing }
		local folder: any = {
			IsA = function(_, class: string)
				return class == "Folder"
			end,
		}
		function folder:FindFirstChild(name: string)
			return remotes[name]
		end
		local replication = {
			FindFirstChild = function()
				return folder
			end,
		}
		local services: { [string]: any } = {
			Players = players,
			ReplicatedStorage = replication,
			RunService = {
				IsServer = function()
					return true
				end,
			},
		}
		local instances = {
			new = function(class: string)
				local signal: any = {}
				function signal:Connect(fn: any)
					self.callback = fn
					return { Disconnect = function() end }
				end
				local r: any = {
					OnServerEvent = signal,
					IsA = function(_, requested: string)
						return requested == class
					end,
				}
				return setmetatable(r, {
					__newindex = function(self: any, key: string, value: any)
						rawset(self, key, value)
						if key == "Parent" then
							remotes[self.Name] = self
						end
					end,
				})
			end,
		}
		local net = t.loadNet(
			{
				GetService = function(_, name: string)
					return services[name]
				end,
			},
			instances,
			{
				clock = function()
					return now
				end,
			},
			function(message: string)
				table.insert(warnings, message)
			end
		)
		return {
			net = net,
			warnings = warnings,
			player = { Name = "Test", UserId = 1 },
			other = { Name = "Other", UserId = 2 },
			at = function(value: number)
				now = value
			end,
			leave = function(player: any)
				removing.callback(player)
			end,
			fire = function(name: string, player: any, ...: any)
				remotes[name].OnServerEvent.callback(player, ...)
			end,
			invoke = function(name: string, player: any, ...: any)
				return remotes[name].OnServerInvoke(player, ...)
			end,
		}
	end

	t.test("Net counts event/request rejections per remote, reason and distinct active player", function()
		local f = fixture()
		local calls = 0
		f.net.on("Event", { f.net.int() }, function()
			calls += 1
		end, { rate = 2 })
		f.net.handle("Request", {}, function()
			calls += 1
		end)
		f.fire("Event", f.player, "bad")
		f.fire("Event", f.player, "bad")
		f.fire("Event", f.player, 1) -- exhausted bucket, rejected before handler
		f.fire("Event", f.other, 1) -- accepted calls do not create rejection counters
		f.invoke("Request", f.other, "extra")
		local stats = f.net.stats()
		t.eq(calls, 1)
		t.eq(stats.Event.total, 3)
		t.eq(stats.Event.reasons["argument 1: expected finite number"], 2)
		t.eq(stats.Event.reasons["rate limit"], 1)
		t.eq(stats.Event.distinctPlayers, 1)
		t.eq(stats.Request.total, 1)
		t.eq(stats.Request.distinctPlayers, 1)
		t.eq(#f.warnings, 2)
	end)

	t.test("Net stats snapshots isolate nested reasons and remote tables", function()
		local f = fixture()
		f.net.on("Copy", {}, function() end)
		f.fire("Copy", f.player, "extra")
		local copy = f.net.stats()
		copy.Copy.total = 999
		copy.Copy.distinctPlayers = 999
		copy.Copy.reasons["too many arguments (1 > 0)"] = 999
		copy.Copy.reasons.fake = 999
		copy.Fake = copy.Copy
		local fresh = f.net.stats()
		t.eq(fresh.Copy.total, 1)
		t.eq(fresh.Copy.distinctPlayers, 1)
		t.eq(fresh.Copy.reasons["too many arguments (1 > 0)"], 1)
		t.eq(fresh.Copy.reasons.fake, nil)
		t.eq(fresh.Fake, nil)
	end)

	t.test("Net summaries count continued rejections and are limited per remote to 60 seconds", function()
		local f = fixture()
		f.net.on("Summary", {}, function() end)
		f.net.on("Independent", {}, function() end)
		f.fire("Summary", f.player, "extra")
		f.fire("Independent", f.player, "extra")
		f.at(59)
		f.fire("Summary", f.player, "extra")
		t.eq(#f.warnings, 2)
		f.at(60)
		f.fire("Summary", f.player, "extra")
		t.eq(#f.warnings, 3)
		t.ok(f.warnings[3]:find("rejected 2 more calls", 1, true))
		f.fire("Independent", f.player, "extra")
		t.eq(#f.warnings, 4, "each remote has its own summary clock")
		f.at(119)
		f.fire("Summary", f.player, "extra")
		t.eq(#f.warnings, 4)
		f.at(120)
		f.fire("Summary", f.player, "extra")
		t.eq(#f.warnings, 5)
		t.ok(f.warnings[5]:find("rejected 2 more calls", 1, true))
		f.at(1000)
		t.eq(#f.warnings, 5, "no timer logs after rejection stops")
		f.fire("Summary", f.player, "extra")
		t.ok(f.warnings[6]:find("rejected 1 more calls", 1, true))
	end)

	t.test("Net caps dynamic reason buckets and retained reason length", function()
		local f = fixture()
		f.net.on("Bounded", {
			function(value: any)
				return false, tostring(value)
			end,
		}, function() end, { rate = 100 })
		for i = 1, 40 do
			f.fire("Bounded", f.player, string.rep("x", 1000) .. i)
		end
		for i = 1, 40 do
			f.fire("Bounded", f.player, tostring(i))
		end
		local count, sum = 0, 0
		for reason, amount in f.net.stats().Bounded.reasons do
			count += 1
			sum += amount
			t.ok(#reason <= 160)
		end
		t.eq(count, 16)
		t.eq(sum, 80)
		t.eq(f.net.stats().Bounded.reasons.other, 26)
	end)

	t.test("Net leave cleanup releases distinct players, warnings and token buckets", function()
		local f = fixture()
		f.net.on("Leave", {}, function() end, { rate = 1 })
		f.fire("Leave", f.player, "extra")
		f.fire("Leave", f.other, "extra")
		t.eq(f.net.stats().Leave.distinctPlayers, 2)
		f.leave(f.player)
		f.leave(f.player) -- repeated cleanup must not decrement twice
		t.eq(f.net.stats().Leave.distinctPlayers, 1)
		t.eq(f.net.stats().Leave.total, 2, "lifetime counts survive leave")
		f.fire("Leave", f.player, "extra") -- same identity models rejoin; full bucket and fresh warning
		t.eq(f.net.stats().Leave.distinctPlayers, 2)
		t.eq(f.net.stats().Leave.reasons["rate limit"], nil)
		t.eq(#f.warnings, 3)
		f.leave(f.player)
		f.leave(f.other)
		t.eq(f.net.stats().Leave.distinctPlayers, 0)
	end)

	t.test("Net counts pending request rejection and cleans in-flight state on leave", function()
		local f = fixture()
		local started = 0
		f.net.handle("Pending", {}, function()
			started += 1
			coroutine.yield()
		end, { maxInFlight = 1 })
		local first = coroutine.create(function()
			f.invoke("Pending", f.player)
		end)
		t.ok(coroutine.resume(first))
		f.invoke("Pending", f.player)
		t.eq(f.net.stats().Pending.reasons["too many pending requests"], 1)
		f.leave(f.player)
		local second = coroutine.create(function()
			f.invoke("Pending", f.player)
		end)
		t.ok(coroutine.resume(second))
		t.eq(started, 2)
		t.ok(coroutine.resume(first))
		t.ok(coroutine.resume(second))
		t.eq(f.net.stats().Pending.distinctPlayers, 0)
	end)
end
