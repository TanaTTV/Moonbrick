--!strict
-- Pose: rig inspection, procedural keyframed poses with markers, and helpers for uploaded animations.
--
--   local rig = Pose.inspect(character)          -- { type = "R15" | "R6" | "Custom", joints = {...} }
--   local Throw = Pose.clip({ name = "Throw", rig = "R15", length = 0.9,
--       keys = { { t = 0, joints = {} },
--                { t = 0.35, ease = "quadOut", joints = { RightShoulder = CFrame.Angles(0, 0, math.rad(160)) } },
--                { t = 0.55, ease = "expoOut", joints = { RightShoulder = CFrame.Angles(0, 0, math.rad(-40)) } } },
--       markers = { { t = 0.5, name = "release" } } })
--   Pose.play(character, Throw):on("release", function() ... end)
--
-- Procedural poses write joint `Transform` before physics (PreSimulation), which works for both
-- Motor6D and AnimationConstraint joints. Transform is NOT replicated: play poses on every client that
-- should see them (broadcast with Net), never only on the server. Joint names are the rig's own:
-- R15 (`RightShoulder`, `Waist`, …) and R6 (`Right Shoulder`, `RootJoint`, …) are different rigs with
-- different joint axes, so a clip declares its rig and refuses the other one.
local Motion = require(script.Parent.Motion)
local Scheduler = require(script.Parent.Scheduler)

local Pose = {}

export type RigType = "R15" | "R6" | "Custom"
export type Joint = { instance: Instance, kind: "Motor6D" | "AnimationConstraint" }
export type Rig = { type: RigType, model: Model, joints: { [string]: Joint }, humanoid: Humanoid?, animator: Animator? }
export type Key = { t: number, joints: { [string]: CFrame }, ease: Motion.Ease? }
export type Clip = {
	name: string,
	rig: RigType | "Any",
	length: number,
	looped: boolean?,
	keys: { Key },
	markers: { { t: number, name: string } }?,
}
export type PlayOptions = { speed: number?, fadeIn: number?, fadeOut: number?, weight: number? }

