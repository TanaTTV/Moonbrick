-- Studio only: expose MCPKit to the Client datamodel so MCP tests can require it there too.
local RunService = game:GetService("RunService")

if RunService:IsStudio() then
	local kit = game:GetService("ServerStorage"):FindFirstChild("MCPKit")
	if kit then
		kit:Clone().Parent = game:GetService("ReplicatedStorage")
	end
end
