return function(t: any)
	local Kit = game:GetService("ServerScriptService").Kit
	local Cooldown, Round, Economy = t.require(Kit.Cooldown), t.require(Kit.Round), t.require(Kit.Economy)
	t.test("cooldowns isolate players and expire on their exact boundary", function()
		local now = 0
		local gate = Cooldown.new(function()
			return now
		end)
		t.eq(gate:use("A", 2), true)
		t.eq(gate:use("A", 2), false)
		t.eq(gate:use("B", 2), true)
		now = 2
		t.eq(gate:use("A", 2), true)
		t.eq(gate:prune(), 1)
		gate:clear("A")
		t.eq(gate:remaining("A"), 0)
	end)
	t.test("invalid cooldowns and round configuration fail early", function()
		t.fails(function()
			Cooldown.new():use("A", 0 / 0)
		end, "finite")
		t.fails(function()
			Round.new({ duration = 0 })
		end, "positive")
		t.fails(function()
			Round.new({ minPlayers = 1.5 })
		end, "integer")
	end)
	t.test("round lifecycle is server-driven and cancels insufficient-player countdowns", function()
		local now = 0
		local round = Round.new({
			clock = function()
				return now
			end,
			intermission = 2,
			duration = 5,
			results = 1,
		})
		t.eq(round:step(1).state, "Waiting")
		t.eq(round:step(2).state, "Intermission")
		t.eq(round:step(1).state, "Waiting")
		round:step(2)
		now = 2
		t.eq(round:step(2).state, "Playing")
		t.eq(round.roundId, 1)
		now = 7
		t.eq(round:step(2).state, "Results")
		now = 8
		t.eq(round:step(2).state, "Waiting")
	end)
	t.test("player loss ends a round and snapshots do not expose controller state", function()
		local now = 0
		local round = Round.new({
			clock = function()
				return now
			end,
		})
		round:step(2)
		round:skip()
		round:step(2)
		t.eq(round:step(0).state, "Results")
		local snapshot = round:snapshot()
		snapshot.state = "Playing"
		t.eq(round.state, "Results")
	end)
	t.test("economy rejects unaffordable, repeated, unknown and invalid purchases without mutation", function()
		local data = { Coins = 10, Inventory = {} }
		local catalog = { Sword = { price = 7 }, Crown = { price = 50 }, Bad = { price = -1 } }
		t.eq(Economy.buy(data, catalog, "Crown"), false)
		t.eq(Economy.buy(data, catalog, "Bad"), false)
		t.eq(Economy.buy(data, catalog, "Missing"), false)
		t.eq(data.Coins, 10)
		t.eq(Economy.buy(data, catalog, "Sword"), true)
		t.eq(data.Coins, 3)
		t.eq(Economy.buy(data, catalog, "Sword"), false)
		t.eq(#data.Inventory, 1)
	end)
	t.test("currency rewards reject overflow, NaN and negative values", function()
		local data = { Coins = 1, Inventory = {} }
		t.eq(Economy.award(data, -1), false)
		t.eq(Economy.award(data, 0 / 0), false)
		t.eq(Economy.award(data, 9007199254740991), false)
		t.eq(Economy.award(data, 2), true)
		t.eq(data.Coins, 3)
	end)
end
