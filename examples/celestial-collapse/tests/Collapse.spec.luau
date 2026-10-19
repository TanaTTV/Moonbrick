return function(t: any)
	local Collapse = t.require(game:GetService("ReplicatedStorage").Shared.Collapse)
	local Fx = t.require(game:GetService("ReplicatedStorage").Kit.Fx)

	t.test("timeline phases are ordered and the blast follows the implosion", function()
		for name, style in Collapse.styles do
			local tl = Collapse.timeline(style)
			t.ok(tl.gather < tl.rise and tl.rise < tl.throw and tl.throw < tl.impact, name .. " phase order")
			t.ok(math.abs(tl.blast - tl.impact - style.timing.implode) < 1e-9, name .. " implode gap")
			t.ok(tl.finish > tl.blast, name .. " aftermath")
		end
	end)

	t.test("the orb arc starts and lands exactly and peaks halfway", function()
		local a, b = Vector3.new(0, 10, 0), Vector3.new(20, 0, 0)
		t.ok((Collapse.arc(a, b, 6, 0) - a).Magnitude < 1e-6)
		t.ok((Collapse.arc(a, b, 6, 1) - b).Magnitude < 1e-6)
		t.ok(math.abs(Collapse.arc(a, b, 6, 0.5).Y - 11) < 1e-6, "midpoint = average height + arc height")
	end)

	t.test("damage falls off with distance and never reaches past the radius", function()
		t.eq(Collapse.damageAt(0, 18), 80)
		t.ok(Collapse.damageAt(9, 18) < 80 and Collapse.damageAt(9, 18) > 25)
		t.eq(Collapse.damageAt(18.1, 18), 0)
		t.eq(Collapse.damageAt(0 / 0, 18), 0)
	end)

	t.test("both styles build valid effects, and the orb lasts exactly until impact", function()
		for name, style in Collapse.styles do
			local plan = Collapse.build(style)
			t.eq(Fx.length(plan.orb), plan.timeline.impact, name)
			t.ok(Fx.length(plan.impact) >= style.timing.implode + 1, name .. " impact length")
			for _, clip in plan.poses do
				t.eq(clip.rig, "R15", name .. " " .. clip.name)
			end
		end
	end)

	t.test("the variants differ in silhouette, texture, timing and material, not just colour", function()
		local a, b = Collapse.styles.Celestial, Collapse.styles.Abyssal
		t.ok(a.orb.form ~= b.orb.form, "orb silhouette")
		t.ok(a.blast.form ~= b.blast.form, "blast silhouette")
		t.ok(a.textures.mote ~= b.textures.mote and a.textures.spark ~= b.textures.spark, "textures")
		t.ok(a.orb.material ~= b.orb.material, "material")
		t.ok(math.abs(Collapse.timeline(a).impact - Collapse.timeline(b).impact) > 0.5, "timing")
		t.ok(a.motion.grow ~= b.motion.grow and a.motion.implode ~= b.motion.implode, "motion language")
	end)
end
