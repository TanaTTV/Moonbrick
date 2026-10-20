--!strict
-- Studio review helper (MCP execute_luau in the Client datamodel):
--   local C = require(game.Players.LocalPlayer.PlayerScripts.Client.Capture)
--   C.setup(CFrame.lookAt(Vector3.new(0, 6, 34), Vector3.new(0, 6, 0)))  -- hold a camera, hide your avatar
--   C.bounty(2)                                                         -- open the board on bounty 2
--   (take the screenshot) ; C.camera(otherCFrame) ; C.release()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BountyCard = require(script.Parent:WaitForChild("BountyCard"))

local Capture = {}

local view: CFrame = CFrame.identity

function Capture.camera(cf: CFrame)
	view = cf
end

function Capture.setup(cf: CFrame)
	assert(RunService:IsStudio(), "Capture is a Studio review tool")
	view = cf
	pcall(function()
		RunService:UnbindFromRenderStep("MoonbrickCapture")
	end)
	RunService:BindToRenderStep("MoonbrickCapture", Enum.RenderPriority.Camera.Value + 10, function()
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = view
		camera.FieldOfView = 60
	end)
	local character = Players.LocalPlayer.Character
	if character then
		-- Keep your own avatar out of review captures.
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 1
			end
		end
		character:PivotTo(CFrame.new(60, 4, 80))
	end
end

function Capture.bounty(i: number?)
	BountyCard.show(i or 1)
end

function Capture.release()
	BountyCard.close()
	pcall(function()
		RunService:UnbindFromRenderStep("MoonbrickCapture")
	end)
end

return Capture
