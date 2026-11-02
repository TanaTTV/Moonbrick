-- MCPKit logic that needs no Studio: path resolution, audit rules and capture stops. Runs headless too.
return function(t: any)
	local K = t.require(game:GetService("ServerStorage").MCPKit)

	t.test("K.get resolves everything K.path prints, dotted names included", function()
		if t.isolated then
			return -- the isolated Studio bundle keeps its tree out of the DataModel, so paths can't resolve
		end
		local folder = Instance.new("Folder")
		folder.Name = "KGetProbe"
		local spec = Instance.new("Folder")
		spec.Name = "Creative.spec"
		spec.Parent = folder
		local inner = Instance.new("Folder")
		inner.Name = "Inner"
		inner.Parent = spec
		folder.Parent = workspace
		t.eq(K.get(K.path(spec)), spec)
		t.eq(K.get("game." .. K.path(inner)), inner)
		t.eq(K.get(folder), folder)
		t.fails(function()
			K.get("Workspace.KGetProbe.Nope.spec")
		end, "not found")
		folder:Destroy()
	end)

	t.test("the audit flags Humanoid:LoadAnimation, not Animator:LoadAnimation", function()
		t.eq(#K.lintLine("local track = humanoid:LoadAnimation(anim)"), 1)
		t.eq(#K.lintLine("local track = animator:LoadAnimation(anim)"), 0)
		t.eq(#K.lintLine("local track = (animator :: Animator):LoadAnimation(source)"), 0)
		t.eq(#K.lintLine("wait(1)"), 1)
		t.eq(#K.lintLine("task.wait(1)"), 0)
	end)
end
