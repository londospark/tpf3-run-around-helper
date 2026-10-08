-- Wrappers that let a locomotive's own model run as a free entity - the run-around
-- "ghost" - with its own sound, smoke, wheel animation and paint.
--
-- The game's sound and transformator scripts for locos read vehicle data
-- (currentInfo.vehicle / railVehicle / landVehicle) that a free entity does not
-- have. ghost_build.script.lua points each loco's sound set (a wrapped copy in
-- res/audio/ghostwrap/) and transformator (res/models/runaround_ghost/real*.trf)
-- at the functions here at load time.
--
--   * For a real train they do exactly what the game's own functions do.
--   * For a free entity they read the ghost's custom entity state, sent by the
--     run-around script:
--         { speed01, power01,                       (top level: read by sound sets)
--           state = { speed, power, vx, vy, color, dir, seg = {...} } }
--     and feed the game's own sound function synthesised vehicle data, drive the
--     wheel animation, set the smoke and put the loco's paint on.
--
-- Scripts are called directly (ug_require of the module), not through util.useFn:
-- in the transformator scope useFn fails ("attempt to index global 'loaderHelper'
-- (a boolean value)", seen live on every train).

local transformator_util = ug_require "::/scripts/transformator_util.tl"

local okSound, soundModule = pcall(ug_require, "::/scripts/soundset_default.script.tl")
local baseUpdateSoundSet = okSound and type(soundModule) == "table" and soundModule.updateSoundSet or nil
if baseUpdateSoundSet == nil then
	-- The sound scope does have a working util.useFn (the game's own sound script uses it).
	local okUtil, util = pcall(ug_require, "::/scripts/util.tl")
	if okUtil and type(util) == "table" and type(util.useFn) == "function" then
		baseUpdateSoundSet = function(...)
			return util.useFn("::/scripts/soundset_default.script@updateSoundSet")(...)
		end
	end
end
-- Neither found (a game update moved the stock sound script): every wrapped
-- sound set calls updateSoundSet every frame, so it must not raise an error
-- there. Trains are then silent rather than spamming the log; said once here.
if baseUpdateSoundSet == nil then
	print("[RunAroundHelper] the game's sound script (soundset_default.script.tl) was not found: wrapped train sounds are silent. Please report this.")
end

-- Wheel animation ("wheels", steam locos): one revolution is 5000 ms of animation
-- time in every base-game steam loco (ani/wheels/*.ani). The driving wheel radius is
-- not available to a script, so a typical one is used.
local WHEEL_RADIUS = 0.9
local WHEEL_ANIMATION_MS = 5000

-- A real carriage whose paint is this flag colour is drawn as nothing (every node
-- scaled to zero, as the base game's fireworks vanish): the run-around hides
-- the real coaches this way while their ghost copies are shown, so the coaches -
-- and their passengers and goods - never leave the train.
local HIDE = { 0.1234567, 0.7654321, 0.3141593 }
local function isHidden(vehicleInfo)
	local c = vehicleInfo and vehicleInfo.color
	return c ~= nil and math.abs(c.x - HIDE[1]) < 1e-3 and math.abs(c.y - HIDE[2]) < 1e-3 and math.abs(c.z - HIDE[3]) < 1e-3
end

-- Load nodes of the hidden real carriages, by carriage entity, so that the ghost
-- copy of a loaded wagon shows the same load (its state names the carriage).
local hiddenLoads = {}

-- The carriage entity a transformator call is for (what the run-around names as a
-- ghost's "mirror"): vehicleStaticInfo.carriageEntity, else the entity id.
local function carriageOf(params)
	local si = params.vehicleStaticInfo
	return (si ~= nil and si.carriageEntity) or params.entityId
end

-- How many nodes the model has, or nil if the output will not say.
local atan2 = math.atan2 or math.atan -- (Lua 5.1's math.atan takes one argument)

local function userTransfCount(transfsOutput)
	local ok, n = pcall(function() return #transfsOutput:getUserTransfs() end)
	if ok and type(n) == "number" and n > 0 then return n end
	return nil
end

local function hide(params, transfsOutput)
	local ci = params.currentInfo
	local indices = {}
	for i, v in ipairs(ci.vehicle.indicesLoadConfig or {}) do indices[i] = v end
	hiddenLoads[carriageOf(params)] = indices
	-- EVERY node, not just the root: the bogies (and their wheels) are placed on
	-- the track by the engine, not through the root, so scaling only the root
	-- left them showing (seen live).
	local zero = api.type.Mat4f.scale(api.type.Vec3f.new(0.0, 0.0, 0.0))
	local n = userTransfCount(transfsOutput)
	if n ~= nil then
		for i = 0, n - 1 do transfsOutput:setUserTransf(i, zero) end
	else
		-- count unknown: every index until the output refuses one
		for i = 0, 255 do
			if not pcall(transfsOutput.setUserTransf, transfsOutput, i, zero) then break end
		end
	end
end

-- A real carriage: hidden when it is painted the flag colour (true), otherwise
-- left to the stock code (false). One drawn again forgets its hidden load; that
-- is only looked up while something is hidden, so other trains pay nothing.
local function hideIfFlagged(params, transfsOutput)
	if isHidden(params.currentInfo.vehicle) then
		hide(params, transfsOutput)
		return true
	end
	if next(hiddenLoads) ~= nil then hiddenLoads[carriageOf(params)] = nil end
	return false
end

local function stateOf(currentInfo)
	local cs = currentInfo.customState
	return cs and cs.state or nil
end

-- Distance the ghost has travelled, from its current motion segment
-- (seg = { d0, v0, acc, vmax, t0 }): accelerating from v0 at acc up to vmax, or
-- braking at a negative acc down to a stop, starting at game time t0 (ms) with
-- distance d0. Worked out from the clock on every call, so the wheels turn
-- smoothly between the ghost's state updates; the segment only changes when the
-- motion does (start, stop, reversal, final approach).
local function segmentDistance(st, now)
	local seg = st.seg
	if seg == nil or seg.t0 == nil or now == nil then return st.dist or 0.0 end
	local t = math.max(now - seg.t0, 0.0) / 1000.0
	local d0, v0, a, vmax = seg.d0 or 0.0, seg.v0 or 0.0, seg.acc or 0.0, seg.vmax or 0.0
	if a > 0 then
		local tAcc = math.max((vmax - v0) / a, 0.0)
		if t <= tAcc then return d0 + v0 * t + 0.5 * a * t * t end
		return d0 + v0 * tAcc + 0.5 * a * tAcc * tAcc + vmax * (t - tAcc)
	elseif a < 0 then
		local tStop = v0 / -a
		if t > tStop then t = tStop end
		return d0 + v0 * t + 0.5 * a * t * t
	end
	return d0 + v0 * t
end

local function applyColor(st, transfsOutput)
	local c = st.color
	if c ~= nil then
		transfsOutput:setModelInstanceAttributeVec3f(transformator_util.colorAttributePostition,
			api.type.Vec3f.new(c[1] or 0.0, c[2] or 0.0, c[3] or 0.0))
	end
end

-- The parts the engine would place for a real train (the loco body, tender,
-- pony truck or bogies) and the axles it would turn: decoded from the model's
-- runaround_partsN parameters (see ghost_build's partsSpecs), the one whose node
-- count is the level of detail being drawn.
local partsCache = {}
local function decodeParts(s)
	local v = {}
	for w in string.gmatch(s, "%S+") do v[#v + 1] = tonumber(w) end
	local n, G, A = v[1], v[2], v[3]
	if n == nil or G == nil or A == nil or #v ~= 3 + G * 16 + A * 3 then return false end
	local out, k = { n = n, groups = {}, axles = {} }, 4
	for _ = 1, G do
		out.groups[#out.groups + 1] = { idx = v[k], parent = v[k + 1], model = { v[k + 2], v[k + 3], v[k + 4], v[k + 5] },
			lcl = { v[k + 6], v[k + 7], v[k + 8], v[k + 9] }, parentModel = { v[k + 10], v[k + 11], v[k + 12], v[k + 13] },
			a = v[k + 14], b = v[k + 15] }
		k = k + 16
	end
	for _ = 1, A do
		out.axles[#out.axles + 1] = { idx = v[k], r = v[k + 1], sign = v[k + 2] }
		k = k + 3
	end
	return out
end
-- The same spec with every node after the root one further on: devers wraps
-- everything under the root in one node of its own (its roll), so if the spec
-- was made without it, the drawn model has one node more.
local function shifted(r)
	local out = { n = r.n + 1, groups = {}, axles = {} }
	local function sh(i) return i + 1 end -- the root's children are now the wrapper's
	for _, g in ipairs(r.groups) do
		out.groups[#out.groups + 1] = { idx = sh(g.idx), parent = sh(g.parent), model = g.model, lcl = g.lcl, parentModel = g.parentModel, a = g.a, b = g.b }
	end
	for _, a in ipairs(r.axles) do out.axles[#out.axles + 1] = { idx = sh(a.idx), r = a.r, sign = a.sign } end
	return out
end
local partsMissLogged = {}
local function partsFor(params, n)
	local tcp = params.transformatorConfigParams
	if n == nil then return nil end
	local okP, has = pcall(function() return tcp ~= nil and tcp.runaround_parts1 ~= nil end)
	if not (okP and has) then
		if (partsMissLogged.none or 0) < 5 then
			partsMissLogged.none = (partsMissLogged.none or 0) + 1
			local mdl = nil
			pcall(function() mdl = tcp and tcp.runaround_mdl end)
			print("[RunAroundHelper] loco copy parts: " .. tostring(mdl) .. " (" .. tostring(n) .. " nodes) has no parts spec;"
				.. " its parameters are " .. type(tcp) .. " - tender and bogies stay rigid")
		end
		return nil
	end
	local seen, wrapped = {}, (tcp.devers_trf ~= nil or tcp.devers_rest1 ~= nil)
	for i = 1, 8 do
		local s = tcp["runaround_parts" .. i]
		if type(s) ~= "string" then break end
		local r = partsCache[s]
		if r == nil then
			r = decodeParts(s)
			partsCache[s] = r
		end
		if r and r.n == n then return r end
		if r and wrapped and r.n + 1 == n then
			local key = s .. "+1"
			if partsCache[key] == nil then partsCache[key] = shifted(r) end
			return partsCache[key]
		end
		seen[#seen + 1] = r and tostring(r.n) or "unreadable"
	end
	local key = tostring(tcp.runaround_mdl) .. ":" .. tostring(n)
	if not partsMissLogged[key] and #seen > 0 and (partsMissLogged.count or 0) < 10 then
		partsMissLogged[key] = true
		partsMissLogged.count = (partsMissLogged.count or 0) + 1
		print("[RunAroundHelper] loco copy parts: " .. tostring(tcp.runaround_mdl) .. " is drawn with " .. tostring(n)
			.. " nodes; its parts spec is for " .. (#seen > 0 and table.concat(seen, ", ") or "none (no runaround_parts on the model)")
			.. (wrapped and " (devers)" or "") .. " - tender and bogies stay rigid")
	end
	return nil
end

-- (x, y, z, yaw) poses: composed, inverted, as a matrix
local function composeP(a, b)
	local c, s = math.cos(a[4]), math.sin(a[4])
	return { a[1] + c * b[1] - s * b[2], a[2] + s * b[1] + c * b[2], a[3] + b[3], a[4] + b[4] }
end
local function inverseP(a)
	local c, s = math.cos(a[4]), math.sin(a[4])
	return { -(c * a[1] + s * a[2]), -(-s * a[1] + c * a[2]), -a[3], -a[4] }
end
local function poseMat(p)
	return api.type.Mat4f.rotZTransl(p[4], api.type.Vec3f.new(p[1], p[2], p[3]))
end
-- turned phi about the axle (y): the top moves forwards (+x) for phi > 0
local function axleMat(phi)
	local c, s = math.cos(phi), math.sin(phi)
	local V4 = api.type.Vec4f.new
	return api.type.Mat4f.new(V4(c, 0, -s, 0), V4(0, 1, 0, 0), V4(s, 0, c, 0), V4(0, 0, 0, 1))
end

-- The track under the copy, as the run-around sends it: points at model x =
-- s0, s0 + ds, ... in the copy's own frame (x forwards, y left). Between and
-- beyond them, straight lines.
local function trackPoint(tr, x)
	local pts = tr.pts
	local count = math.floor(#pts / 2)
	local f = (x - tr.s0) / tr.ds
	local i = math.max(0, math.min(count - 2, math.floor(f)))
	local t = f - i
	local x1, y1, x2, y2 = pts[2 * i + 1], pts[2 * i + 2], pts[2 * i + 3], pts[2 * i + 4]
	return x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
end
local function trackYaw(tr, a, b)
	if a - b < 0.5 then a, b = a + 1.0, b - 1.0 end -- one point: the direction there
	local ax, ay = trackPoint(tr, a)
	local bx, by = trackPoint(tr, b)
	return atan2(ay - by, ax - bx)
end

-- Places the copy's parts as the engine would for a real train: each part's
-- centre kept where it is on the vehicle, turned to follow the track under its
-- axles; the small axles turned by the distance rolled (signed: backwards when
-- the copy runs backwards). As user transforms relative to the parent node:
-- node = parent * rest * U, so U = rest^-1 * parent^-1 * wanted.
-- The columns of a matrix from the engine ({x, y, z} each), whichever way it
-- reads in this context, or nil.
local function matrixCols(m)
	local tries = {
		function() local o = {} for j = 1, 4 do local v = api.type.Mat4f.cols(m, j - 1) o[j] = { v.x, v.y, v.z } end return o end,
		function() local o = {} for j = 1, 4 do local v = m:cols(j - 1) o[j] = { v.x, v.y, v.z } end return o end,
		function() local o = {} for j = 1, 4 do o[j] = { m[(j - 1) * 4 + 1], m[(j - 1) * 4 + 2], m[(j - 1) * 4 + 3] } end return o end,
		function() local o = {} for j = 1, 4 do o[j] = { m[(j - 1) * 4], m[(j - 1) * 4 + 1], m[(j - 1) * 4 + 2] } end return o end,
	}
	for _, f in ipairs(tries) do
		local ok, c = pcall(f)
		if ok and type(c[4][1]) == "number" and type(c[1][1]) == "number" then return c end
	end
	return nil
end

-- Which index setUserTransf gives the list's first entry (0 or 1): measured once
-- (a marker written and read back, then put back), as devers does; the parts
-- are placed only once it is known.
local indexBase = nil
local function measureIndexBase(transfsOutput)
	local V4 = api.type.Vec4f.new
	local marker = api.type.Mat4f.new(V4(1, 0, 0, 0), V4(0, 1, 0, 0), V4(0, 0, 1, 0), V4(0, 0, 1234.5, 1))
	local first = transfsOutput:getUserTransfs()[1]
	local saved, savedAbs = first.transf, first.type == 2
	for _, b in ipairs({ 0, 1 }) do
		local okSet = pcall(transfsOutput.setUserTransf, transfsOutput, b, marker, false)
		local e = transfsOutput:getUserTransfs()[1]
		local c = okSet and e and matrixCols(e.transf) or nil
		if c ~= nil and math.abs(c[4][3] - 1234.5) < 1e-3 then
			pcall(transfsOutput.setUserTransf, transfsOutput, b, saved, savedAbs)
			return b
		end
	end
	pcall(transfsOutput.setUserTransf, transfsOutput, 0, saved, savedAbs)
	return false
end

local function placeParts(params, st, transfsOutput, signedDist)
	local spec = partsFor(params, userTransfCount(transfsOutput))
	if spec == nil then return end
	if indexBase == nil then
		local ok, b = pcall(measureIndexBase, transfsOutput)
		indexBase = ok and b or false
		print("[RunAroundHelper] loco copy parts: user transform indices start at " .. tostring(indexBase)
			.. (indexBase == false and " (not measurable: tender and bogies stay rigid)" or ""))
	end
	if indexBase == false then return end
	local base = indexBase
	local tr = st.track
	if tr ~= nil and type(tr.pts) == "table" and #tr.pts >= 4 and tr.ds and tr.ds > 0 then
		local poses = {}
		for _, g in ipairs(spec.groups) do
			local m = g.model
			local want = { m[1], m[2], m[3], m[4] + trackYaw(tr, g.a, g.b) }
			local parent = poses[g.parent] or g.parentModel
			local u = composeP(inverseP(g.lcl), composeP(inverseP(parent), want))
			poses[g.idx] = want
			transfsOutput:setUserTransf(g.idx + base, poseMat(u), false)
		end
	end
	for _, a in ipairs(spec.axles) do
		transfsOutput:setUserTransf(a.idx + base, axleMat(a.sign * signedDist / a.r), false)
	end
end

-- Free entity: paint, drive and wheel animation from the ghost's state.
local function ghostUpdate(params, transfsOutput)
	local ci = params.currentInfo
	local st = stateOf(ci)
	if st == nil then return end
	applyColor(st, transfsOutput)
	if st.mirror ~= nil and hiddenLoads[st.mirror] ~= nil then
		transformator_util.scaleUserTransfIndicesLoadConfig(hiddenLoads[st.mirror], transfsOutput)
	end
	local dist = segmentDistance(st, ci.world and ci.world.gameTime)
	local reversed = (st.dir or 1) < 0
	transformator_util.addDriveAnimationState(dist, reversed, transfsOutput)
	-- The frame keeps increasing (the animation loops by itself); wrapping it to one
	-- turn made the renderer blend backwards through a whole turn at every wrap.
	local frame = math.floor(dist / (2.0 * math.pi * WHEEL_RADIUS) * WHEEL_ANIMATION_MS + 0.5)
	transfsOutput:addAnimationState("wheels", -1, frame, true, reversed)
	-- distance along the copy's own facing (the segment's start, s0, and its direction)
	local seg = st.seg
	local signed = ((seg and seg.s0) or 0.0) + (reversed and -1 or 1) * (dist - ((seg and seg.d0) or 0.0))
	pcall(placeParts, params, st, transfsOutput, signed)
end

-- The stock train transformator (vehicle/train/shared/transformator_train.script.tl),
-- copied so that real trains do not depend on calling another script.
local function stockTrainUpdate(params, transfsOutput)
	local ci = params.currentInfo
	local lv = ci.landVehicle
	local time = transformator_util.getEntityTime(ci.world.gameTime, params.entityId)
	transformator_util.addAnimationStatesRailVehicles(lv.side, lv.reversed, transfsOutput)
	transformator_util.addDriveAnimationState(lv.wheelAnimationInfo.totalDist, lv.reversed, transfsOutput)
	transformator_util.addDrivingWheelAnimationState(lv.wheelAnimationInfo.drivingWheelRadius,
		lv.wheelAnimationInfo.totalDist, lv.wheelAnimationInfo.wheelDuration, lv.reversed, transfsOutput)
	transformator_util.addDoorAnimationState(ci.vehicle.doorAnimationInfo, transfsOutput)
	transformator_util.addBrakeLightsAnimationState(lv.brakingTimer, time, transfsOutput)
	transformator_util.scaleUserTransfIndicesLoadConfig(ci.vehicle.indicesLoadConfig, transfsOutput)
end

-- PROBE (temporary, logging only): for a real steam loco (runaround_probe set at
-- load by ghost_build), which parts the engine places itself (tender, axles,
-- bogies) and where, so that the loco's copy can place them the same way. Every
-- 20 s per carriage while moving, at most 6 times: the user transforms that
-- aren't the identity, as index:type x,y,z heading(degrees).
local probeSeen = {}
local function probe(params, transfsOutput)
	local p = params.transformatorConfigParams
	if p == nil or p.runaround_probe ~= true then return end
	local ci = params.currentInfo
	local speed = ci.vehicle and ci.vehicle.speed or 0
	if math.abs(speed) < 1.0 then return end
	local key = carriageOf(params)
	local now = ci.world and ci.world.gameTime or 0
	local seen = probeSeen[key]
	if seen ~= nil and (seen.n >= 6 or now - seen.t < 20000) then return end
	probeSeen[key] = { n = (seen and seen.n or 0) + 1, t = now }
	local okL, list = pcall(transfsOutput.getUserTransfs, transfsOutput)
	if not okL or list == nil then print("[RunAroundHelper] PROBE " .. tostring(p.runaround_mdl) .. ": user transforms unreadable") return end
	local n = 0
	pcall(function() n = #list end)
	local parts, unread = {}, 0
	for k = 1, n do
		local e = list[k]
		local c = e and matrixCols(e.transf) or nil
		if c == nil then
			unread = unread + 1
		else
			local ident = math.abs(c[1][1] - 1) + math.abs(c[1][2]) + math.abs(c[2][2] - 1) + math.abs(c[3][3] - 1)
				+ math.abs(c[4][1]) + math.abs(c[4][2]) + math.abs(c[4][3])
			if ident > 1e-4 then
				parts[#parts + 1] = string.format("%d:%s %.2f,%.2f,%.2f %.1f", k, tostring(e.type), c[4][1], c[4][2], c[4][3],
					math.deg(atan2(c[1][2], c[1][1])))
			end
		end
	end
	print(string.format("[RunAroundHelper] PROBE %s carriage %s speed %.1f reversed %s: %d user transforms (%d unreadable), moved: %s",
		tostring(p.runaround_mdl), tostring(key), speed, tostring(ci.landVehicle and ci.landVehicle.reversed), n, unread,
		#parts > 0 and table.concat(parts, " | ") or "none"))
end

local function trainUpdateFn(_captureParams, params, transfsOutput)
	if params.currentInfo.landVehicle ~= nil then
		if hideIfFlagged(params, transfsOutput) then return end
		stockTrainUpdate(params, transfsOutput)
		pcall(probe, params, transfsOutput)
		return
	end
	return ghostUpdate(params, transfsOutput)
end

-- The stock tilting-train transformator (transformator_tiltingTrain.script.tl).
local function tiltingTrainUpdateFn(_captureParams, params, transfsOutput)
	if params.currentInfo.landVehicle == nil then
		return ghostUpdate(params, transfsOutput)
	end
	if hideIfFlagged(params, transfsOutput) then return end
	stockTrainUpdate(params, transfsOutput)
	local ci = params.currentInfo
	local tilt = transformator_util.calculateTilt(params.landVehicleApi, ci.vehicle.speed, 80.0, ci.landVehicle.reversed)
	transfsOutput:addAnimationState("tilt", -1, tilt * 5000, false, false) -- 5000: length of tilt.ani
end

local function clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- Smoke: the stock function for a vehicle; for a free entity, drift and size from
-- the ghost's state.
local function particleFn(captureParams, params, particleSystem)
	local ci = params.currentInfo
	if ci.vehicle ~= nil then
		if isHidden(ci.vehicle) then
			for i = 0, particleSystem:getSize() - 1 do particleSystem:setFrequencyScale(i, 0.0) end
			return
		end
		return transformator_util.updateParticleSystemFn(captureParams, params, particleSystem)
	end
	local st = stateOf(ci)
	if st == nil then return end
	local ef = clamp(st.power or 0.5, 0.25, 1.0)
	local velocity = api.type.Vec3f.new(st.vx or 0.0, st.vy or 0.0, 0.0)
	for i = 0, particleSystem:getSize() - 1 do
		particleSystem:setSizeScale01(i, ef, ef)
		particleSystem:setFrequencyScale(i, 1.0)
		particleSystem:setLifeTimeScale(i, ef)
		particleSystem:setVelocity(i, velocity)
	end
end

-- ---------------------------------------------------------------------------
-- Chaining: a vehicle with another mod's transformator (ghost_build points it at
-- res/models/runaround_ghost/chain.trf and keeps the original's name in
-- transformatorConfig.params.runaround_trf, which arrives here as
-- params.transformatorConfigParams). A hidden carriage is drawn as nothing and a
-- ghost driven as usual; anything else gets the original transformator, found
-- once per name and called as the game would. If it can't be found, the game's
-- own train animation stands in (said once), so a train always animates.
-- ---------------------------------------------------------------------------

-- The owner prefix of a resource name: devers_1:: for a mod's, :: for the game's.
local function ownerOf(res)
	return string.match(res, "^([%w_%-%.]*::)") or "::"
end

-- The folder of a resource name, with its trailing slash, without the owner.
local function folderOf(res)
	local path = string.gsub(res, "^[%w_%-%.]*::", "")
	return string.match(path, "^(.*/)") or "/"
end

-- Runs a resource file and returns what it defines: the table it returns, or the
-- result of the global data() it defines (the form of .trf files). This script's
-- own data is put back straight away.
local loaded = {} -- file -> table, or false
local function loadResource(file)
	if loaded[file] ~= nil then return loaded[file] or nil end
	local saved = data
	local ok, ret = pcall(ug_require, file)
	local defined = data
	data = saved
	local result = nil
	if ok and type(ret) == "table" then
		result = ret
	elseif ok and type(defined) == "function" and defined ~= saved then
		local okD, d = pcall(defined)
		if okD and type(d) == "table" then result = d end
	end
	loaded[file] = result or false
	return result
end

-- The files a ".trf" name can be: in full when it names its owner; "/path" in the
-- vehicle's mod, then the game; a bare name next to the vehicle's model.
local function trfFiles(name, modelName)
	local list
	if string.find(name, "::", 1, true) then
		list = { name }
	elseif string.sub(name, 1, 1) == "/" then
		list = { ownerOf(modelName) .. name, "::" .. name }
	else
		list = { ownerOf(modelName) .. folderOf(modelName) .. name }
	end
	for i, f in ipairs(list) do
		if not string.find(f, "%.lua$") then list[i] = f .. ".lua" end
	end
	return list
end

-- The function a transformator's "file@path.to.fn" names, the file relative to
-- the .trf's folder unless it names its owner; nil if not found.
local function scriptFunction(ref, trfFile)
	if type(ref) ~= "string" then return nil end
	local file, path = string.match(ref, "^(.-)@(.+)$")
	if file == nil then return nil end
	local bases
	if string.find(file, "::", 1, true) then
		bases = { file }
	elseif string.sub(file, 1, 1) == "/" then
		bases = { ownerOf(trfFile) .. file, "::" .. file }
	else
		bases = { ownerOf(trfFile) .. folderOf(trfFile) .. file }
	end
	for _, base in ipairs(bases) do
		for _, ext in ipairs({ ".lua", ".tl" }) do
			local t = loadResource(base .. ext)
			if type(t) == "table" then
				local fn = t
				for key in string.gmatch(path, "[^%.]+") do fn = type(fn) == "table" and fn[key] or nil end
				if type(fn) == "function" then return fn end
			end
		end
	end
	return nil
end

-- One of a transformator's hooks: its function and capture params, or nil.
local function hookOf(cfg, key, file)
	local h = type(cfg[key]) == "table" and cfg[key] or nil
	local fn = h and scriptFunction(h.fileName, file) or nil
	if fn == nil then return nil end
	return { fn = fn, capture = type(h.params) == "table" and h.params or {} }
end

-- The original transformator of a chained vehicle: { update, capture, particles,
-- particlesCapture, emittable, emitted }, or false when it can't be found (then
-- the stock one is used).
local origins = {}
local function originOf(params)
	local okP, name, modelName = pcall(function()
		local p = params.transformatorConfigParams
		return p.runaround_trf, p.runaround_mdl
	end)
	if not okP or type(name) ~= "string" then return false end
	local o = origins[name]
	if o ~= nil then return o end
	o = false
	for _, file in ipairs(trfFiles(name, tostring(modelName or ""))) do
		local cfg = loadResource(file)
		local us = type(cfg) == "table" and cfg.updateScript
		if type(us) == "table" then
			local update = scriptFunction(us.fileName, file)
			if update ~= nil then
				local ps = type(cfg.updateParticleSystemScript) == "table" and cfg.updateParticleSystemScript or nil
				o = {
					update = update,
					capture = type(us.params) == "table" and us.params or {},
					particles = ps and scriptFunction(ps.fileName, file) or nil,
					particlesCapture = ps and type(ps.params) == "table" and ps.params or {},
					emittable = hookOf(cfg, "getEmittableModelsScript", file),
					emitted = hookOf(cfg, "computeEmittedModelsScript", file),
				}
				break
			end
		end
	end
	if not o then
		print("[RunAroundHelper] chained transformator not found: " .. name .. " - the game's own train animation is used for it instead")
	end
	origins[name] = o
	return o
end

local function chainUpdateFn(_captureParams, params, transfsOutput)
	if params.currentInfo.landVehicle == nil then return ghostUpdate(params, transfsOutput) end
	if hideIfFlagged(params, transfsOutput) then return end
	local o = originOf(params)
	if o then return o.update(o.capture, params, transfsOutput) end
	return stockTrainUpdate(params, transfsOutput)
end

local function chainParticleFn(captureParams, params, particleSystem)
	local ci = params.currentInfo
	if ci.vehicle ~= nil and not isHidden(ci.vehicle) then
		local o = originOf(params)
		if o and o.particles then return o.particles(o.particlesCapture, params, particleSystem) end
	end
	return particleFn(captureParams, params, particleSystem)
end

-- The models the original may emit (the game asks this to know which to load):
-- always all of them, hidden or not.
local function chainEmittableFn(_captureParams, params)
	local o = originOf(params)
	if o and o.emittable then return o.emittable.fn(o.emittable.capture, params) end
	return {}
end

-- The models the original emits now. None while the vehicle is hidden (they
-- would stand at the platform with nothing under them). A ghost copy calls the
-- original too, guarded: another mod's script may expect vehicle data a free
-- entity doesn't have, and then the ghost simply shows none (said once).
local emitFailed = {}
local function chainEmittedFn(_captureParams, params, modelEmitter)
	local ci = params.currentInfo
	if ci ~= nil and ci.vehicle ~= nil and isHidden(ci.vehicle) then return end
	local o = originOf(params)
	if not (o and o.emitted) then return end
	if ci ~= nil and ci.vehicle ~= nil then return o.emitted.fn(o.emitted.capture, params, modelEmitter) end
	local ok, err = pcall(o.emitted.fn, o.emitted.capture, params, modelEmitter)
	if not ok then
		local name = tostring(params.transformatorConfigParams and params.transformatorConfigParams.runaround_trf)
		if not emitFailed[name] then
			emitFailed[name] = true
			print("[RunAroundHelper] " .. name .. " emits no extra models on a ghost copy: " .. tostring(err))
		end
	end
end

-- A stand-in params table: the same currentInfo with vehicle data on top.
local function withInfo(params, extra)
	return {
		currentInfo = setmetatable(extra, { __index = params.currentInfo }),
		previousInfo = params.previousInfo,
		entityId = params.entityId,
	}
end

-- The output, for a vehicle that must be silent. The game asserts that every
-- frame adds exactly one track per track of the sound set (simply not calling
-- the sound function crashed the game, live: AudioEmitterBackend "trackSrcs.size()
-- == soundTransfOutput.tracks.size()"). So the game's own function runs as usual
-- and this passes its tracks and continuous events on at zero gain, and drops its
-- one-off events (horn, doors).
local function silenced(out)
	return setmetatable({
		addTrack = function(_, _gain, pitch) return out:addTrack(0.0, pitch) end,
		addEvent = function(_, key, _gain, pitch) return out:addEvent(key, 0.0, pitch) end,
		triggerEvent = function() end,
	}, { __index = function(_, k)
		local v = out[k]
		if type(v) == "function" then return function(_, ...) return v(out, ...) end end
		return v
	end })
end

-- Sound: the game's own function; for a free entity it gets vehicle data built
-- from the ghost's state, so the loco sounds as a real one moving that way would.
local function updateSoundSet(captureParams, params, soundTransfOutput)
	if baseUpdateSoundSet == nil then return end
	local ci = params.currentInfo
	if ci.vehicle ~= nil then
		-- a hidden real loco (its copy is running around): silent, or its engine
		-- would be heard idling at the platform as well as the copy's
		if isHidden(ci.vehicle) then
			return baseUpdateSoundSet(captureParams, params, silenced(soundTransfOutput))
		end
		return baseUpdateSoundSet(captureParams, params, soundTransfOutput)
	end
	local cs = ci.customState
	local st = stateOf(ci) or {}
	local extra = {
		vehicle = {
			speed = st.speed or 0.0,
			speed01 = (cs and cs.speed01) or 0.0,
			power01 = (cs and cs.power01) or 0.0,
			power = st.power or 0.0,
		},
		railVehicle = {
			chuffStep = 1.5, -- metres per chuff: puts the steam idle/fast crossfade where a ghost runs
			weight = 1.0e6,  -- heavy, so the chuffs play at full gain
			sideForce = 0.0,
			maxSideForce = 1.0,
			brakeDecelSmoothed = 0.0,
			numAxles = 4,
			gameSpeedUp = 1.0,
		},
	}
	return baseUpdateSoundSet(captureParams, withInfo(params, extra), soundTransfOutput)
end

function data()
	return {
		sound = { updateSoundSet = updateSoundSet },
		train = { updateFn = trainUpdateFn, updateParticleSystemFn = particleFn },
		tiltingTrain = { updateFn = tiltingTrainUpdateFn, updateParticleSystemFn = particleFn },
		chain = {
			updateFn = chainUpdateFn,
			updateParticleSystemFn = chainParticleFn,
			getEmittableModelsFn = chainEmittableFn,
			computeEmittedModelsFn = chainEmittedFn,
		},
	}
end
