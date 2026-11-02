-- Procedural meshes need EditableMesh, so this suite runs in Studio only (K.test), not headless.
return function(t: any)
	local Geo = t.require(game:GetService("ReplicatedStorage").Kit.Geo)

	local function built(fn: (any) -> ()): any
		local b = Geo.new()
		fn(b)
		return b
	end

	t.test("Scatter.ground lands on the ground, not on spots already placed", function()
		local Scatter = t.require(game:GetService("ReplicatedStorage").Kit.Scatter)
		local floor = Instance.new("Part")
		floor.Anchored, floor.Size, floor.Position = true, Vector3.new(20, 1, 20), Vector3.new(4000, 100, 4000)
		floor.Parent = workspace
		local spot = Instance.new("Part")
		spot.Anchored, spot.Size, spot.Position = true, Vector3.new(6, 6, 6), Vector3.new(4000, 110, 4000)
		spot:SetAttribute("GeoShape", "rock")
		spot.Parent = workspace
		local hit = Scatter.ground({ top = 200 })(4000, 4000)
		floor:Destroy()
		spot:Destroy()
		t.ok(hit, "found the ground")
		t.ok(math.abs(hit.position.Y - 100.5) < 0.01, "landed on the spot")
	end)

	t.test("every built-in shape builds and faces outward on real meshes", function()
		local GeoShapes = t.require(game:GetService("ReplicatedStorage").Kit.GeoShapes)
		for name, build in GeoShapes.Builders do
			local b = built(function(builder)
				build(builder, { Seed = 2 })
			end)
			t.ok(b:volume() > 0, name .. " is inside-out")
			t.ok(b:count() < 1500, name .. " is too heavy")
			b.mesh:Destroy()
		end
	end)

	t.test("every closed primitive faces outward (positive signed volume)", function()
		local shapes: { [string]: (any) -> () } = {
			lathe = function(b)
				b:lathe(
					{ Vector2.new(0.001, 0), Vector2.new(1, 0.2), Vector2.new(0.5, 1), Vector2.new(0.001, 1.2) },
					16
				)
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
