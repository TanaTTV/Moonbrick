return function(t: any)
	local Frontier = t.require(game:GetService("ReplicatedStorage").Shared.Frontier)

	t.test("steady signs never flicker; failing ones drop out sometimes and stay in range", function()
		for i = 0, 200 do
			t.eq(Frontier.flicker(i / 37, 0, 3), 1)
		end
		local drops = 0
		for i = 0, 899 do
			local k = Frontier.flicker(i / 90, 0.9, 5)
			t.ok(k >= 0 and k <= 1, `brightness {k}`)
			if k < 0.2 then
				drops += 1
			end
		end
		t.ok(drops > 20 and drops < 600, `dropouts {drops}`)
		t.eq(Frontier.flicker(1.234, 0.5, 7), Frontier.flicker(1.234, 0.5, 7))
	end)

	t.test("money formats with thousands separators", function()
		t.eq(Frontier.money(0), "$0")
		t.eq(Frontier.money(999), "$999")
		t.eq(Frontier.money(4800), "$4,800")
		t.eq(Frontier.money(1234567), "$1,234,567")
		t.eq(Frontier.money(-2500), "-$2,500")
	end)

	t.test("every bounty has a name, a crime, a positive reward and 1-5 threat", function()
		for _, b in Frontier.bounties do
			t.ok(#b.name > 0 and #b.crime > 0 and b.reward > 0 and b.threat >= 1 and b.threat <= 5, b.name)
		end
	end)
end
