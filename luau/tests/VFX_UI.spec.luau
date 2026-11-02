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
		local b = UI.button({
			parent = holder,
			text = "BUY",
			style = "success",
			onClick = function()
				clicked = true
			end,
		})
		t.eq(b.Parent, holder)
		t.eq(b.Text, "BUY")
		t.ok(b:FindFirstChildOfClass("UICorner"), "corner")
		t.ok(b:FindFirstChildOfClass("UIGradient"), "gradient")
		local size = b:FindFirstChildOfClass("UISizeConstraint")
		t.ok(size and size.MinSize.X >= UI.Theme.minTouchSize, "touch size")
		t.eq(clicked, false)
		holder:Destroy()
	end)

	t.test("theme defaults keep the V1 look; fills and useTheme restyle without breaking buttons", function()
		t.eq(UI.Theme.font, Enum.Font.FredokaOne)
		t.eq(UI.Theme.buttonFill, "gradient")
		t.eq(UI.Theme.buttonStroke, Color3.new(1, 1, 1))
		t.eq(VFX.Style.titleFont, Enum.Font.FredokaOne)
		local saved = table.clone(UI.Theme)
		UI.useTheme({ buttonFill = "flat", displayFont = Enum.Font.Garamond })
		local flat = UI.button({ text = "A" })
		t.eq(flat:FindFirstChildOfClass("UIGradient"), nil, "flat buttons have no gradient")
		t.eq(flat.BackgroundColor3, UI.Theme.primary)
		local panel = UI.panel({ size = UDim2.fromOffset(100, 100), title = "T" })
		t.eq((panel:FindFirstChild("Title") :: TextLabel).Font, Enum.Font.Garamond)
		UI.useTheme({ buttonFill = "outline" })
		local outline = UI.button({ text = "B", style = "danger" })
		t.eq(outline.TextColor3, UI.Theme.danger)
		t.ok(outline:FindFirstChildOfClass("UISizeConstraint"), "touch minimum kept")
		t.fails(function()
			UI.useTheme({ notAThing = 1 })
		end, "unknown key")
		for key, value in saved do
			(UI.Theme :: any)[key] = value
		end
		UI.Theme.displayFont = nil
		flat:Destroy()
		outline:Destroy()
		panel:Destroy()
	end)

	t.test("panel lays out title first", function()
		local p = UI.panel({ size = UDim2.fromOffset(300, 200), title = "Shop" })
		local title = p:FindFirstChild("Title") :: TextLabel
		t.ok(title, "title label")
		t.eq(title.Text, "Shop")
		t.ok(p:FindFirstChildOfClass("UIListLayout"), "list layout")
		p:Destroy()
	end)

	t.test("show hide show cancels stale scale animations", function()
		local panel = Instance.new("Frame")
		UI.show(panel, true)
		UI.show(panel, false)
		UI.show(panel, true)
		task.wait(0.4)
		t.eq(panel.Visible, true)
		local scale = panel:FindFirstChildOfClass("UIScale")
		assert(scale, "UI.show did not create a UIScale")
		t.near(scale.Scale, 1, 0.001)
		panel:Destroy()
	end)
end
