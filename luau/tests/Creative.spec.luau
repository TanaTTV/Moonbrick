-- Pure logic of the creative modules. Runs in Studio (K.test) and headless in CI (no Instances).
-- The Fx/Geo playback tests at the end need the headless engine stand-ins (`t.fixtures`).
return function(t: any)
	local Kit = game:GetService("ReplicatedStorage").Kit
	local Motion = t.require(Kit.Motion)
	local Fx = t.require(Kit.Fx)
	local Pose = t.require(Kit.Pose)
	local Audio = t.require(Kit.Audio)
	local Tex = t.require(Kit.Tex)
	local Scheduler = t.require(Kit.Scheduler)

	t.test("easing curves start at 0, end at 1 and clamp; unknown names are linear", function()
		for _, name in { "linear", "quadOut", "cubicOut", "expoOut", "backOut", "sineInOut", "anticipate" } do
			t.ok(math.abs(Motion.ease(name, 0)) < 1e-6, name .. " at 0")
			t.ok(math.abs(Motion.ease(name, 1) - 1) < 1e-6, name .. " at 1")
		end
		t.ok(Motion.ease("backOut", 0.6) > 1, "backOut overshoots")
		t.ok(Motion.ease("anticipate", 0.2) < 0, "anticipate pulls back first")
		t.eq(Motion.ease("nope", 0.25), 0.25)
		t.eq(Motion.ease("quadOut", 2), 1)
		t.eq(Motion.ease("quadOut", 0 / 0), 0)
		t.ok(Motion.isEase("expoIn") and not Motion.isEase("expo"))
	end)

	t.test("keyframes hold before the first and after the last key and ease each segment", function()
		local keys = { { t = 0, v = 0 }, { t = 1, v = 10, ease = "linear" }, { t = 2, v = 0, ease = "quadOut" } }
		t.eq(Motion.sample(keys, -1), 0)
		t.eq(Motion.sample(keys, 0.5), 5)
		t.eq(Motion.sample(keys, 1.5), 10 - 10 * Motion.ease("quadOut", 0.5))
		t.eq(Motion.sample(keys, 9), 0)
		t.eq(Motion.length(keys), 2)
	end)

	t.test("springs settle on their target without blowing up on long frames", function()
		local s = { value = 0, velocity = 0, target = 1, speed = 12, damping = 0.7 }
		for _ = 1, 120 do
			Motion.springStep(s, 1 / 60)
		end
		t.ok(math.abs(s.value - 1) < 0.01, "settled")
		local big = { value = 0, velocity = 0, target = 1, speed = 30, damping = 0.5 }
		Motion.springStep(big, 0.5)
		t.ok(math.abs(big.value) < 3, "sub-stepping keeps a 0.5 s frame stable")
	end)

	t.test("Fx quality scales counts, filters layers and never emits zero for a nonzero count", function()
		t.eq(Fx.countFor(100, "High", 1), 100)
		t.eq(Fx.countFor(100, "Low", 1), 35)
		t.eq(Fx.countFor(1, "Low", 1), 1)
		t.eq(Fx.countFor(5000, "High", 4), 400)
		t.ok(Fx.allowed({ kind = "particles", count = 1 }, "Low"))
		t.ok(not Fx.allowed({ kind = "particles", count = 1, minQuality = "Medium" }, "Low"))
		t.ok(Fx.allowed({ kind = "particles", count = 1, minQuality = "Medium" }, "High"))
	end)

	t.test("Fx layer timing covers particle lifetimes and mesh keys", function()
		t.eq(Fx.layerEnd({ kind = "particles", at = 1, count = 5, lifetime = { 0.5, 2 } }), 3)
		t.eq(Fx.layerEnd({ kind = "particles", at = 0, rate = 5, duration = 2, lifetime = { 1 } }), 3)
		t.eq(Fx.layerEnd({ kind = "mesh", at = 0.5, keys = { { t = 0 }, { t = 0.75 } } }), 1.25)
		local def = Fx.define({
			name = "Test",
			layers = { { kind = "event", at = 4, name = "late" }, { kind = "event", at = 1, name = "early" } },
		})
		t.eq(Fx.length(def), 4)
	end)

	t.test("Fx.define rejects bad layers with a useful message", function()
		t.fails(function()
			Fx.define({ name = "Bad", layers = { { kind = "sparkle" } } } :: any)
		end, "unknown kind")
		t.fails(function()
			Fx.define({ name = "Bad", layers = { { kind = "particles" } } })
		end, "needs count")
		t.fails(function()
			Fx.define({ name = "Bad", layers = { { kind = "mesh", keys = { { t = 1 }, { t = 0.5 } } } } })
		end, "after the previous key")
		t.fails(function()
			Fx.define({ name = "", layers = {} })
		end, "needs a name")
	end)

	t.test("rig classification tells R15, R6 and custom rigs apart", function()
		t.eq(Pose.classify(Pose.R15), "R15")
		t.eq(Pose.classify(Pose.R6), "R6")
		t.eq(Pose.classify({ "Hinge", "Wheel" }), "Custom")
	end)

	t.test("audio pitch variation stays inside the cue's range", function()
		t.eq(Audio.pitchFor({ id = "x" }), 1)
		t.eq(Audio.pitchFor({ id = "x", pitch = 1.3 }), 1.3)
		t.eq(Audio.pitchFor({ id = "x", pitch = { 0.9, 1.1 } }, 0), 0.9)
		t.eq(Audio.pitchFor({ id = "x", pitch = { 0.9, 1.1 } }, 1), 1.1)
	end)

	t.test("texture alpha stays in 0..1 and every shape fades to nothing outside its radius", function()
		for _, name in { "glow", "core", "ring", "spark", "star", "streak", "smoke", "dust", "shard", "crack", "wisp" } do
			for _, uv in { { 0, 0 }, { 0.3, -0.2 }, { -0.7, 0.4 }, { 0.99, 0.99 } } do
				local a = Tex.alpha(name, uv[1], uv[2], nil, 0.5)
				t.ok(a >= 0 and a <= 1, `{name} alpha {a} out of range`)
			end
			t.ok(Tex.alpha(name, 1.2, 1.2) < 1e-6, name .. " outside the circle")
		end
		t.ok(Tex.alpha("glow", 0, 0) > 0.99, "glow centre is solid")
		t.ok(Tex.alpha("ring", 0, 0) < 0.01, "ring centre is empty")
	end)

	t.test("file textures: stock fallback, then preview, then uploaded ids win", function()
		local id = Tex.fileFor("spark")
		t.ok(string.find(id, "rbxasset://textures/particles/", 1, true) ~= nil, "stock fallback")
		Tex.usePreview()
		local preview, grid = Tex.fileFor("smoke")
		t.eq(preview, "rbxasset://textures/moonbrick/smoke.png")
		t.eq(grid, 4)
		Tex.useFiles({ smoke = "rbxassetid://1" })
		t.eq(Tex.fileFor("smoke"), "rbxassetid://1")
	end)

	t.test("the scheduler's global time scale scales every job's step", function()
		local seen = 0
		local stop = Scheduler.every(function(dt)
			seen += dt
			return false
		end)
		Scheduler.setTimeScale(0.5)
		Scheduler.advance(0.2)
		Scheduler.setTimeScale(1)
		stop()
		Scheduler.advance(0) -- removes the stopped job
		t.ok(math.abs(seen - 0.1) < 1e-9, "0.2 s at half speed")
		t.eq(Scheduler.count(), 0)
	end)

	if not t.fixtures then
		return
	end
	local Geo = t.require(Kit.Geo)
	local assets = t.fixtures.assets

	local function named(name: string): any
		local found
		for _, inst in t.fixtures.instances do
			if inst.Name == name then
				found = inst
			end
		end
		return found
	end

	local rings = Fx.define({
		name = "Rings",
		layers = {
			{ kind = "mesh", name = "Halo", shape = "torus", keys = { { t = 0, size = 4 }, { t = 0.2, size = 6 } } },
			{ kind = "mesh", name = "Spike", shape = "shard", keys = { { t = 0, size = 1 } } },
		},
	})

	t.test("Fx falls back to plain parts when meshes can't be made", function()
		local before = Fx.live()
		assets.denied = true
		local handle = Fx.play(rings, CFrame.new())
		assets.denied = false
		Scheduler.advance(0) -- the first frame applies the keys
		local halo, spike = named("Halo"), named("Spike")
		t.eq(halo.ClassName, "Part")
		t.eq(halo.Shape, Enum.PartType.Cylinder)
		t.ok(math.abs(halo.Size.X - 0.48) < 1e-6 and halo.Size.Y == 4, "torus disc keeps its thickness")
		t.eq(spike.ClassName, "WedgePart")
		t.eq(Fx.live(), before + 1)
		handle:stop()
		t.eq(Fx.live(), before)
	end)

	t.test("a layer that fails to build rolls the effect back", function()
		local before, jobs = Fx.live(), Scheduler.count()
		t.fails(function()
			Fx.play(Fx.define({ name = "Broken", layers = { { kind = "particles", count = 5 } } }), CFrame.new())
		end, "does not implement Attachment")
		t.eq(Fx.live(), before)
		t.eq(Scheduler.count(), jobs)
		t.ok(named("Fx_Broken").destroyed, "partial root destroyed")
	end)

	t.test("Geo.cached builds once for concurrent first callers; Fx.preload warms Fx shapes", function()
		local builds = assets.builds
		local results = {}
		for i = 1, 2 do
			task.spawn(function()
				results[i] = Geo.cached("SingleFlight", function(b)
					b:box(CFrame.identity, Vector3.one)
				end)
			end)
		end
		t.eq(results[1], nil, "first build yields")
		task.wait(0.5)
		t.ok(results[1] ~= nil and results[1] == results[2], "both callers share one template")
		t.eq(assets.builds - builds, 1)
		t.fails(function()
			Geo.cached("Retry", function()
				error("bad shape")
			end)
		end, "bad shape")
		t.ok(Geo.cached("Retry", function(b)
			b:box(CFrame.identity, Vector3.one)
		end) ~= nil, "failures are not cached")

		t.ok(Fx.preload())
		builds = assets.builds
		local handle = Fx.play(rings, CFrame.new())
		t.eq(named("Halo").ClassName, "MeshPart")
		t.eq(named("Spike").ClassName, "MeshPart")
		t.eq(assets.builds, builds, "preloaded shapes are cloned, not rebuilt")
		handle:stop()
	end)

	local long = Fx.define({ name = "Long", layers = { { kind = "event", at = 15, name = "late" } } })

	t.test("overlapping freezes resume the scale from before the first; a watchdog ends stuck effects", function()
		local before = Fx.live()
		local handle = Fx.play(long, CFrame.new(), { timeScale = 0.5 })
		handle:freeze(0.1)
		handle:freeze(0.3)
		handle:setTimeScale(0.25) -- while frozen: applies when the freeze ends
		task.wait(0.2)
		Scheduler.advance(1)
		t.eq(handle.time, 0, "the longer freeze still holds")
		task.wait(0.2)
		Scheduler.advance(1)
		t.eq(handle.time, 0.25)
		handle:freeze(1000)
		task.wait(61)
		t.ok(handle.finished, "watchdog stopped the frozen effect")
		t.eq(Fx.live(), before)
		Scheduler.advance(0)
	end)

	t.test("listeners attached after Fx.play see events at t = 0", function()
		local before = Fx.live()
		local handle = Fx.play(
			Fx.define({ name = "Start", layers = { { kind = "event", at = 0, name = "start" } } }),
			CFrame.new()
		)
		local fired = false
		handle:on("start", function()
			fired = true
		end)
		t.ok(not fired and not handle.finished, "nothing runs before the first frame")
		Scheduler.advance(1 / 60)
		t.ok(fired, "t = 0 event reached the listener")
		t.ok(handle.finished)
		t.eq(Fx.live(), before)
		Scheduler.advance(0)
	end)
end
