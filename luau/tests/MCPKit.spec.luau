return function(t: any)
	local K = t.require(game:GetService("ServerStorage").MCPKit)
	t.test("logs include a warning raised in the same call", function()
		local saved = K._mark -- don't move the caller's mark
		K.mark()
		print("MCPKit logs same-call probe") -- print + filter: a warn would pollute the caller's later K.logs()
		local logs = K.logs("same-call probe")
		K._mark = saved
		t.ok(string.find(logs, "same-call probe", 1, true), "warning missed; K.logs read stale history")
	end)
	t.test("audit refuses to run in a playtest instead of reporting engine-script false positives", function()
		if game:GetService("RunService"):IsRunning() then
			t.ok(string.find(K.audit(), "Edit mode only", 1, true))
		end
	end)
	t.test("model attributes use explicit Rojo types", function()
		local part = Instance.new("Part")
		part:SetAttribute("Active", true)
		part:SetAttribute("Count", 3)
		part:SetAttribute("Tint", Color3.new(1, 0.5, 0))
		local encoded = game:GetService("HttpService"):JSONDecode(K.toModelJson(part))
		t.eq(encoded.properties.Attributes.Active.Bool, true)
		t.eq(encoded.properties.Attributes.Count.Float64, 3)
		t.eq(encoded.properties.Attributes.Tint.Color3[2], 0.5)
		part:Destroy()
	end)
	t.test("complex assets cannot be silently truncated by basic export", function()
		local mesh = Instance.new("MeshPart")
		t.fails(function()
			K.toModelJson(mesh)
		end, "native Rojo syncback")
		mesh:Destroy()
		local model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Parent = model
		model.PrimaryPart = part
		t.fails(function()
			K.toModelJson(model)
		end, "PrimaryPart")
		model:Destroy()
	end)
	t.test("spawns, seats, trusses, emitters, prompts and uploaded meshes export with their settings", function()
		local HttpService = game:GetService("HttpService")
		local model = Instance.new("Model")
		local spawn = Instance.new("SpawnLocation")
		spawn.Neutral = false
		spawn.TeamColor = BrickColor.new("Bright red")
		spawn.Parent = model
		local seat = Instance.new("Seat")
		seat.Disabled = true
		seat.Parent = model
		local truss = Instance.new("TrussPart")
		truss.Parent = model
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 2, 0)
		attachment.Parent = spawn
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 7
		emitter.Lifetime = NumberRange.new(1, 2)
		emitter.Transparency = NumberSequence.new(0.5)
		emitter.Color = ColorSequence.new(Color3.new(1, 0, 0))
		emitter.Parent = attachment
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.Parent = spawn
		local encoded = HttpService:JSONDecode(K.toModelJson(model))
		local kids = {}
		for _, child in encoded.children do
			kids[child.className] = child
		end
		t.eq(kids.SpawnLocation.properties.Neutral, false)
		t.eq(kids.SpawnLocation.properties.TeamColor.BrickColor, spawn.TeamColor.Number)
		t.eq(kids.Seat.properties.Disabled, true)
		t.ok(kids.TrussPart ~= nil)
		local inner = {}
		for _, child in kids.SpawnLocation.children do
			inner[child.className] = child
		end
		t.eq(inner.ProximityPrompt.properties.ActionText, "Open")
		local fx = inner.Attachment.children[1].properties
		t.eq(fx.Rate, 7)
		t.eq(fx.Lifetime.NumberRange[2], 2)
		t.ok(fx.Transparency.NumberSequence.keypoints[1] ~= nil)
		t.eq(fx.Color.ColorSequence.keypoints[1].color[1], 1)
		model:Destroy()
		t.fails(function()
			K.toModelJson(Instance.new("Humanoid"))
		end, "native Rojo syncback")
	end)
	t.test("empty all-replace edits are rejected without looping", function()
		local module = Instance.new("ModuleScript")
		t.fails(function()
			K.edit(module, { { "", "replacement", true } :: { any } })
		end, "nonempty")
		module:Destroy()
	end)
	t.test("recordings retain only bounded rows and bounded row text", function()
		local name = "MoonbrickTest_" .. game:GetService("HttpService"):GenerateGUID(false)
		local count = 0
		K.record(name, function()
			count += 1
			return if count <= 8 then string.rep("x", 1000) else "stop"
		end, { maxRows = 3, timeout = 2 })
		local result = K.results(name, 3)
		t.ok(result:find("8 rows", 1, true))
		t.eq(#K._recs[name].rows, 3)
		t.eq(#K._recs[name].rows[1], 500)
		K._recs[name] = nil
	end)
end
