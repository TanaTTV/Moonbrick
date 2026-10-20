--!strict
-- Studio review helper for screenshot-driven iteration (MCP execute_luau in the Client datamodel):
--   local C = require(game.Players.LocalPlayer.PlayerScripts.Client.Capture)
--   C.setup(CFrame.lookAt(Vector3.new(20, 9, 16), Vector3.new(0, 6, 2)))  -- hold a camera, hide your avatar
--   C.castAt("Celestial", 2.36)                                         -- freeze the cast at 2.36 s
--   (take the screenshot) ; C.camera(otherCFrame) ; C.release()
-- Freezing uses Fx.setGlobalTimeScale(0): effects, poses and tweens stop exactly; physics debris does not.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = ReplicatedStorage:WaitForChild("Kit")
local Fx = require(Kit:WaitForChild("Fx"))
local CollapsePlayer = require(script.Parent:WaitForChild("CollapsePlayer"))

local Capture = {}

local view: CFrame = CFrame.identity
local cancel: (() -> ())? = nil

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
		camera.FieldOfView = 55
	end)
	local character = Players.LocalPlayer.Character
	if character then
		-- Keep your own avatar out of review captures.
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 1
			end
		end
		character:PivotTo(CFrame.new(40, 4, 60))
	end
end

-- Plays a cast by the Astromancer and freezes everything `t` seconds in.
function Capture.castAt(style: string, t: number, target: Vector3?): string
	Fx.setGlobalTimeScale(1)
	if cancel then
		cancel()
	end
	for _, child in workspace:GetChildren() do
		if child.Name:match("^Fx_") or child.Name == "OrbCarrier" then
			child:Destroy()
		end
	end
	task.wait(0.3)
	local caster = workspace:WaitForChild("Stage"):WaitForChild("Astromancer") :: Model
	local start = os.clock()
	cancel = CollapsePlayer.play(style, caster, target or Vector3.new(0, 1.05, -12))
	while os.clock() - start < t do
		RunService.Heartbeat:Wait()
	end
	Fx.setGlobalTimeScale(0)
	return string.format("frozen at %.2f s", os.clock() - start)
end

function Capture.release()
	Fx.setGlobalTimeScale(1)
	if cancel then
		cancel()
		cancel = nil
	end
	pcall(function()
		RunService:UnbindFromRenderStep("MoonbrickCapture")
	end)
end

return Capture
