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
		Tex.resetFiles() -- a game may have configured files before this spec ran
		local ok, err = pcall(function()
			local id = Tex.fileFor("spark")
			t.ok(string.find(id, "rbxasset://textures/particles/", 1, true) ~= nil, "stock fallback")
			Tex.usePreview()
			local preview, grid = Tex.fileFor("smoke")
			t.eq(preview, "rbxasset://textures/moonbrick/smoke.png")
			t.eq(grid, 4)
			Tex.useFiles({ smoke = "rbxassetid://1" })
			t.eq(Tex.fileFor("smoke"), "rbxassetid://1")
		end)
		Tex.resetFiles() -- `require` is cached in a playtest: leave nothing for a second K.test()
		t.ok(ok, tostring(err))
		t.ok(string.find(Tex.fileFor("smoke"), "rbxasset://textures/particles/", 1, true) ~= nil, "reset to stock")
	end)

	t.test("the scheduler's global time scale scales every job's step", function()
		local seen = 0
		local jobs = Scheduler.count() -- a game's own jobs may be running in a playtest
		local stop = Scheduler.every(function(dt)
			seen += dt
			return false
		end)
		local scale = Scheduler.getTimeScale()
		Scheduler.setTimeScale(0.5)
		Scheduler.advance(0.2, "Heartbeat")
		Scheduler.setTimeScale(scale)
		stop()
		Scheduler.advance(0) -- removes the stopped job
		t.ok(math.abs(seen - 0.1) < 1e-9, "0.2 s at half speed")
		t.eq(Scheduler.count(), jobs)
	end)

	t.test("advance steps frozen jobs by the given dt, in both phases, and tells time scale listeners", function()
		local heartbeat, simulation = 0, 0
		local stopHeartbeat = Scheduler.every(function(dt)
			heartbeat += dt
			return false
		end)
		local stopSimulation = Scheduler.every(function(dt)
			simulation += dt
			return false
		end, "PreSimulation")
		local scale = Scheduler.getTimeScale()
		local told: number? = nil
		Scheduler.onTimeScale(function(value)
			told = value
		end)
		Scheduler.setTimeScale(0)
		t.eq(told, 0)
		Scheduler.advance(0.5)
		Scheduler.setTimeScale(scale)
		stopHeartbeat()
		stopSimulation()
		Scheduler.advance(0)
		t.eq(heartbeat, 0.5)
		t.eq(simulation, 0.5)
	end)

	t.test("Pose.clip refuses joints that aren't CFrames, naming the joint", function()
		t.fails(function()
			Pose.clip({
				name = "Bad",
				rig = "Any",
				length = 1,
				keys = { { t = 0, joints = { Waist = 5 :: any } } },
			})
		end, "joint 'Waist' must be a CFrame")
		t.fails(function()
			Pose.clip({ name = "Late", rig = "Any", length = 1, keys = { { t = 2, joints = {} } } })
		end, "inside the clip")
		local clip = Pose.clip({
			name = "Good",
			rig = "Any",
			length = 1,
			keys = { { t = 1, joints = {} }, { t = 0, joints = { Waist = CFrame.identity } } },
		})
		t.eq(clip.keys[1].t, 0, "keys sorted")
	end)

	t.test("one-shot audio cleanup uses the loaded length, not a guess", function()
		t.eq(Audio.lifetime(20, 1), 21)
		t.eq(Audio.lifetime(20, 2, 3), 14)
		t.eq(Audio.lifetime(0, 1), 7, "unknown length")
	end)

	t.test("debris layers end after their longest-lived chunk", function()
		t.eq(Fx.layerEnd({ kind = "debris" }), 2.5)
		t.eq(Fx.layerEnd({ kind = "debris", at = 1, lifetime = { 3 } }), 4.1)
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

	t.test("overlapping freezes resume the scale from before the first; the watchdog spares frozen effects", function()
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
		-- 20 of the 60 watchdog seconds so far; a long capture freeze must not count.
		handle:freeze(1000)
		task.wait(120)
		t.ok(not handle.finished, "a frozen effect outlives the watchdog")
		handle:stop()
		t.eq(Fx.live(), before)
		Scheduler.advance(0)

		local global = Fx.play(long, CFrame.new())
		Fx.setGlobalTimeScale(0)
		task.wait(120)
		t.ok(not global.finished, "a globally frozen effect outlives the watchdog")
		Fx.setGlobalTimeScale(1)
		task.wait(30)
		t.ok(not global.finished, "unfreezing restarts the count, it doesn't kill at once")
		task.wait(40)
		t.ok(global.finished, "a running effect that never finishes is still stopped")
		t.eq(Fx.live(), before)
		Scheduler.advance(0)
	end)

	local function emitterTemplate(scale: number): any
		local template = Instance.new("Model")
		template.Name = "PoolProbe" .. scale
		local part = Instance.new("Part")
		part.Parent = template
		template.PrimaryPart = part
		local emitter = Instance.new("ParticleEmitter")
		emitter.TimeScale = scale
		emitter.Lifetime = NumberRange.new(0.1, 0.1)
		emitter:SetAttribute("EmitCount", 3)
		emitter.Parent = part
		return template
	end

	local function played(handle: any): any
		return handle.root:FindFirstChildWhichIsA("ParticleEmitter", true)
	end

	t.test("pooled emitters keep their authored TimeScale through slow-mo and reuse", function()
		local template = emitterTemplate(0.8)
		local first = Fx.emit(template, CFrame.new(), { timeScale = 0.5 })
		t.ok(math.abs(played(first).TimeScale - 0.4) < 1e-9, "authored times option")
		first:stop()
		local second = Fx.emit(template, CFrame.new(), { timeScale = 0.5 })
		t.ok(math.abs(played(second).TimeScale - 0.4) < 1e-9, "doesn't halve again on reuse")
		second:freeze(0.1)
		t.eq(played(second).TimeScale, 0)
		second:stop()
		local third = Fx.emit(template, CFrame.new())
		t.ok(math.abs(played(third).TimeScale - 0.8) < 1e-9, "a copy released frozen recovers")
		third:stop()
		task.wait(0.2)
		Scheduler.advance(0)
	end)

	t.test("a failing pose stops itself and the next pose still plays", function()
		local function rig(): any
			local model = Instance.new("Model")
			local joint = Instance.new("Motor6D")
			joint.Name = "Waist"
			joint.Parent = model
			model.Parent = workspace
			return model, joint
		end
		local bad, _ = rig()
		local broken = Pose.play(bad, {
			name = "Broken",
			rig = "Any",
			length = 1,
			keys = { { t = 0, joints = { Waist = 5 :: any } } },
		})
		Scheduler.advance(0.1)
		t.ok(broken.finished, "the bad track ended")
		t.eq(Pose.activeCount(), 0, "and left nothing active")

		local good, joint = rig()
		local spin = CFrame.new(0, 2, 0)
		local track = Pose.play(
			good,
			Pose.clip({
				name = "Fine",
				rig = "Any",
				length = 1,
				keys = { { t = 0, joints = { Waist = spin } } },
			}),
			{ fadeIn = 0 }
		)
		Scheduler.advance(0.1)
		t.ok(track.time > 0, "Pose still runs after a failure")
		t.ok(joint.Transform ~= nil and joint.Transform.Position == spin.Position, "the joint moved")
		track:stop(0)
		Scheduler.advance(0.1)
		t.eq(Pose.activeCount(), 0)
		bad:Destroy()
		good:Destroy()
	end)

	t.test("audio: one-shots outlive a slow load, looped cues stay, dead assets are dropped", function()
		Audio.define({
			Long = { id = "rbxassetid://1" },
			Spin = { id = "rbxassetid://2", looped = true },
		})
		local sound: any = Audio.play("Long")
		t.ok(sound.Playing, "playing")
		task.wait(8) -- the old fixed 7 s bound would have cut it here
		t.ok(not sound.destroyed, "still loading")
		sound.IsLoaded, sound.TimeLength, sound.PlaybackSpeed = true, 20, 1
		sound.Loaded:Fire()
		task.wait(15)
		t.ok(not sound.destroyed, "a 20 s sound isn't cut at 7 s")
		task.wait(7)
		t.ok(sound.destroyed, "cleaned up after its length")

		local spinning: any = Audio.play("Spin")
		task.wait(120)
		t.ok(not spinning.destroyed, "looped cue keeps playing")
		spinning:Destroy()

		local dead: any = Audio.play("rbxassetid://404")
		task.wait(11)
		t.ok(dead.destroyed, "an asset that never loads is dropped")
	end)

	t.test("a client finds server-made sound groups under Master instead of duplicating them", function()
		local sound = t.fixtures.services.SoundService
		sound:ClearAllChildren() -- earlier tests made this client's own groups
		local master = Instance.new("SoundGroup")
		master.Name = "MoonbrickMaster"
		master.Parent = sound
		local sfx = Instance.new("SoundGroup")
		sfx.Name = "MoonbrickSFX"
		sfx.Parent = master
		t.eq(Audio.group("SFX"), sfx)
		t.eq(#sound:GetChildren(), 1)
	end)

	t.test("a superseded fov punch keeps the base for the next one", function()
		local VFX = t.require(Kit.VFX)
		local runtime = t.fixtures.runtime
		local camera: any = Instance.new("Folder")
		camera.FieldOfView = 70
		workspace.CurrentCamera = camera
		runtime.client = true
		VFX.fovPunch(10, 1)
		task.wait(0.5)
		VFX.fovPunch(10, 1) -- cancels the first tween
		task.wait(0.1)
		t.eq(camera:GetAttribute("VFXBaseFov"), 70, "the cancelled tween must not clear the base")
		VFX.fovPunch(10, 1)
		t.eq(camera.FieldOfView, 80, "third punch starts from the base, not mid-punch")
		task.wait(1.1)
		t.eq(camera.FieldOfView, 70)
		t.eq(camera:GetAttribute("VFXBaseFov"), nil)
		runtime.client = false
		workspace.CurrentCamera = nil
	end)

	local function spot(shape: string): any
		local part = Instance.new("Part")
		part.Name = "Spot"
		part.Size = Vector3.new(2, 3, 2)
		part.CFrame = CFrame.new(1, 2, 3)
		part.Color = Color3.new(1, 0, 0)
		part.Transparency = 0.25
		part:SetAttribute("GeoShape", shape)
		return part
	end

	t.test("Geo.dress: counts spots, copies transparency and welds the mesh so moving spots keep it", function()
		Geo.register("WeldProbe", function(b)
			b:box(CFrame.identity, Vector3.one)
		end)
		local root = Instance.new("Folder")
		local part = spot("WeldProbe")
		part.Parent = root
		t.eq(Geo.dress(root), 1)
		t.eq(Geo.dress(root), 0, "already dressed")
		local mesh: any = part:FindFirstChild("SpotMesh")
		t.ok(mesh ~= nil and mesh:IsA("MeshPart"))
		t.eq(mesh.Transparency, 0.25)
		t.eq(mesh.Anchored, false)
		t.eq(mesh.Massless, true)
		local weld: any = mesh:FindFirstChildOfClass("WeldConstraint")
		t.ok(weld and weld.Part0 == part and weld.Part1 == mesh, "welded to the spot")
		t.eq(part.Transparency, 1)
		root:Destroy()
	end)

	t.test("Geo.watch waits for the game, keeps dressing late spots and stops cleanly", function()
		local game: any = t.fixtures.game
		local runtime = t.fixtures.runtime
		Geo.register("WatchProbe", function(b)
			b:box(CFrame.identity, Vector3.one)
		end)
		local root = Instance.new("Folder")
		local early = spot("WatchProbe")
		early.Parent = root
		runtime.client, game.loaded = true, false
		local stop = Geo.watch(root)
		task.wait(1)
		t.eq(early:GetAttribute("GeoDressed"), nil, "nothing happens before game.Loaded")
		game.loaded = true
		game.Loaded:Fire()
		task.wait(1)
		t.eq(early:GetAttribute("GeoDressed"), true)

		local folder = Instance.new("Folder")
		local late = spot("WatchProbe")
		late.Parent = folder
		folder.Parent = root -- a whole map arrives at once
		task.wait(1)
		t.eq(late:GetAttribute("GeoDressed"), true, "a spot added later is dressed")

		local tagged = spot("WatchProbe")
		tagged:SetAttribute("GeoShape", nil)
		tagged.Parent = root
		tagged:SetAttribute("GeoShape", "WatchProbe")
		t.fixtures.services.CollectionService:AddTag(tagged, Geo.SpotTag)
		task.wait(1)
		t.eq(tagged:GetAttribute("GeoDressed"), true, "a tagged spot is picked up after its attribute arrives")

		stop()
		local after = spot("WatchProbe")
		after.Parent = root
		task.wait(1)
		t.eq(after:GetAttribute("GeoDressed"), nil, "stopped")
		t.ok(late:FindFirstChild("SpotMesh"), "stopping keeps meshes")
		runtime.client = false
		root:Destroy()
	end)

	t.test("a failed async bake frees the builder and the fixed mesh", function()
		local function box(b)
			b:box(CFrame.identity, Vector3.one)
		end
		local live = assets.live
		assets.failBake = true
		t.fails(function()
			Geo.build(box)
		end, "bake failed")
		assets.failBake = false
		t.eq(assets.live, live, "builder freed when the bake fails")
		assets.failPart = true
		t.fails(function()
			Geo.build(box)
		end, "mesh part failed")
		assets.failPart = false
		t.eq(assets.live, live, "fixed mesh freed when the part fails")
	end)

	t.test("Geo.free releases a built part's mesh; a plain Destroy drops the bookkeeping", function()
		local live = assets.live
		local part = Geo.build(function(b)
			b:box(CFrame.identity, Vector3.one)
		end)
		t.eq(assets.live, live + 1, "the fixed mesh stays alive with its part")
		Geo.free(part)
		t.eq(assets.live, live)
		t.ok(part.destroyed)
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
