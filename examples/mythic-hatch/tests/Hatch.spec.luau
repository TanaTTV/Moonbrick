return function(t: any)
	local Hatch = t.require(game:GetService("ReplicatedStorage").Shared.Hatch)
	local Fx = t.require(game:GetService("ReplicatedStorage").Kit.Fx)

	t.test("rolls follow the 70/25/5 weights and stay in range at the edges", function()
		t.eq(Hatch.roll(0), "Common")
		t.eq(Hatch.roll(0.6999), "Common")
		t.eq(Hatch.roll(0.70), "Rare")
		t.eq(Hatch.roll(0.9499), "Rare")
		t.eq(Hatch.roll(0.95), "Mythic")
		t.eq(Hatch.roll(1), "Mythic")
		t.eq(Hatch.roll(-3), "Common")
		local counts = { Common = 0, Rare = 0, Mythic = 0 }
		for i = 0, 9999 do
			counts[Hatch.roll(i / 10000)] += 1
		end
		t.eq(counts.Common, 7000)
		t.eq(counts.Rare, 2500)
		t.eq(counts.Mythic, 500)
	end)

	t.test("glow stays inside each rarity's range", function()
		for rarity, look in Hatch.looks do
			t.eq(Hatch.glowFor(rarity, 0), look.glow[1])
			t.eq(Hatch.glowFor(rarity, 1), look.glow[2])
			t.eq(Hatch.glowFor(rarity, 7), look.glow[2])
		end
	end)

	t.test("rarer eggs wobble longer, and the phases are ordered", function()
		local previous = 0
		for _, rarity in Hatch.order do
			local tl = Hatch.timeline(rarity)
			t.ok(tl.wobble < tl.burst and tl.burst < tl.reveal and tl.reveal < tl.card and tl.card < tl.done, rarity)
			t.ok(tl.burst > previous, rarity .. " bursts later than the rarity below")
			previous = tl.burst
		end
	end)

	t.test("every rarity builds valid burst and aura effects", function()
		for _, rarity in Hatch.order do
			t.ok(Fx.length(Hatch.burst(rarity)) > 0.5, rarity .. " burst")
			t.ok(Fx.length(Hatch.aura(rarity)) > 5, rarity .. " aura")
		end
	end)
end