Pose.R15 = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}
Pose.R6 = { "RootJoint", "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }

-- Rig type from a list of joint names (pure; tested).
function Pose.classify(names: { string }): RigType
	local set: { [string]: boolean } = {}
	for _, name in names do
		set[name] = true
	end
	if set.Waist and set.RightElbow and set.LeftKnee then
		return "R15"
	elseif set["Right Shoulder"] and set["Left Hip"] and set.RootJoint then
		return "R6"
	end
	return "Custom"
end

-- Finds a character's joints (Motor6D and AnimationConstraint) and classifies the rig.
function Pose.inspect(model: Model): Rig
	local joints: { [string]: Joint } = {}
	local names = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			joints[d.Name] = { instance = d, kind = "Motor6D" }
			table.insert(names, d.Name)
		elseif d:IsA("AnimationConstraint") then
			joints[d.Name] = { instance = d, kind = "AnimationConstraint" }
			table.insert(names, d.Name)
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	return { type = Pose.classify(names), model = model, joints = joints, humanoid = humanoid, animator = animator }
end

-- Validates and returns a clip (keys sorted by time, markers inside the clip).
function Pose.clip(clip: Clip): Clip
	assert(type(clip.name) == "string", "Pose.clip needs a name")
	assert(clip.length > 0, `Pose clip '{clip.name}' needs a positive length`)
	assert(#clip.keys > 0, `Pose clip '{clip.name}' needs keys`)
	table.sort(clip.keys, function(a, b)
		return a.t < b.t
	end)
	local markers: { { t: number, name: string } } = clip.markers or {}
	for _, marker in markers do
		assert(
			marker.t >= 0 and marker.t <= clip.length,
			`Pose clip '{clip.name}': marker '{marker.name}' is outside the clip`
		)
	end
	return clip
end

-- The joint offsets of a clip at time `t` (pure; tested). A joint missing from a key holds identity
-- there, so poses return to rest unless every key names the joint.
function Pose.sample(clip: Clip, t: number): { [string]: CFrame }
	local time = if clip.looped then t % clip.length else math.clamp(t, 0, clip.length)
	local names: { [string]: boolean } = {}
	for _, key in clip.keys do
		for name in key.joints do
			names[name] = true
		end
	end
	local result: { [string]: CFrame } = {}
	for name in names do
		local track: { Motion.Key<CFrame> } = {}
		for _, key in clip.keys do
			table.insert(track, { t = key.t, v = key.joints[name] or CFrame.identity, ease = key.ease })
		end
		result[name] = Motion.sample(track, time)
	end
	return result
end

export type Track = {
	clip: Clip,
	time: number,
	finished: boolean,
	on: (self: Track, marker: string, fn: () -> ()) -> Track,
	stop: (self: Track, fade: number?) -> (),
}

type Internal = Track & {
	_rig: Rig,
	_speed: number,
	_weight: number,
	_fadeIn: number,
	_fadeOut: number,
	_stopping: number?,
	_stopFade: number,
	_listeners: { [string]: { () -> () } },
	_fired: { [number]: boolean },
	_from: { [string]: CFrame },
	_stopJob: (() -> ())?,
	_cycle: number,
}

local TrackMethods = {}
TrackMethods.__index = TrackMethods

function TrackMethods.on(self: Internal, marker: string, fn: () -> ()): Track
	local list = self._listeners[marker] or {}
	self._listeners[marker] = list
	table.insert(list, fn)
	return self
end

function TrackMethods.stop(self: Internal, fade: number?)
	if self.finished or self._stopping then
		return
	end
	self._stopping = self.time
	self._stopFade = math.max(fade or self._fadeOut, 0)
end

local active: { [Model]: { Internal } } = {}

local function finish(track: Internal)
	if track.finished then
		return
	end
	track.finished = true
	local list = active[track._rig.model]
	if list then
		local index = table.find(list, track)
		if index then
			table.remove(list, index)
		end
		if #list == 0 then
			active[track._rig.model] = nil
			-- Leave joints at rest; an Animator (if any) takes over on the next frame.
			for _, joint in track._rig.joints do
				(joint.instance :: any).Transform = CFrame.identity
			end
		end
	end
end

local function advance(track: Internal, dt: number): { [string]: CFrame }?
	if track.finished then
		return nil
	end
	local rig = track._rig
	if not rig.model.Parent then
		finish(track)
		return nil
	end
	local previous = track.time
	track.time += dt * track._speed
	local clip = track.clip
	-- Markers between the previous and the current time (and across a loop wrap).
	local markers: { { t: number, name: string } } = clip.markers or {}
	for i, marker in markers do
		local cycleStart = track._cycle * clip.length
		local markerTime = cycleStart + marker.t
		if not track._fired[i] and previous <= markerTime and track.time >= markerTime then
			track._fired[i] = true
			local listeners: { () -> () } = track._listeners[marker.name] or {}
			for _, fn in listeners do
				task.spawn(fn)
			end
		end
	end
	if clip.looped and track.time >= (track._cycle + 1) * clip.length then
		track._cycle += 1
		table.clear(track._fired)
	end
	local weight = track._weight
	if track._fadeIn > 0 then
		weight *= math.clamp(track.time / track._fadeIn, 0, 1)
	end
	if track._stopping then
		local fade = track._stopFade
		local alpha = if fade <= 0 then 1 else math.clamp((track.time - track._stopping) / fade, 0, 1)
		weight *= 1 - alpha
		if alpha >= 1 then
			finish(track)
			return nil
		end
	elseif not clip.looped and track.time >= clip.length + track._fadeOut then
		finish(track)
		return nil
	elseif not clip.looped and track.time > clip.length and track._fadeOut > 0 then
		weight *= 1 - math.clamp((track.time - clip.length) / track._fadeOut, 0, 1)
	end
	local pose = Pose.sample(clip, track.time)
	local out: { [string]: CFrame } = {}
	for name, cf in pose do
		local from = track._from[name] or CFrame.identity
		out[name] = from:Lerp(cf, weight)
	end
	return out
end

local stepping = false
local function ensureStepping()
	if stepping then
		return
	end
	stepping = true
	Scheduler.every(function(dt)
		for model, tracks in active do
			-- Later tracks win per joint (layering order = play order).
			local combined: { [string]: CFrame } = {}
			for _, track in table.clone(tracks) do
				local pose = advance(track, dt)
				if pose then
					for name, cf in pose do
						combined[name] = cf
					end
				end
			end
			local rig = if #tracks > 0 then tracks[1]._rig else nil
			if rig then
				for name, cf in combined do
					local joint = rig.joints[name]
					if joint then
						(joint.instance :: any).Transform = cf
					end
				end
			end
			if not model.Parent then
				active[model] = nil
			end
		end
		if next(active) == nil then
			stepping = false
			return true
		end
		return false
	end, "PreSimulation")
end

-- Plays a clip on a character. Joints the clip doesn't name keep their Animator pose.
function Pose.play(model: Model, clip: Clip, opts: PlayOptions?): Track
	local o: PlayOptions = opts or {}
	local rig = Pose.inspect(model)
	if clip.rig ~= "Any" and clip.rig ~= rig.type then
		error(`Pose '{clip.name}' is for {clip.rig} rigs, but {model.Name} is {rig.type}`)
	end
	for _, key in clip.keys do
		for name in key.joints do
			if not rig.joints[name] then
				warn(`Pose '{clip.name}': {model.Name} has no joint '{name}'`)
			end
		end
	end
	local track: Internal = setmetatable({
		clip = clip,
		time = 0,
		finished = false,
		_rig = rig,
		_speed = o.speed or 1,
		_weight = math.clamp(o.weight or 1, 0, 1),
		_fadeIn = o.fadeIn or 0.08,
		_fadeOut = o.fadeOut or 0.15,
		_stopFade = 0,
		_listeners = {},
		_fired = {},
		_from = {},
		_cycle = 0,
	}, TrackMethods) :: any
	-- `_from` stays empty: fades start from rest (identity), not from the Animator pose, which changes
	-- every frame.
	local list = active[model] or {}
	active[model] = list
	table.insert(list, track)
	ensureStepping()
	return track
end

-- Stops every procedural pose on a model.
function Pose.stopAll(model: Model, fade: number?)
	local tracks: { Internal } = table.clone(active[model] or {})
	for _, track in tracks do
		track:stop(fade)
	end
end

-- Number of models with active procedural poses (for leak tests).
function Pose.activeCount(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

-- Loads an uploaded animation on a character's Animator. Animations must be owned by the experience
-- owner (or Roblox) to play in a published game.
function Pose.track(
	model: Model,
	animation: string | Animation,
	opts: { priority: Enum.AnimationPriority?, looped: boolean? }?
): AnimationTrack
	local rig = Pose.inspect(model)
	local animator = rig.animator
	if not animator then
		local humanoid = rig.humanoid
		assert(humanoid, `Pose.track: {model.Name} has no Humanoid or Animator`)
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local source: Animation
	if typeof(animation) == "string" then
		local a = Instance.new("Animation")
		a.AnimationId = animation
		source = a
	else
		source = animation
	end
	local track = (animator :: Animator):LoadAnimation(source)
	local o: { priority: Enum.AnimationPriority?, looped: boolean? } = opts or {}
	track.Priority = o.priority or Enum.AnimationPriority.Action
	if o.looped ~= nil then
		track.Looped = o.looped
	end
	return track
end

-- Connects to a named marker (KeyframeMarker) of an uploaded animation.
function Pose.marker(track: AnimationTrack, name: string, fn: (string) -> ()): RBXScriptConnection
	return track:GetMarkerReachedSignal(name):Connect(fn)
end

return Pose
