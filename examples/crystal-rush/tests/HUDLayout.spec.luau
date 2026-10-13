--!strict
return function(t: any)
	local Layout = t.require(game:GetService("ReplicatedStorage").Shared.HUDLayout)
	local function check(width: number, height: number, left: number, top: number, right: number, bottom: number)
		for _, notice in { false, true } do
			local layout = Layout.layoutFor({ width = width, height = height }, {
				left = left,
				top = top,
				right = right,
				bottom = bottom,
			}, notice)
			local halfWidth = layout.width * layout.scale / 2
			t.ok(layout.x - halfWidth >= left + 12, "left safe margin")
			t.ok(layout.x + halfWidth <= width - right - 12, "right safe margin")
			t.eq(layout.y, top + 12, "below top bar")
			local controls = if height < 420 then 120 else 160
			t.ok(layout.y + layout.height * layout.scale <= height - bottom - controls - 12, "above controls")
			t.ok(layout.scale > 0 and layout.scale <= 1.25, "bounded scale")
			t.ok(22 * layout.scale >= 16, "readable status text on target devices")
		end
	end
	t.test("320x568 portrait keeps HUD and notice inside safe margins", function()
		check(320, 568, 0, 36, 0, 0)
	end)
	t.test("568x320 landscape leaves bottom controls clear", function()
		check(568, 320, 0, 36, 0, 21)
	end)
	t.test("notched phone uses device-safe dimensions plus remaining CoreGui inset", function()
		check(724, 354, 0, 36, 0, 0)
		check(390, 763, 0, 12, 0, 0)
	end)
	t.test("tablet portrait and landscape fit without excessive enlargement", function()
		check(768, 1024, 0, 36, 0, 0)
		check(1024, 768, 0, 36, 0, 0)
	end)
	t.test("1080p console and desktop respect asymmetric safe margins", function()
		check(1920, 1080, 80, 72, 60, 40)
		local layout = Layout.layoutFor({ width = 1920, height = 1080 }, {
			left = 80,
			top = 72,
			right = 60,
			bottom = 40,
		})
		t.eq(layout.scale, 1.25)
		t.eq(layout.x, 970)
	end)
	t.test("small viewport transitions never produce negative scale", function()
		local layout = Layout.layoutFor({ width = 0, height = 0 }, { left = 0, top = 0, right = 0, bottom = 0 })
		t.eq(layout.scale, 0)
	end)
end
