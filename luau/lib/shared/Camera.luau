--!strict
-- Camera: scripted camera rigs for the local player. One rig runs at a time; a new one replaces it.
-- Client-only. Rig maths are pure functions, so framing is unit tested.
--
--   Camera.follow(nil, { distance = 16, height = 6 })           -- default target: the local character
--   Camera.topDown(nil, { height = 60, tilt = 20 })
--   Camera.shoulder()                                           -- mouse, thumbstick or touch drag to aim
--   local stop = Camera.path({
--       { t = 0, at = CFrame.lookAt(a, focus), fov = 50 },
--       { t = 3, at = CFrame.lookAt(b, focus), fov = 40, ease = "sineInOut" },
--   }, { onDone = function() print("cut") end })
--   Camera.stop()                                               -- back to the default Roblox camera
--
-- Rigs render at Camera + 1, so `K.cam` (Camera + 10) still wins during captures. Paths run on the
-- Scheduler: `Fx.setGlobalTimeScale` slows or freezes a cutscene with the effects in it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Motion = require(script.Parent.Motion)
local Scheduler = require(script.Parent.Scheduler)
local VFX = require(script.Parent.VFX)

local Camera = {}

-- What a rig watches: a part, a model, a function, or nil for the local character.
export type Target = BasePart | Model | (() -> Vector3)
export type FollowOptions = {
	distance: number?, -- studs behind, default 16
	height: number?, -- studs above the target, default 5
	yaw: number?, -- degrees, default 0
	pitch: number?, -- degrees below level, default 15
	stiffness: number?, -- spring speed, default 8
	collide: boolean?, -- pull in rather than clip through walls, default on
	fov: number?,
}
export type TopDownOptions = {
	height: number?, -- studs above, default 50
	tilt: number?, -- degrees off straight down, default 15
	yaw: number?,
	stiffness: number?,
	fov: number?,
}
export type ShoulderOptions = {
	offset: Vector3?, -- right, up, back in studs, default (2, 2, 8)
	sensitivity: number?, -- degrees per pixel, default 0.25
	pitchLimit: number?, -- degrees, default 70
	collide: boolean?,
	fov: number?,
}
export type PathKey = { t: number, at: CFrame, fov: number?, ease: Motion.Ease? }
export type PathOptions = { onDone: (() -> ())?, hold: boolean? } -- hold: stay on the last frame

local BIND = "MoonbrickCameraRig"
local BIND_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local CLIP_MARGIN = 0.6

type Rig = { step: (number) -> (CFrame, number?), stop: (() -> ())? }

-- Camera behind and above `focus` (pure). Yaw turns around the world up axis.
function Camera.followFrame(focus: Vector3, yaw: number, pitch: number, distance: number): CFrame
	return CFrame.new(focus)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(math.rad(-pitch), 0, 0)
		* CFrame.new(0, 0, distance)
end

-- Camera above `focus`, leaning `tilt` degrees off vertical (pure).
function Camera.topDownFrame(focus: Vector3, height: number, tilt: number, yaw: number?): CFrame
	return Camera.followFrame(focus, yaw or 0, 90 - tilt, height)
end

-- Over-the-shoulder view: `offset` is right, up, back from `focus` along the aim (pure).
function Camera.shoulderFrame(focus: Vector3, yaw: number, pitch: number, offset: Vector3): CFrame
	return CFrame.new(focus)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(math.rad(-pitch), 0, 0)
		* CFrame.new(offset)
end

-- Where a camera may sit on the line from `focus` to `wanted` when a wall is `hitDistance` along it (pure).
function Camera.clip(focus: Vector3, wanted: Vector3, hitDistance: number?): Vector3
	if not hitDistance then
		return wanted
	end
	local line = wanted - focus
	if line.Magnitude <= CLIP_MARGIN then
		return wanted
	end
	return focus + line.Unit * math.max(math.min(hitDistance - CLIP_MARGIN, line.Magnitude), CLIP_MARGIN)
end

