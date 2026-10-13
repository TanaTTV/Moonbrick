return function(t: any)
	local Net = t.require(game:GetService("ReplicatedStorage").Kit.Net)

	t.test("number rejects NaN, infinity and non-numbers", function()
		local v = Net.number()
		t.eq(v(0 / 0), false, "NaN")
		t.eq(v(math.huge), false, "inf")
		t.eq(v(-math.huge), false, "-inf")
		t.eq(v("5"), false, "string")
		t.eq(v(5), true)
	end)

	t.test("number and int enforce ranges", function()
		t.eq(Net.number(0, 10)(11), false)
		t.eq(Net.number(0, 10)(-1), false)
		t.eq(Net.int(1, 99)(1.5), false, "fraction")
		t.eq(Net.int(1, 99)(99), true)
	end)

	t.test("string enforces type and max length", function()
		t.eq(Net.string(3)("abcd"), false)
		t.eq(Net.string(3)("abc"), true)
		t.eq(Net.string()(nil), false)
	end)

	t.test("oneOf, optional, boolean, vector3", function()
		t.eq(Net.oneOf("sword", "bow")("bow"), true)
		t.eq(Net.oneOf("sword", "bow")("axe"), false)
		t.eq(Net.optional(Net.int())(nil), true)
		t.eq(Net.optional(Net.int())(1.5), false)
		t.eq(Net.boolean()(false), true)
		t.eq(Net.boolean()(0), false)
		t.eq(Net.vector3(10)(Vector3.new(0, 0 / 0, 0)), false, "NaN vector")
		t.eq(Net.vector3(10)(Vector3.new(100, 0, 0)), false, "too large")
	end)

	t.test("instance checks class and ancestry", function()
		local folder = Instance.new("Folder")
		local part = Instance.new("Part")
		part.Parent = folder
		t.eq(Net.instance("BasePart")(part), true)
		t.eq(Net.instance("Model")(part), false)
		t.eq(Net.instance("BasePart", workspace)(part), false, "not under workspace")
		folder:Destroy()
	end)

	t.test("check rejects extra arguments and reports the bad position", function()
		local validators = { Net.string(10), Net.int() }
		t.eq(Net.check(validators, { "a", 1 } :: { any }, 2), true)
		local ok, err = Net.check(validators, { "a", 1, "extra" } :: { any }, 3)
		t.eq(ok, false)
		t.ok(string.find(err, "too many", 1, true), err)
		local ok2, err2 = Net.check(validators, { "a", 0.5 } :: { any }, 2)
		t.eq(ok2, false)
		t.ok(string.find(err2, "argument 2", 1, true), err2)
	end)

	t.test("a broken custom validator rejects instead of throwing through a remote", function()
		local ok, err = Net.check({
			function()
				error("validator bug")
			end,
		}, { "input" }, 1)
		t.eq(ok, false)
		t.ok(err:find("validator failed", 1, true))
		t.eq(
			Net.check({
				function()
					return "truthy"
				end,
			}, { "input" }, 1),
			false
		)
	end)
end
