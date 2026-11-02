-- MCPKit logic that needs no Studio: path resolution, audit rules and capture stops. Runs headless too.
return function(t: any)
	local K = t.require(game:GetService("ServerStorage").MCPKit)

	t.test("K.get resolves everything K.path prints, dotted names included", function()
		if t.isolated then
			return -- the isolated Studio bundle keeps its tree out of the DataModel, so paths can't resolve
		end
		local folder = Instance.new("Folder")
		folder.Name = "KGetProbe"
		local spec = Instance.new("Folder")
		spec.Name = "Creative.spec"
		spec.Parent = folder
		local inner = Instance.new("Folder")
		inner.Name = "Inner"
		inner.Parent = spec
		folder.Parent = workspace
		t.eq(K.get(K.path(spec)), spec)
		t.eq(K.get("game." .. K.path(inner)), inner)
		t.eq(K.get(folder), folder)
		t.fails(function()
			K.get("Workspace.KGetProbe.Nope.spec")
		end, "not found")
		folder:Destroy()
	end)

	t.test("model export encodes the value types its widened classes use", function()
		t.eq(K.encode(Vector2.new(1, 2)).Vector2[2], 2)
		t.eq(K.encode(NumberRange.new(1, 3)).NumberRange[2], 3)
		local size = K.encode(NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		}))
		t.eq(size.NumberSequence.keypoints[1].envelope, 0.5)
		t.eq(size.NumberSequence.keypoints[2].time, 1)
		local color = K.encode(ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.new(0, 0, 1)),
		}))
		t.eq(color.ColorSequence.keypoints[2].color[3], 1)
	end)

	t.test("capture viewpoints come from CFrames, positions and look targets", function()
		local cf = CFrame.new(1, 2, 3)
		t.eq(K.frameFrom(cf), cf)
		t.eq(K.frameFrom(Vector3.new(0, 0, 5)).Position, Vector3.new(0, 0, 5))
		local look = K.frameFrom(Vector3.new(0, 0, 5), Vector3.zero)
		t.ok((look.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-6)
		local part = Instance.new("Part")
		part.CFrame = CFrame.new(5, 0, 5)
		t.ok((K.frameFrom(Vector3.new(0, 0, 5), part).LookVector - Vector3.new(1, 0, 0)).Magnitude < 1e-6)
		t.fails(function()
			K.frameFrom("up")
		end, "CFrame or a Vector3")
		t.fails(function()
			K.frameFrom(Vector3.one, Vector3.one)
		end, "its own position")
		local stop = K.tourStop({ at = Vector3.new(0, 0, 5), look = Vector3.zero, fov = 40, label = "gate" }, 2)
		t.eq(stop.fov, 40)
		t.eq(stop.label, "gate")
		t.eq(K.tourStop(cf, 3).label, "stop 3")
		t.fails(function()
			K.tourStop({ fov = 40 }, 1)
		end, "needs cf or at")
	end)

	t.test("the audit flags Humanoid:LoadAnimation, not Animator:LoadAnimation", function()
		t.eq(#K.lintLine("local track = humanoid:LoadAnimation(anim)"), 1)
		t.eq(#K.lintLine("local track = animator:LoadAnimation(anim)"), 0)
		t.eq(#K.lintLine("local track = (animator :: Animator):LoadAnimation(source)"), 0)
		t.eq(#K.lintLine("wait(1)"), 1)
		t.eq(#K.lintLine("task.wait(1)"), 0)
	end)

	if not t.fixtures then
		return -- the rest drives the game's Scheduler and camera through stand-ins
	end
	local Kit = game:GetService("ReplicatedStorage").Kit
	local Scheduler = t.require(Kit.Scheduler)
	local Fx = t.require(Kit.Fx)
	local runtime = t.fixtures.runtime
	local world: any = workspace

	t.test(
		"K.freeze reaches the game's copy through attributes; K.step moves one frame; K.unfreeze restores",
		function()
			local seen = 0
			local stop = Scheduler.every(function(dt)
				seen += dt
				return false
			end)
			local template = Instance.new("Part")
			local emitter = Instance.new("ParticleEmitter")
			emitter.TimeScale = 0.5
			emitter.Parent = template
			template.Parent = workspace
			t.ok(string.find(K.freeze(), "1 emitters", 1, true), "held the emitter")
			t.eq(K.freeze(), "already frozen")
			t.eq(Scheduler.getTimeScale(), 0)
			t.eq(emitter.TimeScale, 0)
			Scheduler.advance(0)
			K.step(0.25)
			t.eq(seen, 0.25, "one exact step while frozen")
			t.eq(emitter.TimeScale, 0, "frozen again after the step")
			K.step(0.25)
			t.eq(seen, 0.5, "a repeat of the same dt still fires")
			K.unfreeze()
			t.eq(Scheduler.getTimeScale(), 1)
			t.eq(emitter.TimeScale, 0.5, "authored scale back")
			t.fails(function()
				K.step()
			end, "needs K.freeze")
			stop()
			Scheduler.advance(0)
			template:Destroy()
		end
	)

	t.test("K.freeze reaches running Fx emitters and keeps effects alive across a long shoot", function()
		local long = Fx.define({ name = "Held", layers = { { kind = "event", at = 15, name = "late" } } })
		local handle = Fx.play(long, CFrame.new())
		K.freeze()
		t.fixtures.frame(200)
		t.ok(not handle.finished, "still there 200 s later")
		K.unfreeze()
		handle:stop()
		Scheduler.advance(0)
	end)

	t.test("K.cam binds after the default camera, holds it, hides the avatar and K.release undoes it all", function()
		local players = t.fixtures.services.Players
		local previous = players.LocalPlayer
		local character = Instance.new("Model")
		local head = Instance.new("Part")
		head.Parent = character
		players.LocalPlayer = { Character = character }
		local camera: any = Instance.new("Folder")
		camera.CFrame, camera.CameraType, camera.FieldOfView = CFrame.new(), Enum.CameraType.Custom, 70
		world.CurrentCamera = camera
		t.fails(function()
			K.cam(Vector3.new(0, 0, 9), Vector3.zero)
		end, "Client datamodel")
		runtime.client = true
		K.cam(Vector3.new(0, 0, 9), Vector3.zero, { fov = 30 })
		local run = t.fixtures.services.RunService
		run.bound.MoonbrickCapture()
		t.eq(camera.CameraType, Enum.CameraType.Scriptable)
		t.eq(camera.CFrame.Position, Vector3.new(0, 0, 9))
		t.eq(camera.FieldOfView, 30)
		t.eq(head.LocalTransparencyModifier, 1)
		K.cam(CFrame.new(1, 1, 1))
		run.bound.MoonbrickCapture()
		t.eq(camera.CFrame.Position, Vector3.new(1, 1, 1), "a second K.cam replaces the first")
		K.release()
		t.eq(run.bound.MoonbrickCapture, nil)
		t.eq(camera.CameraType, Enum.CameraType.Custom)
		t.eq(camera.FieldOfView, 70)
		t.eq(head.LocalTransparencyModifier, 0)
		players.LocalPlayer = previous
		world.CurrentCamera = nil
		runtime.client = false
	end)

	t.test("K.tour walks its stops one call at a time, freezing where asked", function()
		local camera: any = Instance.new("Folder")
		camera.CFrame, camera.CameraType, camera.FieldOfView = CFrame.new(), Enum.CameraType.Custom, 70
		world.CurrentCamera = camera
		runtime.client = true
		local run = t.fixtures.services.RunService
		local stops: { any } = {}
		table.insert(stops, { at = Vector3.new(0, 10, 0), look = Vector3.xAxis, label = "gate" })
		table.insert(stops, { cf = CFrame.new(5, 5, 5), freeze = true })
		table.insert(stops, CFrame.new(9, 9, 9))
		t.eq(K.tour("Town", stops), "Town 1/3 gate")
		run.bound.MoonbrickCapture()
		t.eq(camera.CFrame.Position, Vector3.new(0, 10, 0))
		t.eq(K.tour("Town"), "Town 2/3 stop 2")
		t.eq(Scheduler.getTimeScale(), 0, "this stop froze")
		t.eq(K.tour("Town"), "Town 3/3 stop 3")
		t.eq(Scheduler.getTimeScale(), 1, "leaving a frozen stop thaws")
		run.bound.MoonbrickCapture()
		t.eq(camera.CFrame.Position, Vector3.new(9, 9, 9))
		t.eq(K.tour("Town"), "Town done")
		t.eq(run.bound.MoonbrickCapture, nil, "the camera goes back")
		t.fails(function()
			K.tour("Town")
		end, "no tour")
		world.CurrentCamera = nil
		runtime.client = false
	end)
end
