--!nonstrict
-- Dynamic inspection accepts engine objects and arbitrary test values. Game libraries remain strict.
-- MCPKit: compact helpers for Roblox Studio MCP. Install once per datamodel via execute_luau.
local K: any = { v = 4 }
local function SES()
	return game:GetService("ScriptEditorService") -- lazy: not available in every datamodel
end

function K.path(i: any)
	local t = {}
	while i and i ~= game do
		table.insert(t, 1, i.Name)
		i = i.Parent
	end
	return table.concat(t, ".")
end

function K.get(p: any)
	if typeof(p) == "Instance" then
		return p
	end
	local i = game
	for seg in string.gmatch((p:gsub("^game%.", "")), "[^%.]+") do
		local n = i:FindFirstChild(seg) or (i == game and game:GetService(seg))
		if not n then
			error("not found: " .. p .. " (at " .. seg .. ")", 2)
		end
		i = n
	end
	return i
end

local function fmt(v: any)
	local t = typeof(v)
	if t == "Vector3" then
		return string.format("%.4g,%.4g,%.4g", v.X, v.Y, v.Z)
	elseif t == "CFrame" then
		return "CF(" .. fmt(v.Position) .. ")"
	elseif t == "Color3" then
		return string.format("rgb(%d,%d,%d)", v.R * 255, v.G * 255, v.B * 255)
	elseif t == "Instance" then
		return K.path(v)
	elseif t == "number" then
		return string.format("%.4g", v)
	end
	return tostring(v)
end
K.fmt = fmt

-- Indented tree: "Name [Class] +N" (N = children beyond depth). class filters printed nodes via IsA.
function K.tree(root: any, depth: any, class: any, limit: any)
	root, depth, limit = K.get(root or "Workspace"), depth or 2, limit or 300
	local out = {}
	local function walk(i: any, d: any)
		if #out >= limit then
			return
		end
		local kids = i:GetChildren()
		if not class or i:IsA(class) then
			local more = (d >= depth and #kids > 0) and (" +" .. #kids) or ""
			table.insert(out, string.rep(" ", d) .. i.Name .. " [" .. i.ClassName .. "]" .. more)
		end
		if d < depth then
			for _, c in ipairs(kids) do
				walk(c, d + 1)
			end
		end
	end
	walk(root, 0)
	if #out >= limit then
		table.insert(out, "...truncated at " .. limit)
	end
	return table.concat(out, "\n")
end

-- Find descendants by class (IsA) and/or Lua name pattern. Returns instances (use K.paths to print).
function K.find(root: any, class: any, name: any, limit: any)
	local r = {}
	limit = limit or 500
	for _, d in ipairs(K.get(root or "Workspace"):GetDescendants()) do
		if (not class or d:IsA(class)) and (not name or string.find(d.Name, name)) then
			table.insert(r, d)
			if #r >= limit then
				break
			end
		end
	end
	return r
end

function K.paths(list: any)
	local t = {}
	for i, x in ipairs(list) do
		t[i] = K.path(x)
	end
	return table.concat(t, "\n")
end

-- Read selected properties (plus attributes) compactly: "Name=..; Size=..".
function K.props(i: any, names: any)
	i = K.get(i)
	local t = {}
	for _, n in ipairs(names or { "ClassName" }) do
		local ok, v = pcall(function()
			return i[n]
		end)
		table.insert(t, n .. "=" .. (ok and fmt(v) or "?"))
	end
	for k, v in pairs(i:GetAttributes()) do
		table.insert(t, "@" .. k .. "=" .. fmt(v))
	end
	return table.concat(t, "; ")
end

-- Set props on many instances, yielding every `chunk` to keep Studio responsive. Undoable as one step.
function K.set(list: any, props: any, chunk: any)
	local CHS = game:GetService("ChangeHistoryService")
	local rec = CHS:TryBeginRecording("MCPKit.set")
	local n = 0
	for _, i in ipairs(typeof(list) == "table" and list or { K.get(list) }) do
		for k, v in pairs(props) do
			i[k] = v
		end
		n += 1
		if n % (chunk or 1000) == 0 then
			task.wait()
		end
	end
	if rec then
		CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit)
	end
	return n
end

-- Script source, optionally a line range, with line numbers.
function K.src(p: any, a: any, b: any)
	local s = SES():GetEditorSource(K.get(p))
	if not a then
		return s
	end
	local out, n = {}, 0
	for line in (s .. "\n"):gmatch("(.-)\n") do
		n += 1
		if n >= a and n <= (b or a + 50) then
			table.insert(out, n .. "\t" .. line)
		end
	end
	return table.concat(out, "\n")
