--!strict
-- Studio review helper for screenshot-driven iteration (MCP execute_luau in the Client datamodel):
--   local C = require(game.Players.LocalPlayer.PlayerScripts.Client.Capture)
--   C.setup(CFrame.lookAt(Vector3.new(0, 7, 15), Vector3.new(0, 4, 0)))  -- hold a camera, hide your avatar
--   C.hatchAt("Mythic", 2.9)                                           -- freeze the hatch at 2.9 s
--   (take the screenshot) ; C.camera(otherCFrame) ; C.release()
-- Freezing uses Fx.setGlobalTimeScale(0): effects, the creature and the egg stop; physics shell does not.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = ReplicatedStorage:WaitForChild("Kit")
local Fx = require(Kit:WaitForChild("Fx"))
local HatchPlayer = require(script.Parent:WaitForChild("HatchPlayer"))

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

-- Plays a hatch locally (no server roll, nothing saved) and freezes it `t` seconds in.
function Capture.hatchAt(rarity: string, t: number, onCard: (() -> ())?): string
	Fx.setGlobalTimeScale(1)
	if cancel then
		cancel()
	end
	task.wait(0.3)
	local pedestal = workspace:WaitForChild("World"):WaitForChild("Scene"):WaitForChild("Pedestal") :: BasePart
	local start = os.clock()
	cancel = HatchPlayer.play(rarity, pedestal, { camera = false, onCard = onCard }).cancel
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
