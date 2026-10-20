-- Procedural meshes need EditableMesh, so this suite runs in Studio only (K.test), not headless.
return function(t: any)
	local Geo = t.require(game:GetService("ReplicatedStorage").Kit.Geo)

	local function built(fn: (any) -> ()): any
		local b = Geo.new()
		fn(b)
		return b
	end

	t.test("every closed primitive faces outward (positive signed volume)", function()
		local shapes: { [string]: (any) -> () } = {
			lathe = function(b)
				b:lathe({ Vector2.new(0.001, 0), Vector2.new(1, 0.2), Vector2.new(0.5, 1), Vector2.new(0.001, 1.2) }, 16)
			end,
			sphere = function(b)
				b:sphere(1, 8, 12)
			end,
			torus = function(b)
				b:torus(1, 0.25, 16, 8)
			end,
			tube = function(b)
				b:tube({ Vector3.zero, Vector3.new(0, 1, 0.3), Vector3.new(0, 2, 0) }, 0.3, 8)
			end,
			box = function(b)
				b:box(CFrame.identity, Vector3.new(1, 2, 3))
			end,
			extrude = function(b)
				b:extrude({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(1, 1), Vector2.new(0, 1) }, 1)
			end,
			extrudeReversed = function(b)
				b:extrude({ Vector2.new(0, 1), Vector2.new(1, 1), Vector2.new(1, 0), Vector2.new(0, 0) }, 1)
			end,
		}
		for name, fn in shapes do
			local b = built(fn)
			local v = b:volume()
			b.mesh:Destroy()
			t.ok(v > 0, `{name} is inside-out (signed volume {v})`)
		end
	end)

	t.test("box and extrude volumes are exact", function()
		local b = built(function(builder)
			builder:box(CFrame.new(5, 0, 0), Vector3.new(1, 2, 3))
		end)
		local v = b:volume()
		b.mesh:Destroy()
		t.ok(math.abs(v - 6) < 1e-3, `box volume {v}`)
		local e = built(function(builder)
			builder:extrude({ Vector2.new(0, 0), Vector2.new(2, 0), Vector2.new(2, 1), Vector2.new(0, 1) }, 3)
		end)
		local ev = e:volume()
		e.mesh:Destroy()
		t.ok(math.abs(ev - 6) < 1e-3, `extrude volume {ev}`)
	end)
end