-- The frame and field of view of a keyframed path at time `t` (pure). Keys without `fov` keep the last one.
function Camera.pathFrame(keys: { PathKey }, t: number): (CFrame, number?)
	local frames: { Motion.Key<CFrame> } = {}
	local fovs: { Motion.Key<number> } = {}
	for _, key in keys do
		table.insert(frames, { t = key.t, v = key.at, ease = key.ease })
		if key.fov then
			table.insert(fovs, { t = key.t, v = key.fov, ease = key.ease })
		end
	end
	return Motion.sample(frames, t), if #fovs > 0 then Motion.sample(fovs, t) else nil
end

-- Validates and returns a path: at least one key, times in order, CFrames in `at` (pure).
function Camera.checkPath(keys: { PathKey }): { PathKey }
	assert(#keys > 0, "Camera.path needs at least one key")
	local previous = -math.huge
	for i, key in keys do
		assert(
			type(key.t) == "number" and key.t >= previous,
			`Camera.path: key {i} needs a time after the previous key`
		)
		assert(typeof(key.at) == "CFrame", `Camera.path: key {i} needs a CFrame in 'at'`)
		previous = key.t
	end
	return keys
end

local function focusOf(target: Target?): Vector3?
	if type(target) == "function" then
		return target()
	elseif typeof(target) == "Instance" then
		if target:IsA("Model") then
			return target:GetPivot().Position
		end
		return (target :: BasePart).Position
	end
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function unobstructed(focus: Vector3, wanted: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local hit = workspace:Raycast(focus, wanted - focus, params)
	return Camera.clip(focus, wanted, if hit then hit.Distance else nil)
end

-- Three springs smoothing a focus point.
local function smoother(start: Vector3, speed: number): (Vector3, number) -> Vector3
	local function spring(value: number): Motion.Spring
		return { value = value, velocity = 0, target = value, speed = speed, damping = 1 }
	end
	local x, y, z = spring(start.X), spring(start.Y), spring(start.Z)
	return function(target, dt)
		x.target, y.target, z.target = target.X, target.Y, target.Z
		Motion.springStep(x, dt)
		Motion.springStep(y, dt)
		Motion.springStep(z, dt)
		return Vector3.new(x.value, y.value, z.value)
	end
end

local current: Rig? = nil
local previousType: Enum.CameraType? = nil
local previousFov: number? = nil

local function unbind()
	RunService:UnbindFromRenderStep(BIND)
	local rig = current
	current = nil
	if rig and rig.stop then
		rig.stop()
	end
end

local function start(rig: Rig)
	assert(RunService:IsClient(), "Camera rigs are client-only")
	local camera = workspace.CurrentCamera
	if not current then
		previousType, previousFov = camera.CameraType, camera.FieldOfView
	end
	unbind()
	current = rig
	RunService:BindToRenderStep(BIND, BIND_PRIORITY, function(dt)
		local active = workspace.CurrentCamera
		if not active or current ~= rig then
			return
		end
		local frame, fov = rig.step(dt)
		active.CameraType = Enum.CameraType.Scriptable
		active.CFrame = frame * VFX.shakeOffset() -- VFX.shake leaves Scriptable cameras to their owner
		if fov then
			active.FieldOfView = fov
		end
	end)
end

-- Ends the running rig and hands the camera back to Roblox.
function Camera.stop()
	if not current then
		return
	end
	unbind()
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = previousType or Enum.CameraType.Custom
		if previousFov then
			camera.FieldOfView = previousFov
		end
	end
end

-- Whether a rig is running.
function Camera.active(): boolean
	return current ~= nil
end

-- Third-person chase camera. Waits on the last good focus while the target is missing (respawns).
function Camera.follow(target: Target?, opts: FollowOptions?)
	local o: FollowOptions = opts or {}
	local height = Vector3.new(0, o.height or 5, 0)
	local smooth: ((Vector3, number) -> Vector3)? = nil
	local last = workspace.CurrentCamera.CFrame
	start({
		step = function(dt)
			local focus = focusOf(target)
			if not focus then
				return last, o.fov
			end
			local wanted = focus + height
			smooth = smooth or smoother(wanted, o.stiffness or 8)
			local eased = (smooth :: (Vector3, number) -> Vector3)(wanted, dt)
			local frame = Camera.followFrame(eased, o.yaw or 0, o.pitch or 15, o.distance or 16)
			if o.collide ~= false then
				frame = frame.Rotation + unobstructed(eased, frame.Position)
			end
			last = frame
			return frame, o.fov
		end,
	})
end

-- Fixed-angle view from above, for strategy and arcade games.
function Camera.topDown(target: Target?, opts: TopDownOptions?)
	local o: TopDownOptions = opts or {}
	local smooth: ((Vector3, number) -> Vector3)? = nil
	local last = workspace.CurrentCamera.CFrame
	start({
		step = function(dt)
			local focus = focusOf(target)
			if not focus then
				return last, o.fov
			end
			smooth = smooth or smoother(focus, o.stiffness or 8)
			local eased = (smooth :: (Vector3, number) -> Vector3)(focus, dt)
			last = Camera.topDownFrame(eased, o.height or 50, o.tilt or 15, o.yaw)
			return last, o.fov
		end,
	})
end

-- Over-the-shoulder aim for the local character: locks the mouse, and turns the character with the view.
function Camera.shoulder(opts: ShoulderOptions?)
	local o: ShoulderOptions = opts or {}
	local sensitivity = o.sensitivity or 0.25
	local limit = o.pitchLimit or 70
	local offset = o.offset or Vector3.new(2, 2, 8)
	local yaw, pitch = 0, 0
	local aimed: RBXScriptConnection = UserInputService.InputChanged:Connect(
		function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
				yaw -= input.Delta.X * sensitivity
				pitch = math.clamp(pitch + input.Delta.Y * sensitivity, -limit, limit)
			end
		end
	)
	local stick = Vector2.zero
	local turned: RBXScriptConnection = UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local autoRotate = humanoid and humanoid.AutoRotate
	if humanoid then
		humanoid.AutoRotate = false
	end
	local behavior = UserInputService.MouseBehavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	local last = workspace.CurrentCamera.CFrame
	start({
		step = function(dt)
			if stick.Magnitude > 0.15 then
				yaw -= stick.X * 180 * dt
				pitch = math.clamp(pitch - stick.Y * 120 * dt, -limit, limit)
			end
			local focus = focusOf(nil)
			if not focus then
				return last, o.fov
			end
			local frame = Camera.shoulderFrame(focus, yaw, pitch, offset)
			if o.collide ~= false then
				frame = frame.Rotation + unobstructed(focus, frame.Position)
			end
			local root = Players.LocalPlayer.Character
				and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(yaw), 0)
			end
			last = frame
			return frame, o.fov
		end,
		stop = function()
			aimed:Disconnect()
			turned:Disconnect()
			UserInputService.MouseBehavior = behavior
			if humanoid and autoRotate ~= nil then
				humanoid.AutoRotate = autoRotate
			end
		end,
	})
end

-- Plays a keyframed camera move on Motion curves. Returns a function that ends it early. Ends by handing
-- the camera back, or stays on the last frame with `hold` until `Camera.stop`.
function Camera.path(keys: { PathKey }, opts: PathOptions?): () -> ()
	Camera.checkPath(keys)
	local o: PathOptions = opts or {}
	local length = keys[#keys].t
	local elapsed = 0
	local finished = false
	local stopJob: (() -> ())? = nil
	local rig: Rig
	rig = {
		step = function()
			return Camera.pathFrame(keys, elapsed)
		end,
		stop = function()
			finished = true
			if stopJob then
				stopJob()
			end
		end,
	}
	start(rig)
	stopJob = Scheduler.every(function(dt)
		if finished then
			return true
		end
		elapsed += dt
		if elapsed < length then
			return false
		end
		finished = true
		if o.onDone then
			task.spawn(o.onDone)
		end
		if not o.hold and current == rig then
			Camera.stop()
		end
		return true
	end)
	return function()
		if current == rig then
			Camera.stop()
		end
	end
end

return Camera
