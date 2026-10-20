--!strict
-- Audio: sound groups, a project cue map and positional playback on Roblox's Sound API.
-- Called on a client, only that player hears it; on the server, everyone does.
--
--   Audio.define({ Boom = { id = Audio.Builtin.explosion, volume = 0.9, pitch = { 0.92, 1.05 }, group = "SFX" } })
--   Audio.play("Boom", impactPosition)                   -- 3D at a position (or a part/attachment)
--   Audio.play("Click")                                  -- 2D (UI)
--   local amb = Audio.loop("Wind", nil, { fade = 2 }) ; amb.stop(1.5)
--
-- Use your own uploads, Roblox's built-in sounds (`Audio.Builtin`) or Creator Store audio you are
-- allowed to use. Nothing here uploads or publishes audio.
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Audio = {}

export type Group = "Master" | "Music" | "SFX" | "UI" | "Ambience"
export type Cue = {
	id: string, -- rbxassetid://… or rbxasset://sounds/…
	volume: number?,
	pitch: (number | { number })?, -- fixed, or { min, max } for variation
	group: Group?,
	rolloff: { number }?, -- { min, max } distance in studs for 3D sounds
	looped: boolean?,
	start: number?, -- TimePosition to start from
}
export type Where = Vector3 | BasePart | Attachment
export type PlayOptions = { volume: number?, pitch: number?, delay: number? }
export type Loop = { sound: Sound, stop: (fade: number?) -> () }

-- Sounds that ship with every Roblox client: usable without uploads.
Audio.Builtin = {
	explosion = "rbxasset://sounds/impact_explosion_03.mp3",
	water = "rbxasset://sounds/impact_water.mp3",
	jump = "rbxasset://sounds/action_jump.mp3",
	land = "rbxasset://sounds/action_jump_land.mp3",
	footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
	getUp = "rbxasset://sounds/action_get_up.mp3",
	falling = "rbxasset://sounds/action_falling.ogg",
	swim = "rbxasset://sounds/action_swim.mp3",
	tick = "rbxasset://sounds/volume_slider.ogg",
}

local cues: { [string]: Cue } = {}
local groups: { [string]: SoundGroup } = {}
local DEFAULT_VOLUME: { [string]: number } = { Master = 1, Music = 0.5, SFX = 0.8, UI = 0.6, Ambience = 0.45 }

-- The SoundGroup for `name` under SoundService (created once; all groups route into Master).
function Audio.group(name: Group): SoundGroup
	local existing = groups[name]
	if existing and existing.Parent then
		return existing
	end
	local found = SoundService:FindFirstChild("Moonbrick" .. name)
	local group: SoundGroup
	if found and found:IsA("SoundGroup") then
		group = found
	else
		group = Instance.new("SoundGroup")
		group.Name = "Moonbrick" .. name
		group.Volume = DEFAULT_VOLUME[name] or 1
		if name ~= "Master" then
			group.Parent = Audio.group("Master")
		else
			group.Parent = SoundService
		end
	end
	groups[name] = group
	return group
end

function Audio.setVolume(name: Group, volume: number)
	Audio.group(name).Volume = math.clamp(volume, 0, 10)
end

-- Adds or replaces cues by name.
function Audio.define(map: { [string]: Cue })
	for name, cue in map do
		assert(type(cue.id) == "string" and cue.id ~= "", `Audio cue '{name}' needs an id`)
		cues[name] = cue
	end
end

function Audio.cue(name: string): Cue?
	return cues[name]
end

-- Picks a pitch from a cue's fixed value or { min, max } range; `rand` (0..1) is injectable for tests.
function Audio.pitchFor(cue: Cue, rand: number?): number
	local p = cue.pitch
	if type(p) == "table" then
		local r = rand or math.random()
		return p[1] + (p[2] - p[1]) * r
	end
	return if type(p) == "number" then p else 1
end

local anchorFolder: Folder? = nil
local function anchorAt(position: Vector3): Attachment
	if not anchorFolder or not anchorFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "MoonbrickAudio"
		folder.Parent = workspace
		anchorFolder = folder
	end
	local part = Instance.new("Part")
	part.Name = "AudioAnchor"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = position
	part.Parent = anchorFolder
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	return attachment
end

local function build(nameOrId: string, where: Where?, opts: PlayOptions?): (Sound, Instance?)
	local o: PlayOptions = opts or {}
	local cue: Cue = cues[nameOrId] or { id = nameOrId }
	local sound = Instance.new("Sound")
	sound.Name = if cues[nameOrId] then nameOrId else "Sound"
	sound.SoundId = cue.id
	sound.Volume = (cue.volume or 0.8) * (o.volume or 1)
	sound.PlaybackSpeed = o.pitch or Audio.pitchFor(cue)
	sound.Looped = cue.looped == true
	sound.TimePosition = cue.start or 0
	sound.SoundGroup = Audio.group(cue.group or (if where then "SFX" else "UI"))
	if cue.rolloff then
		sound.RollOffMinDistance = cue.rolloff[1]
		sound.RollOffMaxDistance = cue.rolloff[2]
	end
	local holder: Instance? = nil
	if typeof(where) == "Vector3" then
		local attachment = anchorAt(where)
		holder = attachment.Parent
		sound.Parent = attachment
	elseif typeof(where) == "Instance" then
		sound.Parent = where
	else
		sound.Parent = SoundService -- 2D
	end
	return sound, holder
end

-- Plays a cue (or a raw sound id) once. Returns the Sound, which cleans itself up.
function Audio.play(nameOrId: string, where: Where?, opts: PlayOptions?): Sound
	local sound, holder = build(nameOrId, where, opts)
	local delay = opts and opts.delay or 0
	local function start()
		if sound.Parent then
			sound:Play()
		end
	end
	if delay > 0 then
		task.delay(delay, start)
	else
		start()
	end
	-- Generous upper bound for cleanup when Ended never fires (an unloaded asset).
	local lifetime = delay + math.max(sound.TimeLength, 6) / math.max(sound.PlaybackSpeed, 0.1) + 1
	sound.Ended:Once(function()
		sound:Destroy()
		if holder then
			holder:Destroy()
		end
	end)
	Debris:AddItem(sound, lifetime)
	if holder then
		Debris:AddItem(holder, lifetime)
	end
	return sound
end

-- Starts a looping cue (ambience, music) with an optional fade-in. `stop(fade)` fades it out.
function Audio.loop(nameOrId: string, where: Where?, opts: { fade: number?, volume: number? }?): Loop
	local o: { fade: number?, volume: number? } = opts or {}
	local sound, holder = build(nameOrId, where, { volume = o.volume })
	sound.Looped = true
	local target = sound.Volume
	local fade = o.fade or 0
	if fade > 0 then
		sound.Volume = 0
	end
	sound:Play()
	local fading = true
	if fade > 0 then
		task.spawn(function()
			local t = 0
			while fading and sound.Parent and t < fade do
				t += task.wait()
				sound.Volume = target * math.clamp(t / fade, 0, 1)
			end
		end)
	end
	return {
		sound = sound,
		stop = function(out: number?)
			fading = false
			local duration = out or 0
			task.spawn(function()
				local from, t = sound.Volume, 0
				while sound.Parent and t < duration do
					t += task.wait()
					sound.Volume = from * (1 - math.clamp(t / duration, 0, 1))
				end
				sound:Destroy()
				if holder then
					holder:Destroy()
				end
			end)
		end,
	}
end

return Audio
