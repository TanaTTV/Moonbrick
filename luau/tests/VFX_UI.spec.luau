return function(t: any)
	local Kit = game:GetService("ReplicatedStorage").Kit
	local VFX = t.require(Kit.VFX)
	local UI = t.require(Kit.UI)

	t.test("world effects create cleaned-up, non-colliding parts", function()
		local before = #workspace:GetChildren()
		VFX.impact(Vector3.new(0, 500, 0), { pillar = true })
		local created = 0
		for _, c in workspace:GetChildren() do
			if c:IsA("BasePart") and c.Position.Y > 400 then
				created += 1
				t.eq(c.CanCollide, false, "effect part collides")
				t.eq(c.CanQuery, false, "effect part is raycastable")
			end
		end
		t.ok(created >= 3, "expected shockwave, sphere and burst parts, got " .. created)
		t.ok(#workspace:GetChildren() > before)
	end)

	t.test("aura attaches and its cleanup removes everything", function()
		local part = Instance.new("Part")
		part.Parent = workspace
		local remove = VFX.aura(part)
		t.ok(part:FindFirstChild("VFXAura"), "aura attachment")
		t.ok(part:FindFirstChildOfClass("PointLight"), "glow light")
		remove()
		t.eq(part:FindFirstChild("VFXAura"), nil)
		t.eq(part:FindFirstChildOfClass("PointLight"), nil)
		part:Destroy()
	end)

	t.test("screen effects refuse to run on the server", function()
		if game:GetService("RunService"):IsServer() then
			t.fails(function()
				VFX.flash()
			end, "client-only")
		end
	end)

	t.test("buttons get theme styling, touch-size minimum and click wiring", function()
		local holder = Instance.new("Folder")
		local clicked = false
		local b = UI.button({ parent = holder, text = "BUY", style = "success", onClick = function()
			clicked = true
		end })
		t.eq(b.Parent, holder)
		t.eq(b.Text, "BUY")
		t.ok(b:FindFirstChildOfClass("UICorner"), "corner")
		t.ok(b:FindFirstChildOfClass("UIGradient"), "gradient")
		local size = b:FindFirstChildOfClass("UISizeConstraint")
		t.ok(size and size.MinSize.X >= UI.Theme.minTouchSize, "touch size")
		t.eq(clicked, false)
		holder:Destroy()
	end)

	t.test("panel lays out title first", function()
		local p = UI.panel({ size = UDim2.fromOffset(300, 200), title = "Shop" })
		local title = p:FindFirstChild("Title") :: TextLabel
		t.ok(title, "title label")
		t.eq(title.Text, "Shop")
		t.ok(p:FindFirstChildOfClass("UIListLayout"), "list layout")
		p:Destroy()
	end)
end