end

-- Exact (plain) find/replace edits on one script: edits = {{old, new[, all]}, ...}. Atomic: fails before writing.
function K.edit(p: any, edits: any)
	local s = SES():GetEditorSource(K.get(p))
	for idx, e in ipairs(edits) do
		local old, new, all = e[1], e[2], e[3]
		assert(
			type(old) == "string" and #old > 0 and type(new) == "string",
			"edits require nonempty old text and string replacements"
		)
		local a, b = string.find(s, old, 1, true)
		if not a then
			error("edit " .. idx .. ": old text not found", 2)
		end
		if all then
			local parts, pos = {}, 1
			while a do
				table.insert(parts, s:sub(pos, a - 1))
				table.insert(parts, new)
				pos = b + 1
				a, b = string.find(s, old, pos, true)
			end
			table.insert(parts, s:sub(pos))
			s = table.concat(parts)
		else
			if string.find(s, old, b + 1, true) then
				error("edit " .. idx .. ": old text not unique (pass all=true)", 2)
			end
			s = s:sub(1, a - 1) .. new .. s:sub(b + 1)
		end
	end
	SES():UpdateSourceAsync(K.get(p), function()
		return s
	end)
	return "ok " .. #edits .. " edits"
end

-- Create or overwrite a script. parentPath must exist; class defaults to ModuleScript.
function K.write(parentPath: any, name: any, source: any, class: any)
	local parent = K.get(parentPath)
	local s = parent:FindFirstChild(name)
	if not s then
		s = Instance.new(class or "ModuleScript")
		s.Name = name
		s.Parent = parent
	end
	SES():UpdateSourceAsync(s, function()
		return source
	end)
	return K.path(s)
end

