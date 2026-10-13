-- Studio-only test hooks: features register actions that MCP can call with K.hook(feature, action, ...).
-- Nothing is created outside Studio, so published games are unaffected.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DebugHooks = {}

function DebugHooks.register(feature: string, actions: { [string]: (...any) -> ...any })
	if not RunService:IsStudio() then
		return
	end
	local folder = ServerStorage:FindFirstChild("DebugHooks")
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "DebugHooks"
		created.Archivable = false
		created.Parent = ServerStorage
		folder = created
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = feature
	fn.OnInvoke = function(action: string, ...)
		local handler = actions[action]
		if not handler then
			local names = {}
			for name in actions do
				table.insert(names, name)
			end
			error(`unknown action '{action}' for {feature}; available: {table.concat(names, ", ")}`)
		end
		return handler(...)
	end
	fn.Parent = folder
end

return DebugHooks
