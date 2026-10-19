--!strict
-- Motion: easing curves, keyframe tracks and springs on the shared Scheduler.
-- Pure helpers (`ease`, `sample`, `springStep`) need no engine, so timing is unit tested.
--
--   Motion.to(frame, { Position = UDim2.fromScale(0.5, 0.4) }, { time = 0.3, ease = "backOut" })
--   Motion.keys(part, "Size", { { t = 0, v = Vector3.one }, { t = 0.2, v = Vector3.one * 6, ease = "expoOut" } })
--   local s = Motion.spring(0, { speed = 12, damping = 0.6 }) ; s.target = 1 -- s.value follows
local Scheduler = require(script.Parent.Scheduler)

local Motion = {}

-- Easing names: linear, quadIn, quadOut, quadInOut, cubicOut, expoIn, expoOut, backIn, backOut,
-- elasticOut, sineInOut, anticipate. Typed as string so data tables stay easy to write; `Motion.isEase`
-- checks a name.
export type Ease = string
export type Key<T> = { t: number, v: T, ease: Ease? }
export type Spring = { value: number, velocity: number, target: number, speed: number, damping: number }

local PI = math.pi

local curves: { [string]: (number) -> number } = {
	linear = function(x)
		return x
	end,
	quadIn = function(x)
		return x * x
	end,
	quadOut = function(x)
		return 1 - (1 - x) * (1 - x)
	end,
	quadInOut = function(x)
		return if x < 0.5 then 2 * x * x else 1 - (-2 * x + 2) ^ 2 / 2
	end,
	cubicOut = function(x)
		return 1 - (1 - x) ^ 3
	end,
	expoIn = function(x)
		return if x <= 0 then 0 else 2 ^ (10 * x - 10)
	end,
	expoOut = function(x)
		return if x >= 1 then 1 else 1 - 2 ^ (-10 * x)
	end,
	backOut = function(x)
		local c1 = 1.70158
		return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
	end,
	backIn = function(x)
		local c1 = 1.70158
		return (c1 + 1) * x ^ 3 - c1 * x ^ 2
	end,
	elasticOut = function(x)
		if x <= 0 or x >= 1 then
			return x
		end
		return 2 ^ (-10 * x) * math.sin((x * 10 - 0.75) * (2 * PI) / 3) + 1
	end,
	sineInOut = function(x)
		return -(math.cos(PI * x) - 1) / 2
	end,
	-- Pull back first, then overshoot forward: a wind-up in one curve.
	anticipate = function(x)
		local c = 2.2
		return x * x * ((c + 1) * x - c)
	end,
}

function Motion.isEase(name: string): boolean
	return curves[name] ~= nil
end

-- Eased progress for `x` in 0..1 (clamped). Unknown names fall back to linear.
function Motion.ease(name: Ease?, x: number): number
	local alpha = if x ~= x then 0 else math.clamp(x, 0, 1)
	local curve = curves[name or "linear"] or curves.linear
	return curve(alpha)
end

local function lerp(a: any, b: any, alpha: number): any
	if type(a) == "number" then
		return a + (b - a) * alpha
	end
	return a:Lerp(b, alpha) -- Vector3, Vector2, Color3, CFrame, UDim2
end

-- Value of a keyframe track at time `t`; each key's `ease` shapes the segment that ends at it.
function Motion.sample<T>(keys: { Key<T> }, t: number): T
	assert(#keys > 0, "Motion.sample needs at least one key")
	if t <= keys[1].t then
		return keys[1].v
	end
	for i = 2, #keys do
		local b = keys[i]
		if t <= b.t then
			local a = keys[i - 1]
			local span = b.t - a.t
			local alpha = if span <= 0 then 1 else (t - a.t) / span
			return lerp(a.v, b.v, Motion.ease(b.ease, alpha))
		end
	end
	return keys[#keys].v
end

-- Length of a key track in seconds.
function Motion.length<T>(keys: { Key<T> }): number
	return if #keys > 0 then keys[#keys].t else 0
end

-- Advances a damped spring by `dt` (semi-implicit Euler, sub-stepped for stability).
function Motion.springStep(s: Spring, dt: number)
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	local k = s.speed * s.speed
	local c = 2 * s.damping * s.speed
	for _ = 1, steps do
		s.velocity += (k * (s.target - s.value) - c * s.velocity) * h
		s.value += s.velocity * h
	end
end

-- A spring driven by the shared scheduler until `stop` is called. Read `value`, set `target`.
function Motion.spring(initial: number, opts: { speed: number?, damping: number? }?): Spring & { stop: () -> () }
	local o: { speed: number?, damping: number? } = opts or {}
	local s: any =
		{ value = initial, velocity = 0, target = initial, speed = o.speed or 10, damping = o.damping or 0.7 }
	s.stop = Scheduler.every(function(dt)
		Motion.springStep(s, dt)
		return false
	end)
	return s
end

export type TweenOptions = { time: number?, ease: Ease?, delay: number?, onDone: (() -> ())? }

-- Tweens properties of `inst` on the shared scheduler. Returns a cancel function.
function Motion.to(inst: Instance, props: { [string]: any }, opts: TweenOptions?): () -> ()
	local o: TweenOptions = opts or {}
	local duration = math.max(o.time or 0.25, 1e-3)
	local delay = o.delay or 0
	local from: { [string]: any } = {}
	local target = inst :: any
	for name in props do
		from[name] = target[name]
	end
	local elapsed = 0
	return Scheduler.every(function(dt)
		if inst.Parent == nil then
			return true
		end
		elapsed += dt
		local alpha = math.clamp((elapsed - delay) / duration, 0, 1)
		if elapsed < delay then
			return false
		end
		local eased = Motion.ease(o.ease or "quadOut", alpha)
		for name, value in props do
			target[name] = lerp(from[name], value, eased)
		end
		if alpha >= 1 then
			if o.onDone then
				task.spawn(o.onDone)
			end
			return true
		end
		return false
	end)
end

-- Plays a keyframe track on one property of `inst`. Returns a cancel function.
function Motion.keys<T>(inst: Instance, property: string, keys: { Key<T> }, opts: { onDone: (() -> ())? }?): () -> ()
	local elapsed = 0
	local length = Motion.length(keys)
	local target = inst :: any
	return Scheduler.every(function(dt)
		if inst.Parent == nil then
			return true
		end
		elapsed += dt
		target[property] = Motion.sample(keys, elapsed)
		if elapsed >= length then
			if opts and opts.onDone then
				task.spawn(opts.onDone)
			end
			return true
		end
		return false
	end)
end

return Motion