-- Grep all scripts (plain text by default): "path:line: text", capped.
function K.grep(q: any, pattern: any, limit: any)
	local out = {}
	limit = limit or 50
	for _, d in ipairs(game:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			local ok, s = pcall(SES().GetEditorSource, SES(), d)
			if ok then
				local n = 0
				for line in (s .. "\n"):gmatch("(.-)\n") do
					n += 1
					if string.find(line, q, 1, not pattern) then
						table.insert(out, K.path(d) .. ":" .. n .. ": " .. line:sub(1, 160))
						if #out >= limit then
							return table.concat(out, "\n") .. "\n...capped"
						end
					end
				end
			end
		end
	end
	return table.concat(out, "\n")
end

-- Testing ---------------------------------------------------------------------

-- Screen coords of a part/model for user_mouse_input (Client datamodel).
function K.screen(p: any)
	local i = K.get(p)
	local pos = i:IsA("Model") and i:GetPivot().Position or i.Position
	local s, on = workspace.CurrentCamera:WorldToScreenPoint(pos)
	return string.format("%d,%d%s", s.X, s.Y, on and "" or " (offscreen)")
end

local LogService = game:GetService("LogService")
function K.mark()
	K._mark = #LogService:GetLogHistory()
	return "marked"
end

-- Warnings/errors (plus lines containing `filter`) since K.mark(); "clean" if none.
function K.logs(filter: any, limit: any)
	local out, h = {}, LogService:GetLogHistory()
	for i = (K._mark or 0) + 1, #h do
		local m = h[i]
		local bad = m.messageType == Enum.MessageType.MessageWarning or m.messageType == Enum.MessageType.MessageError
		if bad or (filter and string.find(m.message, filter, 1, true)) then
			table.insert(out, m.messageType.Name:sub(8, 11) .. ": " .. m.message:sub(1, 200))
		end
	end
	limit = limit or 30
	if #out > limit then
		out = { table.unpack(out, #out - limit + 1) }
	end
	return #out == 0 and "clean" or table.concat(out, "\n")
end

-- Background sampler. fn(t) runs every frame (or opts.every s) until it returns "stop" or opts.timeout (15 s);
-- non-nil returns are kept as rows. Arm it BEFORE triggering the action: the Client datamodel runs MCP calls one at a time.
function K.record(name: any, fn: any, opts: any)
	opts = opts or {}
	local maxRows = opts.maxRows or 600
	assert(maxRows >= 1 and maxRows <= 10000 and maxRows % 1 == 0, "maxRows must be 1..10000")
	assert((opts.timeout or 15) > 0 and (opts.timeout or 15) <= 120, "record timeout must be 0..120 seconds")
	local rec = { rows = {}, done = false, cancelled = false, total = 0 }
	K._recs = K._recs or {}
	if K._recs[name] then
		K._recs[name].cancelled = true
	end
	K._recs[name] = rec
	local function append(row)
		rec.total += 1
		if #rec.rows == maxRows then
			table.remove(rec.rows, 1)
		end
		table.insert(rec.rows, tostring(row):sub(1, 500))
	end
	task.spawn(function()
		local t0 = os.clock()
		while not rec.cancelled and os.clock() - t0 < (opts.timeout or 15) do
			local ok, row = pcall(fn, os.clock() - t0)
			if not ok then
				append("ERR " .. tostring(row))
				break
			end
			if row == "stop" then
				break
			end
			if row ~= nil then
				append(row)
			end
			if opts.every then
				task.wait(opts.every)
			else
				task.wait()
			end
		end
		rec.done = true
	end)
	return "recording " .. name
end

function K.cancel(name: any)
	local rec = K._recs and K._recs[name]
	if rec then
		rec.cancelled = true
	end
	return rec ~= nil
end

-- Wait up to `wait` s for a recording to finish; returns its last `limit` rows.
function K.results(name: any, wait: any, limit: any)
	local rec = K._recs and K._recs[name]
	if not rec then
		return "no recording " .. name
	end
	local t = os.clock()
	while not rec.done and os.clock() - t < (wait or 15) do
		task.wait(0.1)
	end
	local rows = rec.rows
	limit = limit or 40
	if #rows > limit then
		rows = { table.unpack(rows, #rows - limit + 1) }
	end
	return string.format(
		"%s: %d rows%s\n%s",
		name,
		rec.total,
		(rec.done and "" or " (still running)") .. (rec.total > #rec.rows and " (older rows dropped)" or ""),
		table.concat(rows, "\n")
	)
end

-- Call a Studio-only debug hook registered by game code (ServerStorage.DebugHooks.<feature>, Server datamodel).
function K.hook(feature: any, action: any, ...: any)
	local folder = game:GetService("ServerStorage"):FindFirstChild("DebugHooks")
	local f = folder and folder:FindFirstChild(feature)
	if not f then
		error("no debug hook '" .. feature .. "' (hooks exist only in the Server datamodel during a playtest)", 2)
	end
	return f:Invoke(action, ...)
end

-- Files ---------------------------------------------------------------------

-- Serialize an instance tree to Rojo .model.json (non-default properties, tags, attributes) so Studio-built
-- basic objects can live in the project. Use native Rojo syncback for meshes, UI, rigs and effects.
local EXPORT_CLASSES = {
	Folder = true,
	Model = true,
	Part = true,
	WedgePart = true,
	CornerWedgePart = true,
	PointLight = true,
	SpotLight = true,
	SurfaceLight = true,
	Decal = true,
	Texture = true,
	StringValue = true,
	IntValue = true,
	NumberValue = true,
	BoolValue = true,
	CFrameValue = true,
	Vector3Value = true,
}
local PROPS = {
	"Anchored",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
	"Massless",
	"Locked",
	"Transparency",
	"Reflectance",
	"Material",
	"Color",
	"Size",
	"CFrame",
	"Shape",
	"Brightness",
	"Range",
	"Enabled",
	"Texture",
	"Face",
	"Value",
	"Text",
	"CollisionGroup",
	"MaterialVariant",
	"PivotOffset",
	"RootPriority",
	"Shadows",
	"Angle",
	"Color3",
	"ZIndex",
	"StudsPerTileU",
	"StudsPerTileV",
	"OffsetStudsU",
	"OffsetStudsV",
	"TopSurface",
	"BottomSurface",
	"LeftSurface",
	"RightSurface",
	"FrontSurface",
	"BackSurface",
	"ModelStreamingMode",
	"LevelOfDetail",
}
local defaults = {}
local function encode(v: any)
	local t = typeof(v)
	if t == "boolean" or t == "number" or t == "string" then
		return v
	end
	if t == "EnumItem" then
		return v.Name
	end
	if t == "Vector3" then
		return { v.X, v.Y, v.Z }
	end
	if t == "Color3" then
		return { v.R, v.G, v.B }
	end
	if t == "CFrame" then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
		return {
			CFrame = {
				position = { x, y, z },
				orientation = { { r00, r01, r02 }, { r10, r11, r12 }, { r20, r21, r22 } },
			},
		}
	end
	return nil
end
local function attribute(v)
	local kind = typeof(v)
	local explicit = { boolean = "Bool", number = "Float64", string = "String", Vector3 = "Vector3", Color3 = "Color3" }
	if explicit[kind] then
		return { [explicit[kind]] = encode(v) }
	end
	if kind == "CFrame" then
		return encode(v)
	end
	error("unsupported attribute type " .. kind .. "; use native Rojo syncback", 3)
end
local function node(i: any)
	assert(
		EXPORT_CLASSES[i.ClassName],
		"basic model export does not support " .. i.ClassName .. "; use native Rojo syncback"
	)
	if i:IsA("Model") then
		assert(i.PrimaryPart == nil, "PrimaryPart references require native Rojo syncback")
	end
	if i:IsA("BasePart") then
		assert(i.CustomPhysicalProperties == nil, "CustomPhysicalProperties require native Rojo syncback")
	end
	local n = { name = i.Name, className = i.ClassName }
	local ok, def = pcall(function()
		defaults[i.ClassName] = defaults[i.ClassName] or Instance.new(i.ClassName)
		return defaults[i.ClassName]
	end)
	local props, any = {}, false
	for _, k in ipairs(PROPS) do
		local okv, v = pcall(function()
			return i[k]
		end)
		if okv and v ~= nil and (k == "CFrame" or not ok or def[k] ~= v) then
			local e = encode(v)
			if e ~= nil then
				props[k], any = e, true
			end
		end
	end
	local tags = i:GetTags()
	if #tags > 0 then
		props.Tags, any = tags, true
	end
	local attrs, anyAttr = {}, false
	for k, v in pairs(i:GetAttributes()) do
		local e = attribute(v)
		if e ~= nil then
			attrs[k], anyAttr = e, true
		end
	end
	if anyAttr then
		props.Attributes, any = attrs, true
	end
	if any then
		n.properties = props
	end
	local kids = {}
	for _, c in ipairs(i:GetChildren()) do
		table.insert(kids, node(c))
	end
	if #kids > 0 then
		n.children = kids
	end
	return n
end
function K.toModelJson(p: any)
	local n = node(K.get(p))
	n.name = nil -- the file name sets the instance name
	return game:GetService("HttpService"):JSONEncode(n)
end

-- Tests ----------------------------------------------------------------------------
-- Specs are ModuleScripts named "*.spec" under ServerStorage.Tests (Rojo: tests/**/*.spec.luau) that return
-- function(t) t.test("name", function() t.eq(got, want) end) end.
-- Run in the Server datamodel of a playtest: every playtest is a fresh VM, so tests see current code.
-- In Edit mode requires are cached across calls; t.require loads a fresh clone of a module (its own nested
-- requires may still be stale there).
local function show(v: any)
	return type(v) == "string" and string.format("%q", v) or tostring(v)
end
function K.test(filter: any)
	local root = game:GetService("ServerStorage"):FindFirstChild("Tests")
	if not root then
		return "no ServerStorage.Tests folder"
	end
	local fresh = not game:GetService("RunService"):IsRunning()
	local clones, passed, failed, lines, suites = {}, 0, 0, {}, 0
	local function load(m: any)
		if not fresh then
			return require(m)
		end
		local c = m:Clone()
		c.Name = m.Name .. "__fresh"
		c.Archivable = false
		c.Parent = m.Parent
		table.insert(clones, c)
		return require(c)
	end
	local t = {}
	function t.eq(a: any, b: any, msg: any)
		if a ~= b then
			error((msg and msg .. ": " or "") .. "expected " .. show(b) .. ", got " .. show(a), 2)
		end
	end
	function t.ok(v: any, msg: any)
		if not v then
			error(msg or "expected truthy, got " .. show(v), 2)
		end
	end
	function t.near(a: any, b: any, eps: any, msg: any)
		if math.abs(a - b) > (eps or 1e-6) then
			error((msg and msg .. ": " or "") .. "expected ~" .. show(b) .. ", got " .. show(a), 2)
		end
	end
	function t.fails(fn: any, contains: any)
		local ok, err = pcall(fn)
		if ok then
			error("expected an error", 2)
		end
		if contains and not string.find(tostring(err), contains, 1, true) then
			error("error " .. show(tostring(err)) .. " does not contain " .. show(contains), 2)
		end
	end
	t.require = load
	for _, spec in ipairs(root:GetDescendants()) do
		if
			spec:IsA("ModuleScript")
			and spec.Name:match("%.spec$")
			and (not filter or string.find(spec.Name, filter, 1, true))
		then
			suites += 1
			local suite = spec.Name:gsub("%.spec$", "")
			function t.test(name: any, fn: any)
				local ok, err = pcall(fn)
				if ok then
					passed += 1
				else
					failed += 1
					table.insert(lines, "FAIL " .. suite .. " > " .. name .. ": " .. tostring(err))
				end
			end
			local okLoad, body = pcall(load, spec)
			if not okLoad or type(body) ~= "function" then
				failed += 1
				table.insert(lines, "FAIL " .. suite .. ": spec must return function(t): " .. tostring(body))
			else
				local okRun, err = pcall(body, t)
				if not okRun then
					failed += 1
					table.insert(lines, "FAIL " .. suite .. " (outside a test): " .. tostring(err))
				end
			end
		end
	end
	for _, c in ipairs(clones) do
		c:Destroy()
	end
	if suites == 0 then
		return "no test specs matched; nothing was tested"
	end
	return string.format(
		"%d passed, %d failed%s",
		passed,
		failed,
		fresh and " (edit mode: nested requires may be stale)" or ""
	) .. (#lines > 0 and "\n" .. table.concat(lines, "\n") or "")
end

-- Quick health/perf snapshot: instance counts, heaviest classes, memory, physics parts.
function K.perf(top: any)
	local counts, total, parts, unanchored = {}, 0, 0, 0
	for _, d in ipairs(workspace:GetDescendants()) do
		total += 1
		counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
		if d:IsA("BasePart") then
			parts += 1
			if not d.Anchored then
				unanchored += 1
			end
		end
	end
	local list = {}
	for class, n in pairs(counts) do
		table.insert(list, { class, n })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	local heavy = {}
	for i = 1, math.min(top or 8, #list) do
		heavy[i] = list[i][1] .. "=" .. list[i][2]
	end
	local mem = game:GetService("Stats"):GetTotalMemoryUsageMb()
	return string.format(
		"workspace instances=%d parts=%d unanchored=%d studioMemory=%.0fMB streaming=%s\ntop: %s",
		total,
		parts,
		unanchored,
		mem,
		tostring(workspace.StreamingEnabled),
		table.concat(heavy, " ")
	)
end

-- Pre-publish audit: deprecated APIs, input that doesn't work on every platform, risky remotes, leftovers.
function K.audit()
	local SESok = pcall(SES)
	local issues = {}
	local function add(s: any)
		if #issues < 60 then
			table.insert(issues, s)
		end
	end
	local deprecated = {
		{ "%f[%w_.]wait%(", "wait() -> task.wait()" },
		{ "%f[%w_.]spawn%(", "spawn() -> task.spawn()" },
		{ "%f[%w_.]delay%(", "delay() -> task.delay()" },
		{ ":connect%(", ":connect -> :Connect" },
		{ "Instance%.new%([^,%)]+,", "Instance.new(class, parent) -> set Parent last" },
		{ "LoadAnimation", "Humanoid:LoadAnimation -> Animator:LoadAnimation" },
		{ "%f[%w_]loadstring%(", "loadstring is disabled in live games" },
		{ '"ClickDetector"', "ClickDetector: no console/gamepad support; prefer ProximityPrompt" },
	}
	for _, d in ipairs(game:GetDescendants()) do
		if d:IsA("LuaSourceContainer") and d.Name ~= "MCPKit" and SESok then
			if d:IsA("BaseScript") and d.Disabled then
				add(K.path(d) .. " disabled script (review before publish)")
			end
			local ok, src = pcall(SES().GetEditorSource, SES(), d)
			if ok then
				local n = 0
				for line in (src .. "\n"):gmatch("(.-)\n") do
					n += 1
					if not line:match("^%s*%-%-") then
						for _, rule in ipairs(deprecated) do
							if line:find(rule[1]) then
								add(K.path(d) .. ":" .. n .. " " .. rule[2])
							end
						end
						if line:find("OnServerEvent") and not src:find("typeof%(") and not src:find("Net%.") then
							add(
								K.path(d)
									.. ":"
									.. n
									.. " OnServerEvent without visible argument validation (use Kit.Net)"
							)
						end
					end
				end
			end
		elseif d:IsA("ClickDetector") then
			add(K.path(d) .. " ClickDetector: no console/gamepad support; prefer ProximityPrompt")
		elseif d:IsA("TextButton") and d.Text == "Button" then
			add(K.path(d) .. " button still says 'Button'")
		elseif (d:IsA("Script") or d:IsA("LocalScript")) and d.Disabled then
			add(K.path(d) .. " disabled script (leftover?)")
		end
	end
	if not workspace.StreamingEnabled then
		add("Workspace.StreamingEnabled is off (slower joins/higher memory on mobile)")
	end
	return #issues == 0 and "audit clean" or (#issues .. " issues\n" .. table.concat(issues, "\n"))
end

-- selene: allow(global_usage)
_G.K = K
return K
