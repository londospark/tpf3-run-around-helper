--[[
	Runaround Railways - game script (TpF3)

	At a terminus configured in game (a "loop": line + stop + a few clicked route
	points), an arriving train's locomotive runs round its train instead of the
	game's instant flip:

	  1. detach: the loco part is swapped for an invisible stand-in of the same
	     length (a train with no powered part crashes the game), and a "ghost" -
	     a free entity drawn from the loco's own model where possible - appears
	     where the loco stood;
	  2. the ghost drives the planned route (reversing where the planner chose),
	     keeping its facing, with its own sound, smoke, wheels and paint (see
	     ghost_real.script.lua and ghost_build.script.lua);
	  3. the train is flipped with the game's own reverse command, so its head
	     faces the way out and the stand-in is at that end;
	  4. the ghost glides to the stand-in and the real loco replaces it, facing
	     the way the ghost faces; the train leaves.

	Things learned from the engine, which the code relies on:
	  - no commands from the OnArriveAtStop handler (mid-modification assert) and
	    no command callbacks inside update(): arrivals are queued, update() moves
	    the ghosts and returns what needs doing, postUpdate() sends the commands;
	  - vehicle configs must be real TransportVehicleConfig/Part objects, and parts
	    must match their model's compartments (see loadConfigsForModel);
	  - a vehicle replace that keeps the train's length leaves every carriage in
	    place; the flip mirrors the train about the middle of its length;
	  - carriage positions are reported late for a tick or two after a flip or a
	    replace, so nothing is decided from positions read straight after one;
	  - model metadata cannot be read with getAsTable from a game script (it can
	    in the load script); modelRep.get works.
]]

local CONFIG = {
	-- Log every vehicle arrival (vehicle/line/stop ids).
	LOG_ARRIVALS = true,
	-- Log carriage positions around each step of a run (for layout problems).
	LOG_TRACES = true,
	-- Kill switch for the whole run-around.
	detachEnabled = true,
	-- Flip the train (the game's own reverse command) before putting the loco back,
	-- so that the game does not flip it back to the buffer end at departure.
	reverseBeforeRecouple = true,
	-- Draw the ghost from the loco's own model when ghost_build.script.lua has
	-- wrapped it; otherwise (or when false) from a ghost copy.
	useRealModel = true,
	-- Use the ghost copies built at load time (loco's meshes, smoke, sound) rather
	-- than the plain silent copies shipped in res/models/runaround_ghost/.
	useEffectGhosts = true,
	-- Move the coaches along by the loco's length gradually while the loco is away,
	-- instead of in one jump. A vehicle replace keeps the MIDDLE of the train where
	-- it was (traced live: adding or removing length moves both ends by half of it),
	-- and the flip mirrors the train about that middle, so nothing but driving can
	-- move the middle. A real run-around moves the train's middle by a loco length
	-- (the loco ends up beyond the far coach), so the coaches have to shift by one
	-- loco length at some point. Here they creep there in 1 m steps: the stand-in
	-- in front of them shrinks while a second one behind them grows (same total
	-- length), the train is flipped when it is symmetrical (so the flip moves
	-- nothing), and the creep finishes on the other side. Only when the loco is
	-- the first part of the train.
	creepLayout = true,
	-- Better than the creep (and used instead when every coach can be shown): ghost
	-- copies of the loco AND the coaches are shown in their places, and the real
	-- coaches are HIDDEN (not removed: they stay in the train with their passengers
	-- and goods - passengers and cargo belong to the train, and taking coaches out
	-- lowers its capacity). They are hidden by a flag colour that the wrapped
	-- transformator (ghost_real.script.lua) turns into "draw nothing". Out of sight
	-- the train is rearranged and flipped, the ghost coaches glide to where the
	-- coaches end up, and the coaches get their own paint back under them. The
	-- game's vehicle marker only re-attaches three times.
	ghostRake = true,
	rakeSlideSpeed = 1.2, -- m/s at which the ghost coaches slide
	-- metres per creep step (a multiple of the stand-ins' 0.25 m), seconds between
	-- steps (0 = as fast as the game confirms them), and how far the loco drives
	-- before they start. Each step is a replace, so the game's vehicle marker above
	-- the train jitters while the coaches move; bigger steps mean fewer, larger ones.
	creepStep = 0.25,
	creepStepSeconds = 0.0,
	creepStartDistance = 30.0,
	-- Once the loco is back on, check its real facing against the ghost's and
	-- correct it if they differ (a safety net; see verifyRun).
	verifyFacing = true,

	-- Defaults for a newly added loop (editable per loop in the panel).
	defaultSpeed = 8.0,
	defaultAccel = 2.0,
}

local function logInfo(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	print("[RunAroundHelper] " .. table.concat(parts, " "))
end

local function loopLabel(loop)
	return loop.name or ("line=" .. tostring(loop.lineEntity) .. " stop=" .. tostring(loop.stopIndex))
end

-- Finds the configured loop matching an arrival event, or nil.
local function findLoopForArrival(loops, lineEntity, stopIndex)
	for _, loop in ipairs(loops) do
		if loop.lineEntity == lineEntity and loop.stopIndex == stopIndex then
			return loop
		end
	end
	return nil
end

local function findLoopById(loops, loopId)
	for _, loop in ipairs(loops) do
		if loop.id == loopId then
			return loop
		end
	end
	return nil
end

-- Loop ids must survive save/reload and stay deterministic, so the counter
-- lives in persistent state rather than a module-local variable.
local function newLoopId(data)
	data.nextLoopId = (data.nextLoopId or 1)
	local id = data.nextLoopId
	data.nextLoopId = id + 1
	return id
end

-- Finds the index (1-based) of the locomotive part inside a
-- TransportVehicleConfig.vehicles array by modelId.
local function findLocoIndex(tvc, loop)
	for i, tvp in ipairs(tvc.vehicles) do
		if tvp.part.modelId == loop.locoModelId then
			return i
		end
	end
	return nil
end

-- Index (into the train's parts) of the part standing nearest a world
-- position, or nil. Uses each carriage's model position; assumes the
-- CARRIAGE_LIST order matches the config's part order (unverified - the
-- result is logged so it can be checked).
local function nearestCarriageIndex(vehicleEntity, pos)
	local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
	if cl == nil then return nil end
	local best, bestD2 = nil, math.huge
	for i, carriageEntity in ipairs(cl.carriages) do
		local mil = api.engine.getComponent(carriageEntity, api.type.ComponentType.MODEL_INSTANCE_LIST)
		if mil ~= nil and mil.fatInstances[1] ~= nil then
			local c = mil.fatInstances[1].transf:cols(3)
			local d2 = (c.x - pos.x) ^ 2 + (c.y - pos.y) ^ 2
			if d2 < bestD2 then best, bestD2 = i, d2 end
		end
	end
	return best, math.sqrt(bestD2)
end

-- Vehicle configs handed to makeVehicleReplaceCmd must be real game objects
-- (api.type.TransportVehicleConfig / TransportVehiclePart), not plain tables:
-- a plain table was rejected with "bad argument ... (const
-- TransportVehicleConfig expected)". The base game either copies an existing
-- config with TransportVehicleConfig.new(existing) and re-lists its parts
-- (manager_window.tl, "duplicateVehicles") or builds parts with
-- TransportVehiclePart.new() and assigns the list (replace_vehicles.tl).

-- A part as plain data, safe to keep in the script state (which is saved with
-- the game) while the loco is away as a ghost.
local function snapshotPart(tvp)
	local loads = {}
	for i, lc in ipairs(tvp.part.compartment2loadConfig) do
		loads[i] = { loadConfigIndex = lc.loadConfigIndex, cargoTypeId = lc.cargoTypeId }
	end
	local autos = {}
	if tvp.autoLoadConfig ~= nil then
		for i, b in ipairs(tvp.autoLoadConfig) do autos[i] = b end
	end
	local color = nil
	local c = tvp.part.color
	if c ~= nil then color = { x = c.x, y = c.y, z = c.z } end
	return {
		modelId = tvp.part.modelId,
		reversed = tvp.part.reversed,
		color = color,
		loads = loads,
		autos = autos,
		purchaseTime = tvp.purchaseTime,
		maintenanceChange = tvp.maintenanceChange,
		maintenanceState = tvp.maintenanceState,
	}
end

-- One LoadConfig per compartment the MODEL declares, as the base game's
-- vehicle_util.makePart builds them. The game asserts that a part's load
-- configs match its model's compartments, so the COUNT always comes from the
-- model's metadata (a modded loco may declare more or fewer than the usual
-- one), never from a fixed number. Where the loco being put back had settings
-- for a compartment (which load config is selected, and its cargo type), they
-- are restored; anything the model has extra starts at load config 0.
local function loadConfigsForModel(modelId, savedLoads, savedAutos)
	local declared = nil
	local optionCounts = {} -- per compartment: how many load configs the model offers
	local ok, model = pcall(api.res.modelRep.get, modelId)
	if ok and model ~= nil then
		local okMeta, tvMeta = pcall(function() return model.metadata["transportVehicle"] end)
		if okMeta and tvMeta ~= nil then
			declared = 0
			for _, comp in ipairs(tvMeta.compartments) do
				declared = declared + 1
				local n = 0
				for _ in ipairs(comp.loadConfigs) do n = n + 1 end
				optionCounts[declared] = n
			end
		end
	end
	local count = declared or (savedLoads and #savedLoads) or 1
	if savedLoads ~= nil and declared ~= nil and #savedLoads ~= declared then
		logInfo("model", modelId, "declares", declared, "compartment(s) but the loco part had", #savedLoads, "- using the model's count")
	end
	local loads = {}
	for i = 1, count do
		local lc = api.type.LoadConfig.new()
		local saved = savedLoads and savedLoads[i]
		local index = saved and saved.loadConfigIndex or 0
		-- The game asserts 0 <= index < (number of load configs the model offers
		-- for this compartment); a saved index from another model can exceed it.
		if optionCounts[i] ~= nil and (index < 0 or index >= optionCounts[i]) then index = 0 end
		lc.loadConfigIndex = index
		if saved and saved.cargoTypeId ~= nil then
			pcall(function() lc.cargoTypeId = saved.cargoTypeId end)
		end
		loads[i] = lc
	end
	-- The game also asserts autoLoadConfig.size() == compartment2loadConfig.size()
	-- (vehicle_util_engine.cpp:352); a freshly created part has it empty.
	local autos = {}
	for i = 1, count do
		local saved = savedAutos and savedAutos[i]
		autos[i] = (saved == true)
	end
	return loads, autos
end

-- Rebuilds a real TransportVehiclePart from a snapshot (built the way
-- gui/line_vehicle_mgmt/vehicle_util.lua's makePart does it). Keeping
-- purchaseTime / maintenanceState means the loco keeps its age and condition.
local function partFromSnapshot(snap, reversed)
	local part = api.type.TransportVehiclePart.new()
	part.part.modelId = snap.modelId
	part.part.reversed = reversed
	local loads, autos = loadConfigsForModel(snap.modelId, snap.loads, snap.autos)
	part.part.compartment2loadConfig = loads
	part.autoLoadConfig = autos
	if snap.color ~= nil then
		part.part.color = api.type.Vec3f.new(snap.color.x, snap.color.y, snap.color.z)
	end
	part.purchaseTime = snap.purchaseTime
	part.maintenanceChange = snap.maintenanceChange
	part.maintenanceState = snap.maintenanceState
	return part
end

-- Puts a parts list into a config: every vehicle its own group (no multiple
-- units), no multiple-unit files.
local function finishConfig(config, parts)
	config.vehicles = parts
	local groups = {}
	for i = 1, #parts do groups[i] = 1 end
	config.vehicleGroups = groups
	config.muFileNames = {}
	return config
end

-- The invisible stand-in locos (res/models/runaround_standin/standin_cm<centimetres>.mdl,
-- 0.25 to 44 m in 0.25 m steps); the one nearest wantLength. Found by name
-- because a mod's resource prefix is not known in advance.
local standInIds = nil -- length in metres -> model id
local function findStandInModelId(wantLength)
	if standInIds == nil then
		standInIds = {}
		local ok, all = pcall(api.res.modelRep.getAll, true)
		if ok and all ~= nil then
			for id, name in pairs(all) do
				if type(name) == "string" then
					local cm = string.match(name, "runaround_standin/standin_cm(%d+)%.mdl")
					if cm then standInIds[tonumber(cm) / 100] = id end
				end
			end
		end
	end
	local bestLen, bestDiff = nil, nil
	for len in pairs(standInIds) do
		local d = math.abs(len - (wantLength or 12))
		if bestDiff == nil or d < bestDiff then bestLen, bestDiff = len, d end
	end
	if bestLen == nil then return nil end
	return standInIds[bestLen], bestLen
end

-- True for any of the stand-in models.
local function isStandIn(modelId)
	if standInIds == nil then findStandInModelId(12) end
	for _, id in pairs(standInIds or {}) do
		if id == modelId then return true end
	end
	return false
end

local function carriagePos(carriageEntity)
	local mil = api.engine.getComponent(carriageEntity, api.type.ComponentType.MODEL_INSTANCE_LIST)
	return mil.fatInstances[1].transf:cols(3)
end

-- A carriage's length, from the spacing of the carriages' centres (neighbouring
-- centres are half of one plus half of the other apart): model metadata is not
-- readable here. nil when the train is too short to tell.
local function carriageLength(vehicleEntity, idx)
	local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
	local n = #cl.carriages
	if n < 3 then return nil end
	local function gap(i, j)
		local a, b = carriagePos(cl.carriages[i]), carriagePos(cl.carriages[j])
		return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
	end
	if idx == 1 then return 2 * gap(1, 2) - gap(2, 3) end
	if idx == n then return 2 * gap(n, n - 1) - gap(n - 1, n - 2) end
	return nil
end

-- A value from a model's metadata, or nil (modelRep.get works in a game script).
local function modelMeta(modelId, ...)
	local keys = { ... }
	local ok, v = pcall(function()
		local cur = api.res.modelRep.get(modelId).metadata
		for _, k in ipairs(keys) do cur = cur[k] end
		return cur
	end)
	return ok and v or nil
end

-- A vehicle model's length along the track, from its metadata extent (what the
-- game butts vehicles together by: the BR 75's -6.42..6.19 m plus half a 23.39 m
-- coach is the 18.13 m between their centres seen live). nil if unreadable.
local function modelLength(modelId)
	local ext = modelMeta(modelId, "extent")
	local ok, len = pcall(function() return ext.bbMax.x - ext.bbMin.x end)
	if not ok or type(len) ~= "number" or len < 0.5 or len > 60 then return nil end
	return len
end

-- Ghost copies, used when the loco's own model cannot be: first the copy built at
-- load time from the loco itself (runaround_ghost_dyn/, with its smoke and sound),
-- then the plain silent copy of a base-game loco shipped with the mod
-- (runaround_ghost/), then a base-game loco of the same engine type.
local ghostIdsByFile = nil
local dynGhostIdsByFile = nil
local GHOST_FALLBACK = { STEAM = "mogul_2_6_0.mdl", ELECTRIC = "br_e94.mdl", DIESEL = "alco_hh600.mdl" }
-- Returns the ghost's model id and whether it is an effects ghost (smoke and
-- sound driven by the ghost's state, built at load time from the loco's own
-- model by ghost_build.script.lua, so it exists for modded locos too).
local function findGhostModelId(locoModelId)
	local okAll, all = pcall(api.res.modelRep.getAll, true)
	if not okAll or all == nil then return nil end
	if ghostIdsByFile == nil then
		ghostIdsByFile, dynGhostIdsByFile = {}, {}
		for id, name in pairs(all) do
			if type(name) == "string" then
				if string.find(name, "runaround_ghost_dyn/", 1, true) then
					dynGhostIdsByFile[string.match(name, "([^/]+)%.mdl$") or name] = id
				elseif string.find(name, "runaround_ghost/", 1, true) then
					ghostIdsByFile[string.match(name, "([^/]+)$")] = id
				end
			end
		end
	end
	local locoName = all[locoModelId]
	local file = type(locoName) == "string" and string.match(locoName, "([^/]+)$") or nil
	local base = file and string.match(file, "^(.*)%.mdl$") or nil
	if CONFIG.useEffectGhosts and base ~= nil and dynGhostIdsByFile[base] ~= nil then
		logInfo("ghost model: effects ghost (smoke and sound) for", locoName)
		return dynGhostIdsByFile[base], true
	end
	if file ~= nil and ghostIdsByFile[file] ~= nil then
		logInfo("ghost model: plain ghost (no effects) for", locoName)
		return ghostIdsByFile[file], false
	end
	local engineType = "DIESEL"
	local engType = modelMeta(locoModelId, "landVehicle", "engines", 1, "type")
	if engType ~= nil and GHOST_FALLBACK[tostring(engType)] then engineType = tostring(engType) end
	logInfo("ghost model: no ghost for", tostring(locoName), "- using the generic", engineType, "ghost")
	return ghostIdsByFile[GHOST_FALLBACK[engineType]], false
end

-- Whether the loco's own model can be used as the ghost: its sound set and
-- transformator must already point at the wrappers (ghost_build.script.lua does
-- that at load). If not, using it would raise Lua errors every frame ("attempt to
-- index local 'vehicleInfo'").
local realMarkers = nil -- set of model file names with a marker (the models do not change once loaded)
local function realModelReady(locoModelId)
	-- Model metadata cannot be read from a game script, so ghost_build.script.lua
	-- leaves a marker model, "runaround_ghost_real/<file>.mdl", for every loco whose
	-- sound set and transformator it has wrapped.
	local okAll, all = pcall(api.res.modelRep.getAll, true)
	if not okAll or all == nil then return false, "models not listable" end
	local locoName = all[locoModelId]
	local base = type(locoName) == "string" and string.match(locoName, "([^/]+)%.mdl$") or nil
	if base == nil then return false, "model name unknown" end
	if realMarkers == nil then
		realMarkers = {}
		for _, name in pairs(all) do
			local marked = type(name) == "string" and string.match(name, "runaround_ghost_real/(.+)%.mdl$")
			if marked then realMarkers[marked] = true end
		end
	end
	if realMarkers[base] then return true end
	return false, "its sound set or transformator was not wrapped at load"
end

-- The model a coach's ghost is drawn from, or nil if it cannot have one. It is the
-- coach's own model, and only when its transformator was wrapped at load: the same
-- wrapper is what hides the real coach while its ghost is shown, so a coach
-- without it could not be hidden either (the run then uses the creep instead).
local function coachGhostModel(coachModelId)
	if realModelReady(coachModelId) then return coachModelId end
	return nil
end

local function gameTimeMs()
	local ok, gt = pcall(function() return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime end)
	return ok and gt or nil
end

-- Starts a new motion segment for the wheel animation (see segmentDistance in
-- ghost_real.script.lua): from the distance travelled so far, speed v0,
-- acceleration acc (negative to brake), up to vmax.
local function startSegment(run, v0, acc, vmax)
	run.seg = { d0 = run.gdist or 0.0, v0 = v0, acc = acc, vmax = vmax, t0 = gameTimeMs() }
	run.segChanged = true
end

-- Sends the ghost its state (speed for sound and smoke, velocity for the smoke's
-- drift, the loco's paint, the motion segment for the wheels). Every tick while it
-- moves, now and then while it stands, and at once when the segment changes.
local function pushGhostState(run, speed, vx, vy, dt)
	if not run.effects then return end
	run.stateAge = (run.stateAge or 0.0) + dt
	local last = run.lastSpeed
	if not run.segChanged and last ~= nil and speed == 0.0 and last == 0.0 and run.stateAge < 1.0 then return end
	local speed01 = math.min(speed / (run.topSpeed or 27.8), 1.0)
	local power = math.min(0.25 + speed01, 1.0)
	-- which way the wheels turn: backwards when the ghost drives against its facing
	local backwards = (run.headingFlipped and 1 or 0) + (((run.yawOffset or 0) > 1) and 1 or 0)
	local ok, cmd = pcall(api.cmd.makeCustomEntityUpdateStateCmd, run.ghost, {
		speed01 = speed01,
		power01 = power,
		state = {
			speed = speed, power = power, vx = vx, vy = vy,
			color = run.color,
			dist = run.gdist or 0.0,
			seg = run.seg,
			dir = (backwards % 2 == 1) and -1 or 1,
		},
	})
	if ok then
		api.cmd.sendCommand(cmd)
		run.lastSpeed = speed
		run.stateAge = 0.0
		run.segChanged = false
	end
end

-- A real TransportVehiclePart for the stand-in.
local function makeStandInPart(standId, locoSnap)
	local part = api.type.TransportVehiclePart.new()
	part.part.modelId = standId
	part.part.reversed = false
	local loads, autos = loadConfigsForModel(standId, locoSnap.loads, locoSnap.autos)
	part.part.compartment2loadConfig = loads
	part.autoLoadConfig = autos
	part.purchaseTime = locoSnap.purchaseTime
	part.maintenanceChange = locoSnap.maintenanceChange
	part.maintenanceState = 1
	return part
end

-- Config with the locomotive swapped for the stand-in, in the same place, and
-- the wagons untouched. NOT with the loco simply removed: a consist with no
-- powered part cannot be drawn and crashes the game.
local function buildConfigWithStandIn(tvc, locoIdx, standId, locoSnap, addTail)
	local config = api.type.TransportVehicleConfig.new(tvc)
	local parts = {}
	for i, part in ipairs(config.vehicles) do
		if i == locoIdx then
			parts[#parts + 1] = makeStandInPart(standId, locoSnap)
		else
			parts[#parts + 1] = part
		end
	end
	if addTail then parts[#parts + 1] = makeStandInPart(standId, locoSnap) end -- see balanceWithTail
	return finishConfig(config, parts)
end

-- The creep layout (see creepLayout): the coaches in their current order, with
-- stand-ins of total length a in front (the head) and one of length b behind
-- (left out when 0). The front is always a fixed 0.5 m stand-in followed by the
-- rest of a: the head carriage then never moves while the coaches creep, so the
-- game's vehicle marker, which sits on it, stays still (it wiggled at every step
-- when the head stand-in itself was shrinking).
local CREEP_HEAD = 0.5
local function buildCreepConfig(tvc, a, b, locoSnap, skipIdx)
	local config = api.type.TransportVehicleConfig.new(tvc)
	local parts = {}
	parts[#parts + 1] = makeStandInPart(findStandInModelId(CREEP_HEAD), locoSnap)
	if a - CREEP_HEAD > 0.1 then parts[#parts + 1] = makeStandInPart(findStandInModelId(a - CREEP_HEAD), locoSnap) end
	for i, part in ipairs(config.vehicles) do
		-- skipIdx: the loco itself, at the detach (it is not a stand-in, so without
		-- this it stayed on the train and the ghost made a second loco, live)
		if i ~= skipIdx and not isStandIn(part.part.modelId) then parts[#parts + 1] = part end
	end
	if b > 0.1 then parts[#parts + 1] = makeStandInPart(findStandInModelId(b), locoSnap) end
	return finishConfig(config, parts)
end

-- Config with the stand-in(s) taken out and the real locomotive put back on the
-- train. A loco cannot pass through its consist, so it can only couple onto the
-- end it arrives at; which end that is comes from where the run finished (see
-- chooseAttachEnd), not from a setting. It then faces OUTWARD, away from the
-- wagons, so that it can pull them: a loco at the front of the parts list is
-- not reversed, one at the rear is.
--
-- origRev (the wagons' original reversed flags, in original order) is given
-- after a flip: the loco goes at the head and the wagons are re-listed in the
-- opposite order with their flags toggled, which is exactly the flip's mirror
-- undone, so every wagon ends up where it stood and facing as it did.
local function buildConfigWithLocoReattached(currentTvc, locoSnap, attachAtRear, standId, locoReversed, origRev)
	local config = api.type.TransportVehicleConfig.new(currentTvc)
	if locoReversed == nil then locoReversed = attachAtRear end
	local loco = partFromSnapshot(locoSnap, locoReversed)
	if origRev ~= nil then
		local wagons = {}
		for _, part in ipairs(config.vehicles) do
			if not isStandIn(part.part.modelId) then wagons[#wagons + 1] = part end
		end
		local parts = { loco }
		for i = #wagons, 1, -1 do
			local flag = origRev[i]
			if flag == nil then flag = wagons[i].part.reversed end
			wagons[i].part.reversed = not flag
			parts[#parts + 1] = wagons[i]
		end
		return finishConfig(config, parts)
	end
	local parts = {}
	if not attachAtRear then parts[1] = loco end
	for _, part in ipairs(config.vehicles) do
		if not isStandIn(part.part.modelId) then -- the stand-ins go away here
			parts[#parts + 1] = part
		end
	end
	if attachAtRear then parts[#parts + 1] = loco end
	return finishConfig(config, parts)
end

-- Reads the loco's current world transform off the live carriage entity,
-- before it gets replaced away. ASSUMES carriages[] is index-aligned with
-- transportVehicleConfig.vehicles - verify this the first time you run it.
local function captureLocoTransform(vehicleEntity, locoIdx)
	local carriageList = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
	local carriageEntity = carriageList.carriages[locoIdx]
	local mil = api.engine.getComponent(carriageEntity, api.type.ComponentType.MODEL_INSTANCE_LIST)
	local transf = mil.fatInstances[1].transf
	-- A copy: the component's matrix must not be read again after the consist is replaced.
	local okClone, copy = pcall(function() return transf:clone() end)
	return okClone and copy or transf
end

-- Samples an edge's geometry at N points to approximate its length, since
-- no explicit length field is exposed on Edge/EdgeGeometry.
local function estimateEdgeLength(geometry)
	local samples = 16
	local prev = api.engine.util.transport.calcPosition(geometry, 0.0)
	local total = 0.0
	for i = 1, samples do
		local t = i / samples
		local pos = api.engine.util.transport.calcPosition(geometry, t)
		total = total + api.type.Vec3f.distance(prev, pos)
		prev = pos
	end
	return total
end

local function getEdgeGeometry(edgeDef)
	local network = api.engine.getComponent(edgeDef.entity, api.type.ComponentType.TRANSPORT_NETWORK)
	local edge = network.edges[edgeDef.index + 1] -- Lua arrays are 1-based, edge indices are 0-based
	return edge.geometry
end

-- ---------------------------------------------------------------------
-- Route planning from clicked points.
--
-- The user clicks a few track pieces ("waypoints"); the route between them is
-- worked out with the game's own pathfinder (findPathNodeToNode, called the
-- same way mission_pathfinding_util.tl does). The pathfinder only finds
-- forward routes, so each pair of consecutive points is one "leg", and at
-- every intermediate point the planner may choose to REVERSE (loco stops and
-- sets back) at a small cost - that is how a run-around into a loop comes
-- out, and a wye simply shows up as an ordinary route through its junctions.
-- Directions of travel are chosen automatically (shortest total, reversals
-- penalised), because a click carries no direction.
-- ---------------------------------------------------------------------
local REVERSAL_PENALTY = 250.0 -- metres-equivalent cost of stopping to reverse at a click point
local REVERSAL_PAUSE = 1.5     -- seconds the ghost loco waits when it reverses
local CLEAR_M = 10.0          -- a reversal happens this far into the track piece, i.e. just clear of the points, not at the piece's end
local STATES = { { true, true }, { true, false }, { false, true }, { false, false } } -- {arrive dir, depart dir}

local function getTnEdge(entity, index)
	local tn = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_NETWORK)
	if tn == nil then return nil end
	return tn.edges[index + 1]
end

-- One {EdgeId, boolean} entry of a pathfinder result. The pair's runtime
-- shape is unconfirmed (a positional read of the same declared type failed
-- once for a component field), so try the plausible shapes.
local function unpackPathPair(pair)
	local shapes = {
		function() return pair[1], pair[2] end,
		function() return pair.edgeId, pair.dir end,
		function() return pair.first, pair.second end,
	}
	for _, fn in ipairs(shapes) do
		local ok, eid, dir = pcall(fn)
		if ok and eid ~= nil and eid.entity ~= nil and eid.index ~= nil and type(dir) == "boolean" then
			return eid, dir
		end
	end
	return nil
end

local function sameEdge(x, y)
	return x ~= nil and y ~= nil and x.entity == y.entity and x.index == y.index
end

local function sameNode(x, y)
	return x.entity == y.entity and x.index == y.index
end

-- Track pieces strictly between two nodes (empty if they are the same node),
-- as {entity,index,forward}; nil + message if there is no route.
local function pathBetweenNodes(startNode, destNode)
	if sameNode(startNode, destNode) then return {} end
	local ok, res = pcall(api.engine.util.pathfinding.findPathNodeToNode, { startNode }, { destNode }, { api.type.enum.TransportMode.TRAIN })
	if not ok then return nil, "pathfinder error: " .. tostring(res) end
	if #res == 0 then return nil, "no track route" end
	local out = {}
	for i = 1, #res do
		local eid, dir = unpackPathPair(res[i])
		if eid == nil then return nil, "unreadable pathfinder entry " .. i end
		out[#out + 1] = { entity = eid.entity, index = eid.index, forward = dir }
	end
	return out
end

local function dedupeEdges(raw)
	local out = {}
	for _, e in ipairs(raw) do
		local last = out[#out]
		if not (sameEdge(last, e) and last.forward == e.forward) then
			out[#out + 1] = e
		end
	end
	return out
end

local function exitNodeOf(eb, dB)
	return dB and eb.conns[2] or eb.conns[1]
end

-- The pathfinder is asked for a route to the far end of the target piece, so
-- it is the pathfinder that checks the junction turn onto that piece is
-- possible; the route must then actually finish along the piece in the
-- wanted direction.
local function endsAlong(edges, b, dB)
	local last = edges[#edges]
	return last ~= nil and sameEdge(last, b) and last.forward == dB
end

-- Edges to drive from waypoint a (leaving in direction dA) to waypoint b
-- (travelling along it in direction dB), both included. nil + message if no route.
local function legPath(a, dA, b, dB)
	local ea, eb = getTnEdge(a.entity, a.index), getTnEdge(b.entity, b.index)
	if ea == nil or eb == nil then return nil, "a clicked track piece no longer exists" end
	local startNode = dA and ea.conns[2] or ea.conns[1]
	local mid, err = pathBetweenNodes(startNode, exitNodeOf(eb, dB))
	if mid == nil then return nil, err end
	local raw = { { entity = a.entity, index = a.index, forward = dA } }
	for _, e in ipairs(mid) do raw[#raw + 1] = e end
	local out = dedupeEdges(raw)
	if not endsAlong(out, b, dB) then return nil, "no route along the clicked piece that way" end
	return out
end

-- Same, but starting from a track NODE (the station stop) rather than from a
-- clicked piece: the loco simply sets off from where it is standing.
local function legFromNode(startNode, b, dB)
	local eb = getTnEdge(b.entity, b.index)
	if eb == nil then return nil, "a clicked track piece no longer exists" end
	local mid, err = pathBetweenNodes(startNode, exitNodeOf(eb, dB))
	if mid == nil then return nil, err end
	local out = dedupeEdges(mid)
	if not endsAlong(out, b, dB) then return nil, "no route along the clicked piece that way" end
	return out
end

local function edgesCost(edges)
	local cost = 0
	for _, e in ipairs(edges) do
		cost = cost + estimateEdgeLength(getEdgeGeometry(e))
	end
	return cost
end

-- ---------------------------------------------------------------------
-- Finding a place to reverse when the clicks alone don't give one.
--
-- If two points can't be joined going forward, the loco has to stop and set
-- back somewhere on the way. A reversal happens ON a piece of track: the loco
-- drives to the end of piece C, stops, and drives back along C. So candidate
-- reversing pieces are found by asking the pathfinder for routes to nearby
-- track nodes (the last piece of each route is a candidate C), then routing
-- back from C to the target. The cheapest total wins. Nearby nodes come from
-- the same octree search the base game's missions use.
-- ---------------------------------------------------------------------
local CUSP_RADIUS = 300.0        -- metres around the source exit / target / stop
local CUSP_MAX_CANDIDATES = 100  -- pathfinder calls stay bounded

local function nodesNear(positions)
	local seen, out = {}, {}
	for _, pos in ipairs(positions) do
		if pos ~= nil then
			local ok, nodes = pcall(api.engine.util.octree.findTransportNetworkNodesInCircle, api.type.Vec2f.new(pos.x, pos.y), CUSP_RADIUS)
			if ok and nodes ~= nil then
				for i = 1, #nodes do
					local nd = nodes[i]
					local key = tostring(nd.entity) .. ":" .. tostring(nd.index)
					if not seen[key] then
						seen[key] = true
						out[#out + 1] = nd
					end
				end
			end
		end
	end
	return out
end

local function piecePos(edgeDef, t)
	return api.engine.util.transport.calcPosition(getEdgeGeometry(edgeDef), t)
end

-- firstEdges: pieces already driven to reach uNode. Returns the full list of
-- edges up to (not including) the target piece, or nil.
local function findCuspLeg(firstEdges, uNode, targetExitNode, b, dB, centres)
	local best, bestCost = nil, math.huge
	local tried = 0
	for _, v in ipairs(nodesNear(centres)) do
		if not sameNode(v, uNode) then
			tried = tried + 1
			if tried > CUSP_MAX_CANDIDATES then break end
			local p1 = pathBetweenNodes(uNode, v)
			if p1 ~= nil and #p1 > 0 then
				local c = p1[#p1]
				local ec = getTnEdge(c.entity, c.index)
				if ec ~= nil then
					local backNode = c.forward and ec.conns[1] or ec.conns[2]
					local p2 = pathBetweenNodes(backNode, targetExitNode)
					if p2 ~= nil and endsAlong(p2, b, dB) then
						local raw = {}
						for _, e in ipairs(firstEdges) do raw[#raw + 1] = e end
						for _, e in ipairs(p1) do raw[#raw + 1] = e end
						raw[#raw + 1] = { entity = c.entity, index = c.index, forward = not c.forward }
						for _, e in ipairs(p2) do raw[#raw + 1] = e end
						local cost = edgesCost(raw) + REVERSAL_PENALTY
						if cost < bestCost then best, bestCost = raw, cost end
					end
				end
			end
		end
	end
	return best
end

-- Best route through all waypoints, or nil + message. If startNode is given
-- the route begins there (the stop the train is standing at), so the first
-- waypoint can be the reversing point itself.
-- Returns route (list of {entity,index,forward[,reversal]}), info {length, reversals}.
-- Direct route from piece a to piece b, or, if there is none, one with an
-- automatically chosen reversing place.
local function legPathAuto(a, dA, b, dB)
	local edges, err = legPath(a, dA, b, dB)
	if edges ~= nil then return edges end
	local ea, eb = getTnEdge(a.entity, a.index), getTnEdge(b.entity, b.index)
	if ea == nil or eb == nil then return nil, err end
	local uNode = dA and ea.conns[2] or ea.conns[1]
	local first = { { entity = a.entity, index = a.index, forward = dA } }
	local raw = findCuspLeg(first, uNode, exitNodeOf(eb, dB), b, dB, { piecePos(first[1], dA and 1.0 or 0.0), piecePos(b, 0.5) })
	if raw == nil then return nil, err end
	return dedupeEdges(raw)
end

local function legFromNodeAuto(startNode, startPos, b, dB)
	local edges, err = legFromNode(startNode, b, dB)
	if edges ~= nil then return edges end
	local eb = getTnEdge(b.entity, b.index)
	if eb == nil then return nil, err end
	local raw = findCuspLeg({}, startNode, exitNodeOf(eb, dB), b, dB, { startPos, piecePos(b, 0.5) })
	if raw == nil then return nil, err end
	return dedupeEdges(raw)
end

local function planRoute(waypoints, startNode, startPos)
	local n = #waypoints
	if n < 2 then return nil, "need at least 2 points" end

	local memo = {}
	local function leg(i, d, a)
		local key = i .. ":" .. tostring(d) .. ":" .. tostring(a)
		local m = memo[key]
		if m == nil then
			local edges, err = legPathAuto(waypoints[i], d, waypoints[i + 1], a)
			m = { edges = edges, cost = edges and edgesCost(edges) or math.huge, err = err }
			memo[key] = m
		end
		return m
	end
	local function leg0(a)
		local key = "0:" .. tostring(a)
		local m = memo[key]
		if m == nil then
			local edges, err = legFromNodeAuto(startNode, startPos, waypoints[1], a)
			m = { edges = edges, cost = edges and edgesCost(edges) or math.huge, err = err }
			memo[key] = m
		end
		return m
	end

	local best, from = { {} }, {}
	for s, st in ipairs(STATES) do
		local a, d = st[1], st[2]
		if startNode ~= nil then
			local l = leg0(a)
			best[1][s] = (l.cost < math.huge) and (l.cost + ((a ~= d) and REVERSAL_PENALTY or 0)) or math.huge
		else
			best[1][s] = (a == d) and 0 or math.huge -- no arrival at the first point
		end
	end
	for i = 2, n do
		best[i], from[i] = {}, {}
		for s, st in ipairs(STATES) do
			local a, d = st[1], st[2]
			if i == n and a ~= d then
				best[i][s] = math.huge -- departure at the last point is meaningless
			else
				local penalty = (a ~= d) and REVERSAL_PENALTY or 0
				local bestCost, bestPrev = math.huge, nil
				for ps, pst in ipairs(STATES) do
					if best[i - 1][ps] < math.huge then
						local l = leg(i - 1, pst[2], a)
						if l.cost < math.huge then
							local c = best[i - 1][ps] + l.cost + penalty
							if c < bestCost then bestCost, bestPrev = c, ps end
						end
					end
				end
				best[i][s], from[i][s] = bestCost, bestPrev
			end
		end
	end

	local endState, endCost = nil, math.huge
	for s = 1, #STATES do
		if best[n][s] < endCost then endState, endCost = s, best[n][s] end
	end
	if endState == nil then
		-- Say which pair of points cannot be joined, to make the message useful.
		if startNode ~= nil then
			local any, lastErr = false, "no track route"
			for _, as in ipairs({ true, false }) do
				local l = leg0(as)
				if l.cost < math.huge then any = true else lastErr = l.err or lastErr end
			end
			if not any then return nil, "from the station stop to point 1: " .. lastErr end
		end
		for i = 1, n - 1 do
			local any, lastErr = false, "no track route"
			for _, ds in ipairs({ true, false }) do
				for _, as in ipairs({ true, false }) do
					local l = leg(i, ds, as)
					if l.cost < math.huge then any = true else lastErr = l.err or lastErr end
				end
			end
			if not any then
				return nil, "point " .. i .. " to point " .. (i + 1) .. ": " .. lastErr
			end
		end
		return nil, "no consistent route through these points"
	end

	local chosen = { [n] = endState }
	for i = n, 2, -1 do chosen[i - 1] = from[i][chosen[i]] end

	local route, reversals = {}, 0
	local function append(edges)
		for _, e in ipairs(edges) do
			local last = route[#route]
			if sameEdge(last, e) then
				if last.forward ~= e.forward then
					-- Same track piece taken again the other way round: the loco stops and reverses here.
					route[#route + 1] = { entity = e.entity, index = e.index, forward = e.forward, reversal = true }
					reversals = reversals + 1
				end
			else
				route[#route + 1] = { entity = e.entity, index = e.index, forward = e.forward }
			end
		end
	end
	if startNode ~= nil then
		append(leg0(STATES[chosen[1]][1]).edges)
	end
	for i = 1, n - 1 do
		append(leg(i, STATES[chosen[i]][2], STATES[chosen[i + 1]][1]).edges)
	end
	return route, { length = endCost, reversals = reversals }
end

-- The track node where trains stop at a line's stop, or nil. Resolved the way
-- the base game's line_util.tl does: line -> stop -> station group -> station
-- -> terminal.vehicleNodeId (raw Line component indices are zero-based).
local function getStopNode(lineEntity, stopIndex)
	if lineEntity == nil or stopIndex == nil then return nil end
	local line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE)
	local stop = line and line.stops[stopIndex + 1]
	if stop == nil then return nil end
	local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
	local stationEntity = group and group.stations[stop.station + 1]
	if stationEntity == nil then return nil end
	local station = api.engine.getComponent(stationEntity, api.type.ComponentType.STATION)
	local terminal = station and station.terminals[stop.terminal + 1]
	if terminal == nil then return nil end
	-- A position on the platform, for centring the reversal search.
	local pos = nil
	local ok, res = pcall(function()
		local ep = terminal.vehicleEdges[1]
		return piecePos({ entity = ep.edgeId.entity, index = ep.edgeId.index }, ep.param)
	end)
	if ok then pos = res end
	return terminal.vehicleNodeId, pos
end

-- Rebuilds loop.loopEdges from loop.waypoints and records a one-line status
-- for the panel. Never throws.
local function recomputeLoopRoute(loop)
	loop.waypoints = loop.waypoints or {}
	loop.routeLength, loop.routePieces, loop.routeReversals = nil, nil, nil
	if #loop.waypoints < 2 then
		loop.loopEdges = {}
		loop.pathStatus = (#loop.waypoints == 0) and "no points yet" or "1 point - click at least one more (the reversing point, then the loop)"
		return
	end
	local okNode, startNode, startPos = pcall(getStopNode, loop.lineEntity, loop.stopIndex)
	if not okNode or startNode == nil then
		logInfo("could not find the stop's track node for loop", loopLabel(loop), "- planning from the first point instead:", tostring(startNode))
		startNode = nil
	end
	local ok, route, info = pcall(planRoute, loop.waypoints, startNode, startPos)
	if not ok then
		loop.loopEdges = {}
		loop.pathStatus = "route error: " .. tostring(route)
		logInfo("route planning error for loop", loopLabel(loop), tostring(route))
		return
	end
	if route == nil then
		loop.loopEdges = {}
		loop.pathStatus = "no route - " .. tostring(info)
		logInfo("no route for loop", loopLabel(loop), "-", tostring(info))
		return
	end
	loop.loopEdges = route
	-- The planner's cost includes a penalty per reversal; the real length is the
	-- sum of the pieces (reversal pieces are driven back over, so they count).
	local length = 0.0
	for _, e in ipairs(route) do
		local okL, len = pcall(function() return estimateEdgeLength(getEdgeGeometry(e)) end)
		if okL then length = length + len end
	end
	info.length = length
	loop.routeLength = length
	loop.routePieces = #route
	loop.routeReversals = info.reversals
	loop.pathStatus = string.format("%d points, %d track pieces, %d reversal(s), about %d m", #loop.waypoints, #route, info.reversals, math.floor(info.length))
	logInfo("route for loop", loopLabel(loop), "-", loop.pathStatus)
end

-- Where along the route the real loco is standing, so the ghost can start
-- there instead of at the route's first piece (which is the stop's track node,
-- about the middle of the platform). Looks along the route up to its first
-- reversal (the loco stands on that first leg) for the point nearest the loco:
-- limiting it to the first 8 pieces missed a loco standing further along, so
-- the ghost started a few metres from it, towards the wagons. Returns the piece
-- number, the metres already covered on it, and the distance from the loco to
-- that point; nil if the route has no pieces.
local function locateOnRoute(loop, pos)
	local edges = loop.loopEdges
	if edges == nil or #edges == 0 then return nil end
	local calc = api.engine.util.transport.calcPosition
	local bestK, bestS, bestD2 = nil, 0, math.huge
	for k = 1, math.min(#edges, 120) do
		local edgeDef = edges[k]
		if edgeDef.reversal then break end
		do
			local ok, geometry = pcall(getEdgeGeometry, edgeDef)
			if ok then
				local len = estimateEdgeLength(geometry)
				local steps = math.max(20, math.min(400, math.floor(len))) -- about one sample a metre
				for i = 0, steps do
					local along = i / steps -- fraction of the way travelled
					local u = edgeDef.forward and along or (1.0 - along)
					local p = calc(geometry, u)
					local d2 = (p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2
					if d2 < bestD2 then bestK, bestS, bestD2 = k, along * len, d2 end
				end
			end
		end
	end
	if bestK == nil then return nil end
	return bestK, bestS, math.sqrt(bestD2)
end

-- Where the loco goes back on after the creep: the stand-in left on the train,
-- found by its model (not by list position, which misled the ghost into
-- driving back through the coaches, live).
local function readStandInPosition(vehicleEntity, awayFrom)
	-- Every stand-in carriage with its length; the far end's ones (after the creep
	-- there are only the front ones, 0.5 m + the rest) give the loco's centre as
	-- their length-weighted centre.
	local found = {}
	pcall(function()
		local lengthOf = {}
		for len, id in pairs(standInIds or {}) do lengthOf[id] = len end
		local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
		for _, c in ipairs(cl.carriages) do
			local mil = api.engine.getComponent(c, api.type.ComponentType.MODEL_INSTANCE_LIST)
			local inst = mil.fatInstances[1]
			if isStandIn(inst.modelId) then
				local p = inst.transf:cols(3)
				local d = awayFrom and math.sqrt((p.x - awayFrom.x) ^ 2 + (p.y - awayFrom.y) ^ 2) or 0
				found[#found + 1] = { x = p.x, y = p.y, z = p.z, d = d, len = lengthOf[inst.modelId] or 1 }
			end
		end
	end)
	if #found == 0 then return nil end
	local far = 0
	for _, f in ipairs(found) do if f.d > far then far = f.d end end
	local sx, sy, sz, sw = 0, 0, 0, 0
	for _, f in ipairs(found) do
		if f.d > far - 30 then -- the far end's stand-ins
			sx, sy, sz, sw = sx + f.x * f.len, sy + f.y * f.len, sz + f.z * f.len, sw + f.len
		end
	end
	return { x = sx / sw, y = sy / sw, z = sz / sw }
end

-- The route is done: with the flip enabled the train is flipped next and the
-- ghost then glides to where the loco goes back on; without it, the run ends.
local function routeFinished(run)
	if (run.layout ~= nil or run.rake ~= nil) and run.phase == nil then
		run.phase = "waitLayout"
		run.speed = 0.0
		startSegment(run, 0.0, 0.0, 0.0)
		pushGhostState(run, 0.0, 0.0, 0.0, 0.0)
		return false
	end
	if CONFIG.reverseBeforeRecouple and run.phase == nil then
		run.phase = "flip"
		run.speed = 0.0
		startSegment(run, 0.0, 0.0, 0.0)
		pushGhostState(run, 0.0, 0.0, 0.0, 0.0)
		return false
	end
	return true
end

-- Glide in a straight line to run.target (the flipped stand-in: where the loco
-- goes back on), braking evenly to a stop there. The facing stays as it was.
local function advanceApproach(run, dt)
	local dx, dy, dz = run.target.x - run.gx, run.target.y - run.gy, run.target.z - run.gz
	local dist = math.sqrt(dx * dx + dy * dy)
	if run.approachDecel == nil then
		-- Set off at the route speed and brake at a constant rate to stop at the
		-- stand-in (the wheel animation follows the same motion).
		local v0 = math.max(run.loopSpeed or CONFIG.defaultSpeed, 1.0)
		run.approachDecel = (dist > 0.1) and (v0 * v0 / (2.0 * dist)) or 1.0
		run.speed = v0
		startSegment(run, v0, -run.approachDecel, 0.0)
	end
	local speed = math.max(math.sqrt(2.0 * run.approachDecel * dist), 0.5)
	local step = speed * dt
	local arrived = step >= dist
	local f = arrived and 1.0 or (step / dist)
	run.gx, run.gy, run.gz = run.gx + dx * f, run.gy + dy * f, run.gz + dz * f
	run.gdist = (run.gdist or 0.0) + (arrived and dist or step)
	run.speed = arrived and 0.0 or speed
	local vx = (dist > 0) and dx / dist * run.speed or 0.0
	local vy = (dist > 0) and dy / dist * run.speed or 0.0
	pushGhostState(run, run.speed, vx, vy, dt)
	local transf = api.type.Mat4f.rotZTransl(run.gyaw, api.type.Vec3f.new(run.gx, run.gy, run.gz))
	api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(run.ghost, transf))
	if arrived then run.phase = "finish" end
	return false
end

-- Where the flipped train's head part (the stand-in) is, or nil.
local function readHeadPosition(vehicleEntity)
	local ok, c = pcall(function()
		local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
		return carriagePos(cl.carriages[1])
	end)
	if ok then return { x = c.x, y = c.y, z = c.z } end
	return nil
end

-- Advances one run by dt seconds. Returns true when the run needs its next
-- step done in postUpdate (recouple, or the facing check after it).
local function advanceGhost(run, dt)
	local loop = run.loop
	if run.phase == "flip" then return false end -- waiting for the train to be flipped
	if run.phase == "settle" then
		-- Just after a flip the carriages still report their old positions for a
		-- tick or two: wait, then read where the stand-in (now the head) is.
		run.settleTicks = (run.settleTicks or 0) + 1
		if run.settleTicks >= 4 then
			run.target = readHeadPosition(run.vehicleEntity)
			-- (the loco's centre goes where the stand-in's is: a replace keeps the centre
			-- of the front part fixed)
			if run.target ~= nil then
				run.phase = "approach"
				logInfo(string.format("ghost heading for the flipped stand-in at %.1f, %.1f", run.target.x, run.target.y))
			else
				logInfo("could not read the stand-in's position after the flip - the loco goes straight back on")
				run.phase = "finish"
			end
		end
		return false
	end
	if run.phase == "waitLayout" and run.rake ~= nil then
		if run.rake.stage == "done" and run.target ~= nil then
			logInfo(string.format("ghost heading for the loco's place at %.1f, %.1f", run.target.x, run.target.y))
			run.phase = "approach"
		elseif run.rake.stage == "failed" then
			logInfo("ghost rake failed - putting the real train back where it is")
			run.phase = "finish"
		end
		return false
	end
	if run.phase == "waitLayout" then
		local L = run.layout
		if L.stage == "done" or (L.stage == "failed" and run.flipped) then
			run.target = readStandInPosition(run.vehicleEntity, run.locoPos)
			if run.target ~= nil then
				logInfo(string.format("ghost heading for the stand-in at %.1f, %.1f", run.target.x, run.target.y))
				run.phase = "approach"
			else
				run.phase = "finish"
			end
		elseif L.stage == "failed" then
			run.layout = nil -- not flipped: the plain way (flip now)
			run.phase = nil
			return routeFinished(run)
		end
		return false
	end
	if run.phase == "approach" then return advanceApproach(run, dt) end
	if run.phase == "verify" then
		run.verifyWait = (run.verifyWait or 0) + 1
		return run.verifyWait >= 4
	end
	if run.phase == "done" or run.phase == "finish" then return true end
	if run.edgeCursor > #loop.loopEdges then
		return routeFinished(run)
	end

	-- Waiting at a reversal point (the loco changing direction).
	if run.pause ~= nil and run.pause > 0 then
		run.pause = run.pause - dt
		run.speed = 0.0
		if run.seg == nil or run.seg.acc ~= 0.0 or run.seg.v0 ~= 0.0 then startSegment(run, 0.0, 0.0, 0.0) end
		pushGhostState(run, 0.0, 0.0, 0.0, dt)
		return false
	end

	local edgeDef = loop.loopEdges[run.edgeCursor]
	if run.edgeLength == nil then
		if edgeDef.reversal and not run.reversalDone then
			run.reversalDone = true
			run.headingFlipped = not run.headingFlipped
			run.pause = REVERSAL_PAUSE
			run.speed = 0.0
			startSegment(run, 0.0, 0.0, 0.0)
			pushGhostState(run, 0.0, 0.0, 0.0, 0.0)
			return false
		end
		run.edgeLength = estimateEdgeLength(getEdgeGeometry(edgeDef))
		run.edgeProgress = run.startOffset or 0.0
		run.startOffset = nil
		-- A piece that is about to be driven back over (a reversal) is only
		-- driven far enough to clear the points, not to its far end.
		run.edgeLimit = nil
		local nextDef = loop.loopEdges[run.edgeCursor + 1]
		if nextDef ~= nil and nextDef.reversal and sameEdge(nextDef, edgeDef) and run.edgeLength > CLEAR_M * 1.5 then
			run.edgeLimit = math.max(CLEAR_M, run.edgeProgress + 1.0)
		end
	end

	-- Setting off (at the start, or after a reversal): a new motion segment.
	if run.speed == 0.0 and (run.seg == nil or run.seg.acc == 0.0) then
		startSegment(run, 0.0, loop.accel, loop.speed)
	end
	run.speed = math.min(loop.speed, run.speed + loop.accel * dt)
	local endAt = run.edgeLimit or run.edgeLength
	local before = run.edgeProgress
	run.edgeProgress = math.min(run.edgeProgress + run.speed * dt, endAt)
	local t = run.edgeLength > 0 and math.min(run.edgeProgress / run.edgeLength, 1.0) or 1.0

	-- Position along the piece's geometry (u runs start -> end); travel is
	-- towards u = 1 when forward, u = 0 when not. Heading comes from two
	-- nearby points so it stays defined at the very ends of a piece.
	local geometry = getEdgeGeometry(edgeDef)
	local forward = edgeDef.forward
	local u = forward and t or (1.0 - t)
	local calc = api.engine.util.transport.calcPosition
	local pos = calc(geometry, u)
	local pa = calc(geometry, math.max(0.0, u - 0.02))
	local pb = calc(geometry, math.min(1.0, u + 0.02))
	local dx, dy = pb.x - pa.x, pb.y - pa.y
	if not forward then dx, dy = -dx, -dy end
	local travelYaw = math.atan2(dy, dx)
	-- The ghost starts facing exactly as the real loco did (yawOffset is 0 or
	-- half a turn, fixed on the first step) and keeps that facing through
	-- every reversal: a loco that reverses does not turn round.
	if run.yawOffset == nil then
		run.yawOffset = 0.0
		if run.locoYaw ~= nil then
			local diff = math.atan2(math.sin(run.locoYaw - travelYaw), math.cos(run.locoYaw - travelYaw))
			run.yawOffset = (math.abs(diff) > math.pi / 2) and math.pi or 0.0
			logInfo(string.format("ghost facing: %s the first direction of travel", run.yawOffset == 0.0 and "along" or "against"))
		end
	end
	local yaw = travelYaw + run.yawOffset
	if run.headingFlipped then
		yaw = yaw + math.pi -- driving backwards: the loco keeps facing the way it faced
	end
	local transf = api.type.Mat4f.rotZTransl(yaw, pos)
	local pvx, pvy = 0.0, 0.0
	if run.gx ~= nil and dt > 0 then pvx, pvy = (pos.x - run.gx) / dt, (pos.y - run.gy) / dt end
	if not run.firstLogged and run.locoPos ~= nil then
		run.firstLogged = true
		logInfo(string.format("ghost first step %.1f m from where the loco stood", math.sqrt((pos.x - run.locoPos.x) ^ 2 + (pos.y - run.locoPos.y) ^ 2)))
	end
	run.gx, run.gy, run.gz, run.gyaw = pos.x, pos.y, pos.z, yaw
	run.gdist = (run.gdist or 0.0) + (run.edgeProgress - before)
	run.loopSpeed = loop.speed
	pushGhostState(run, run.speed, pvx, pvy, dt)

	api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(run.ghost, transf))

	if run.edgeProgress >= endAt then
		if run.edgeLimit ~= nil then
			run.startOffset = run.edgeLength - run.edgeLimit -- drive back from here
		end
		run.edgeCursor = run.edgeCursor + 1
		run.edgeLength = nil
		run.reversalDone = false
	end

	if run.edgeCursor > #loop.loopEdges then
		return routeFinished(run)
	end
	return false
end

-- Lets a train that was held for a run-around go again. Used on every failure
-- path so a problem here never leaves a train stuck at the station.
local function releaseTrain(vehicleEntity)
	api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(vehicleEntity, false))
	pcall(function() api.cmd.sendCommand(api.cmd.makeVehicleSetStoppedByUserCmd(vehicleEntity, false)) end)
end

-- Keeps the train where it is. Sent again after every flip and replace: after a
-- flip the train crept 18 m towards the exit on its two 1 kW stand-ins before the
-- loco came back (traced live).
local function holdTrain(vehicleEntity)
	api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(vehicleEntity, true))
	pcall(function() api.cmd.sendCommand(api.cmd.makeVehicleSetStoppedByUserCmd(vehicleEntity, true)) end)
end

-- True to attach at the rear (last part) of the consist, false for the front
-- (first part): whichever end is nearer the last route point the user clicked,
-- since that is where the loco has just arrived. Also returns a description
-- for the log.
local function chooseAttachEnd(vehicleEntity, loop, tvc, standId)
	local last = loop.waypoints and loop.waypoints[#loop.waypoints]
	if last == nil then return true, "no route points recorded, defaulting to the rear" end
	local pos = piecePos(last, 0.5)
	local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
	if cl == nil or #cl.carriages == 0 then return true, "no carriages found, defaulting to the rear" end
	local function distTo(i)
		local mil = api.engine.getComponent(cl.carriages[i], api.type.ComponentType.MODEL_INSTANCE_LIST)
		local c = mil.fatInstances[1].transf:cols(3)
		return math.sqrt((c.x - pos.x) ^ 2 + (c.y - pos.y) ^ 2)
	end
	-- The stand-in sits where the loco used to be and is about to be removed,
	-- so the ends that matter are those of the wagons.
	local first, last = nil, nil
	for i, part in ipairs(tvc.vehicles) do
		if part.part.modelId ~= standId then
			first = first or i
			last = i
		end
	end
	if first == nil or cl.carriages[first] == nil or cl.carriages[last] == nil then
		return true, "could not tell the wagons apart, defaulting to the rear"
	end
	local dFront, dRear = distTo(first), distTo(last)
	local atRear = dRear <= dFront
	return atRear, string.format("nearest the last route point: front end %d m away, rear end %d m away", math.floor(dFront), math.floor(dRear))
end

-- Puts the real loco back. attachAtRear/why say where (see chooseAttachEnd).
-- Position log of a train's carriages, to find out how the game lays a train out
-- after each vehicle replace / flip (used to work out why wagons jumped).
local function traceNow(label, vehicleEntity)
	if not CONFIG.LOG_TRACES then return end
	local ok, err = pcall(function()
		local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
		local parts = {}
		for i, c in ipairs(cl.carriages) do
			local mil = api.engine.getComponent(c, api.type.ComponentType.MODEL_INSTANCE_LIST)
			local t = mil.fatInstances[1].transf:cols(3)
			parts[#parts + 1] = string.format("%d=(%.1f,%.1f)", i, t.x, t.y)
		end
		logInfo("trace", label, table.concat(parts, " "))
	end)
	if not ok then logInfo("trace", label, "unreadable:", tostring(err)) end
end

-- Logs the positions after some ticks (the game lays carriages out a tick or two late).
local function scheduleTrace(state, label, vehicleEntity, ticks)
	if not CONFIG.LOG_TRACES then return end
	local data = state:get()
	data.traces = data.traces or {}
	data.traces[#data.traces + 1] = { label = label, vehicleEntity = vehicleEntity, ticks = ticks }
	state:set(data)
end

-- Ends a run: the ghost goes, the train is released.
local function finalizeRun(run)
	if not run.ghostGone then api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost)) end
	releaseTrain(run.vehicleEntity)
	if not run.noDepartNow then api.cmd.sendCommand(api.cmd.makeVehicleTryToDepartCmd(run.vehicleEntity)) end
	logInfo("run-around complete for vehicle", run.vehicleEntity, "loop", loopLabel(run.loop))
end

local function recouple(state, run, tv, atRear, locoReversed, why, origRev)
	logInfo("recouple: removing the stand-in and attaching the loco at the", atRear and "REAR" or "FRONT", "of the consist,", locoReversed and "reversed" or "not reversed", "-", why)

	local okBuild, newConfig = pcall(buildConfigWithLocoReattached, tv.transportVehicleConfig, run.locoPart, atRear, run.standInModelId, locoReversed, origRev)
	if not okBuild then
		-- The ghost is deliberately left in place: it is the only copy of the loco.
		logInfo("recouple FAILED - could not build the new consist:", tostring(newConfig), "- loco ghost left in place, train released")
		releaseTrain(run.vehicleEntity)
		return
	end
	local okCmd, cmd = pcall(api.cmd.makeVehicleReplaceCmd, run.vehicleEntity, newConfig)
	if not okCmd then
		logInfo("recouple FAILED - replace command rejected:", tostring(cmd), "- loco ghost left in place, train released")
		releaseTrain(run.vehicleEntity)
		return
	end

	api.cmd.sendCommand(cmd, function(_, success)
		if not success then
			logInfo("recouple replaceVehicle FAILED for vehicle", run.vehicleEntity, "loop", loopLabel(run.loop), "- loco ghost left in place, train released")
			releaseTrain(run.vehicleEntity)
			return
		end
		scheduleTrace(state, "after the recouple (+1 tick)", run.vehicleEntity, 1)
		scheduleTrace(state, "after the recouple (+3 ticks)", run.vehicleEntity, 3)
		-- The ghost goes at once: the real loco is on the train now, and leaving the
		-- ghost up while the facing is verified showed two locos for a moment.
		api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost))
		run.ghostGone = true
		if CONFIG.verifyFacing and run.gyaw ~= nil then
			-- Keep the run (and the ghost) for a few ticks so the new carriages exist,
			-- then compare the loco's real facing with the ghost's (verifyRun).
			run.phase = "verify"
			run.verifyWait = 0
			run.locoAtRear = atRear
			local data = state:get()
			data.runs[#data.runs + 1] = run
			state:set(data)
		else
			finalizeRun(run)
		end
	end)
end

-- Unit vector along the train from its rear carriage to its head carriage
-- (the direction the train would travel), or nil.
local function headDirection(vehicleEntity)
	local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
	if cl == nil or #cl.carriages < 2 then return nil end
	local function pos(i)
		local mil = api.engine.getComponent(cl.carriages[i], api.type.ComponentType.MODEL_INSTANCE_LIST)
		local c = mil.fatInstances[1].transf:cols(3)
		return c.x, c.y
	end
	local hx, hy = pos(1)
	local rx, ry = pos(#cl.carriages)
	local d = math.sqrt((hx - rx) ^ 2 + (hy - ry) ^ 2)
	if d < 1e-6 then return nil end
	return (hx - rx) / d, (hy - ry) / d
end

-- Whether the loco part must be marked reversed so that it faces the way the
-- ghost faced at the end of its run (= the way the real loco faced when it
-- left: a loco that runs round does not turn, so it goes back on facing the
-- train and pulls it tender-first). reversed = facing against the train's
-- head direction.
local function locoIsReversed(run)
	if run.gyaw == nil or run.startHead == nil or run.startSign == nil then return nil, "no start geometry" end
	-- The head direction now is the one at the start, or its opposite once the
	-- game's flip has been done: known from the geometry, NOT read from the
	-- carriages, whose positions are still the old ones for a tick or two after
	-- a flip (that gave the wrong answer and showed the loco the wrong way for a
	-- moment before the check put it right).
	local hx, hy = run.startHead.x, run.startHead.y
	if run.flipped then hx, hy = -hx, -hy end
	local dot = math.cos(run.gyaw) * hx + math.sin(run.gyaw) * hy
	local sign = dot >= 0 and 1 or -1
	-- The part's flag was reversed=startReversed when its facing had sign
	-- startSign against the head; the same sign needs the same flag.
	local reversed = run.startReversed
	if sign ~= run.startSign then reversed = not reversed end -- (not `and/or`: that fails when the flag is false)
	return reversed, string.format("ghost facing dot head direction = %.2f (was %+d at the start with reversed=%s)", dot, run.startSign, tostring(run.startReversed))
end

-- Edits one run in the saved state (a run handed to postUpdate is a copy).
local function updateRun(state, vehicleEntity, fn)
	local data = state:get()
	for _, r in ipairs(data.runs) do
		if r.vehicleEntity == vehicleEntity then fn(r) end
	end
	state:set(data)
end

-- Steps the creep layout on (see creepLayout). Returns true when a command is
-- due, which layoutStep then sends from postUpdate.
local function advanceLayout(run, dt)
	local L = run.layout
	if L == nil or L.busy or L.stage == "done" or L.stage == "failed" then return false end
	if L.stage == "waiting" then
		if (run.gdist or 0) < CONFIG.creepStartDistance then return false end
		L.stage = "A"
		L.timer = 0
		logInfo("creep: moving the coaches along by", L.len, "m while the loco is away")
	end
	L.timer = (L.timer or 0) + dt
	if L.timer < CONFIG.creepStepSeconds then return false end
	L.timer = 0
	local half = L.len / 2
	local step = CONFIG.creepStep or 0.25
	if L.stage == "A" then
		if L.a > half + 1e-6 then
			local d = math.min(step, L.a - half)
			L.a, L.b, L.action = L.a - d, L.b + d, "replace"
		else
			L.stage, L.action = "flip", "flip"
		end
	elseif L.stage == "B" then
		if L.b > 1e-6 then
			local d = math.min(step, L.b)
			L.a, L.b, L.action = L.a + d, L.b - d, "replace"
		else
			L.stage = "done"
			logInfo("creep: done")
			return false
		end
	else
		return false
	end
	L.busy = true
	return true
end

local function layoutStep(state, vehicleEntity)
	local data = state:get()
	local run = nil
	for _, r in ipairs(data.runs) do if r.vehicleEntity == vehicleEntity then run = r end end
	if run == nil or run.layout == nil then return end
	local L = run.layout
	local function done(fn)
		holdTrain(vehicleEntity)
		updateRun(state, vehicleEntity, function(r)
			if r.layout ~= nil then
				r.layout.busy = false
				if fn then fn(r) end
			end
		end)
	end
	local function fail(why)
		logInfo("creep: stopped -", why)
		done(function(r) r.layout.stage = "failed" end)
	end
	if L.action == "flip" then
		local ok, cmd = pcall(api.cmd.makeVehicleReverseCmd, vehicleEntity)
		if not ok then return fail("reverse command rejected: " .. tostring(cmd)) end
		api.cmd.sendCommand(cmd, function(_, success)
			if not success then return fail("reverse command failed") end
			logInfo("creep: train flipped (it is symmetrical now, so nothing should move)")
			scheduleTrace(state, "after the flip (+4 ticks)", vehicleEntity, 4)
			done(function(r)
				r.layout.stage = "B"
				r.flipped = true
			end)
		end)
		return
	end
	local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then return fail("the train is gone") end
	local okB, cfg = pcall(buildCreepConfig, tv.transportVehicleConfig, L.a, L.b, run.locoPart)
	if not okB then return fail("could not build the layout: " .. tostring(cfg)) end
	local okC, cmd = pcall(api.cmd.makeVehicleReplaceCmd, vehicleEntity, cfg)
	if not okC then return fail("replace rejected: " .. tostring(cmd)) end
	api.cmd.sendCommand(cmd, function(_, success)
		if not success then return fail("replace failed") end
		done(nil)
	end)
end

-- The game flips a train that has to leave a terminus by the way it came (it
-- mirrors the consist end for end and keeps the parts list order), and it does
-- that at departure. A loco coupled on at the exit end was therefore flipped
-- straight back to the buffer end (seen live). So the train is flipped HERE
-- (game's own reverse command), while only wagons and the invisible stand-in
-- are on it: the head then faces the exit and the stand-in sits at the exit
-- end. The ghost then glides to the stand-in (position read off the live
-- carriage) and the loco replaces it, so nothing snaps and nothing is flipped
-- at departure. Live run: parts order is preserved by the flip ("Swwww").
local function flipRun(state, vehicleEntity)
	local function fail(reason)
		logInfo("flip failed (", reason, ") - the loco will be put back without flipping")
		updateRun(state, vehicleEntity, function(r) r.phase = "done"; r.noFlip = true end)
	end
	local okRev, revCmd = pcall(api.cmd.makeVehicleReverseCmd, vehicleEntity)
	if not okRev then return fail("reverse command rejected: " .. tostring(revCmd)) end
	api.cmd.sendCommand(revCmd, function(_, success)
		if not success then return fail("reverse command failed") end
		logInfo("train flipped; putting the loco back")
		scheduleTrace(state, "after the flip (+2 ticks)", vehicleEntity, 2)
		scheduleTrace(state, "after the flip (+8 ticks)", vehicleEntity, 8)
		updateRun(state, vehicleEntity, function(r)
			r.flipped = true
			r.phase = "settle"
			r.settleTicks = 0
		end)
	end)
end

-- The real loco's facing is compared with the ghost's once it is back on the train
-- (its part's `reversed` flag may not mean what it seems), and the flag is
-- toggled once if they differ, so the loco is never turned round by the swap.
local function verifyRun(state, run)
	scheduleTrace(state, "after the release", run.vehicleEntity, 60)
	local ok, yaw = pcall(function()
		local cl = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
		local idx = run.locoAtRear and #cl.carriages or 1
		local mil = api.engine.getComponent(cl.carriages[idx], api.type.ComponentType.MODEL_INSTANCE_LIST)
		local c0 = mil.fatInstances[1].transf:cols(0)
		return math.atan2(c0.y, c0.x)
	end)
	if not ok then
		logInfo("verify: could not read the loco's facing (", tostring(yaw), ") - leaving it as it is")
		finalizeRun(run)
		return
	end
	local dot = math.cos(run.gyaw) * math.cos(yaw) + math.sin(run.gyaw) * math.sin(yaw)
	logInfo(string.format("verify: loco facing against ghost facing, dot = %.2f", dot))
	if dot >= 0 or run.corrected then
		finalizeRun(run)
		return
	end
	local okFix, cmd = pcall(function()
		local tv = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
		local config = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
		local parts = {}
		for i, part in ipairs(config.vehicles) do parts[i] = part end
		local idx = run.locoAtRear and #parts or 1
		parts[idx].part.reversed = not parts[idx].part.reversed
		return api.cmd.makeVehicleReplaceCmd(run.vehicleEntity, finishConfig(config, parts))
	end)
	if not okFix then
		logInfo("verify: could not turn the loco round:", tostring(cmd))
		finalizeRun(run)
		return
	end
	logInfo("verify: the loco faces the wrong way, flipping its reversed flag")
	api.cmd.sendCommand(cmd, function(_, success)
		if not success then logInfo("verify: the correction was refused") end
		finalizeRun(run)
	end)
end

local recoupleRake -- defined with the ghost rake, below

local function finishRun(state, run)
	local tv = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		logInfo("finishRun: vehicle", run.vehicleEntity, "no longer exists, aborting recouple")
		api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost))
		return
	end
	if run.rake ~= nil then
		return recoupleRake(state, run) -- also when it failed: the real train goes back
	end
	local reversed, why = locoIsReversed(run)
	if run.flipped then
		-- Head faces the exit and the stand-in is the head part: loco goes there.
		local restore = run.layout == nil and (run.origRev or {}) or nil
		recouple(state, run, tv, false, reversed, "train was flipped first, loco takes the head; " .. tostring(why), restore)
		return
	end
	local okEnd, atRear, endWhy = pcall(chooseAttachEnd, run.vehicleEntity, run.loop, tv.transportVehicleConfig, run.standInModelId)
	if not okEnd then
		logInfo("could not work out which end to attach at (", tostring(atRear), ") - defaulting to the rear")
		atRear, endWhy = true, "fallback"
	end
	recouple(state, run, tv, atRear, reversed, "no flip; " .. tostring(endWhy) .. "; " .. tostring(why))
end

-- ---------------------------------------------------------------------
-- Ghost rake (see CONFIG.ghostRake)
-- ---------------------------------------------------------------------

-- Every carriage's centre and yaw, in list order.
local function carriageFrames(vehicleEntity)
	local frames = {}
	local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
	for i, c in ipairs(cl.carriages) do
		local mil = api.engine.getComponent(c, api.type.ComponentType.MODEL_INSTANCE_LIST)
		local t = mil.fatInstances[1].transf
		local p, x = t:cols(3), t:cols(0)
		frames[i] = { x = p.x, y = p.y, z = p.z, yaw = math.atan2(x.y, x.x), modelId = mil.fatInstances[1].modelId, entity = c }
	end
	return frames
end

-- Every part's length, from the spacing of the carriage centres (neighbours are
-- half of one plus half of the other apart). Parts of the same model are taken to
-- be the same length, which fixes the one unknown; nil if it cannot be worked out.
local function partLengths(frames, tvc)
	local n = #frames
	if n < 2 then return nil end
	local gaps = {}
	for i = 1, n - 1 do
		gaps[i] = math.sqrt((frames[i].x - frames[i + 1].x) ^ 2 + (frames[i].y - frames[i + 1].y) ^ 2)
	end
	local len = {}
	for i = 1, n - 1 do
		if tvc.vehicles[i].part.modelId == tvc.vehicles[i + 1].part.modelId then len[i], len[i + 1] = gaps[i], gaps[i] end
	end
	if next(len) == nil then return nil end
	for _ = 1, n do -- spread from the known ones: len[i] + len[i+1] = 2 * gap
		for i = 1, n - 1 do
			if len[i] ~= nil and len[i + 1] == nil then len[i + 1] = 2 * gaps[i] - len[i] end
			if len[i + 1] ~= nil and len[i] == nil then len[i] = 2 * gaps[i] - len[i + 1] end
		end
	end
	for i = 1, n do
		if len[i] == nil or len[i] < 0.5 or len[i] > 44 then return nil end
	end
	return len
end

-- The colour that tells the wrapped transformator to draw a real carriage as
-- nothing (it is unlikely to be anyone's paint; see ghost_real.script.lua).
local HIDE_COLOUR = { 0.1234567, 0.7654321, 0.3141593 }

-- The train while its ghosts are shown: a stand-in for the loco, then the REAL
-- coaches, hidden, in reverse order and turned. After the flip that is, from the
-- new head, loco then last coach ... first coach, each facing as it did: the train
-- the loco couples back onto, with nothing taken out of it.
local function buildHiddenRakeConfig(tvc, lengths, locoSnap)
	local config = api.type.TransportVehicleConfig.new(tvc)
	local parts = { makeStandInPart(findStandInModelId(lengths[1]), locoSnap) }
	for i = #config.vehicles, 2, -1 do
		local part = config.vehicles[i]
		part.part.reversed = not part.part.reversed
		part.part.color = api.type.Vec3f.new(HIDE_COLOUR[1], HIDE_COLOUR[2], HIDE_COLOUR[3])
		parts[#parts + 1] = part
	end
	return finishConfig(config, parts)
end

-- The coach snapshot a current part is (by model and purchase time), or nil.
local function matchCoach(part, coaches)
	for i, c in ipairs(coaches) do
		if c.snap.modelId == part.part.modelId and c.snap.purchaseTime == part.purchaseTime and not c.matched then
			c.matched = true
			return i, c
		end
	end
	return nil
end

-- The train at the end: the loco at the head and the same coach parts (so their
-- passengers and goods stay) with their own paint back. Flipped: they are already
-- in the right order. Not flipped (something failed): back in the original order,
-- facing as they did.
local function buildRealRakeConfig(currentTvc, locoSnap, locoReversed, coaches, flipped)
	local config = api.type.TransportVehicleConfig.new(currentTvc)
	for _, c in ipairs(coaches) do c.matched = false end
	local found = {}
	for _, part in ipairs(config.vehicles) do
		if not isStandIn(part.part.modelId) then
			local idx, c = matchCoach(part, coaches)
			if c ~= nil and c.snap.color ~= nil then
				part.part.color = api.type.Vec3f.new(c.snap.color.x, c.snap.color.y, c.snap.color.z)
			end
			found[#found + 1] = { part = part, idx = idx or (#found + 1), c = c }
		end
	end
	local parts = { partFromSnapshot(locoSnap, locoReversed) }
	if flipped then
		for _, f in ipairs(found) do parts[#parts + 1] = f.part end
	else
		table.sort(found, function(a, b) return a.idx < b.idx end)
		for _, f in ipairs(found) do
			if f.c ~= nil then f.part.part.reversed = f.c.snap.reversed end
			parts[#parts + 1] = f.part
		end
	end
	return finishConfig(config, parts)
end

local function pushCoachState(coach, speed, seg)
	pcall(function()
		api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateStateCmd(coach.ghost, {
			speed01 = 0.0, power01 = 0.0,
			state = { speed = speed, power = 0.0, vx = 0.0, vy = 0.0, color = coach.color, dist = coach.dist or 0.0, seg = seg, dir = 1, mirror = coach.mirror },
		}))
	end)
end

local function smoothstep(t)
	if t <= 0 then return 0 end
	if t >= 1 then return 1 end
	return t * t * (3 - 2 * t)
end

-- Moves the ghost rake on. Returns true when the invisible train needs flipping.
local function advanceRake(run, dt)
	local R = run.rake
	if R == nil or R.busy then return false end
	if R.stage == "flip" then
		R.busy = true
		return true
	end
	if R.stage == "settle" then
		R.ticks = (R.ticks or 0) + 1
		if R.ticks < 4 then return false end
		-- Where everything will be: the invisible stand-ins, ordered from the buffer
		-- end (where the loco stood) outwards. The last is the loco's place; the
		-- others are the coaches', first to last.
		local ok, frames = pcall(carriageFrames, run.vehicleEntity)
		if not ok then R.stage = "failed" return false end
		local from = run.locoPos
		local coachFrames, locoFrame = {}, nil
		for _, f in ipairs(frames) do
			if isStandIn(f.modelId) then locoFrame = f else coachFrames[#coachFrames + 1] = f end
		end
		table.sort(coachFrames, function(a, b)
			return (a.x - from.x) ^ 2 + (a.y - from.y) ^ 2 < (b.x - from.x) ^ 2 + (b.y - from.y) ^ 2
		end)
		if locoFrame == nil or #coachFrames ~= #R.coaches then R.stage = "failed" return false end
		for i, c in ipairs(R.coaches) do
			c.target = coachFrames[i]
			c.mirror = coachFrames[i].entity -- the real coach under this ghost: its load nodes
			pushCoachState(c, 0.0, nil)
		end
		run.target = { x = locoFrame.x, y = locoFrame.y, z = locoFrame.z }
		R.stage = "waiting"
		logInfo(string.format("ghost rake: the coaches will slide %.1f m", math.sqrt((R.coaches[1].target.x - R.coaches[1].start.x) ^ 2 + (R.coaches[1].target.y - R.coaches[1].start.y) ^ 2)))
		return false
	end
	if R.stage == "waiting" then
		if (run.gdist or 0) < CONFIG.creepStartDistance then return false end
		local far = 0
		for _, c in ipairs(R.coaches) do
			c.slide = math.sqrt((c.target.x - c.start.x) ^ 2 + (c.target.y - c.start.y) ^ 2)
			if c.slide > far then far = c.slide end
		end
		R.duration = math.max(far / CONFIG.rakeSlideSpeed, 3.0)
		R.t = 0
		R.stage = "slide"
		for _, c in ipairs(R.coaches) do
			c.dist0 = c.dist or 0.0
			pushCoachState(c, c.slide / R.duration, { d0 = c.dist0, v0 = c.slide / R.duration, acc = 0.0, vmax = 0.0, t0 = gameTimeMs() })
		end
		return false
	end
	if R.stage == "slide" then
		R.t = R.t + dt
		local f = smoothstep(R.t / R.duration)
		for _, c in ipairs(R.coaches) do
			local x = c.start.x + (c.target.x - c.start.x) * f
			local y = c.start.y + (c.target.y - c.start.y) * f
			local z = c.start.z + (c.target.z - c.start.z) * f
			pcall(function()
				api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(c.ghost,
					api.type.Mat4f.rotZTransl(c.start.yaw, api.type.Vec3f.new(x, y, z))))
			end)
		end
		if R.t >= R.duration then
			R.stage = "done"
			for _, c in ipairs(R.coaches) do
				c.dist = (c.dist0 or 0.0) + (c.slide or 0.0)
				pushCoachState(c, 0.0, { d0 = c.dist, v0 = 0.0, acc = 0.0, vmax = 0.0, t0 = gameTimeMs() })
			end
			logInfo("ghost rake: coaches in place")
		end
	end
	return false
end

local function rakeFlipStep(state, vehicleEntity)
	local function done(fn)
		holdTrain(vehicleEntity)
		updateRun(state, vehicleEntity, function(r) if r.rake then r.rake.busy = false; fn(r) end end)
	end
	local ok, cmd = pcall(api.cmd.makeVehicleReverseCmd, vehicleEntity)
	if not ok then
		logInfo("ghost rake: reverse rejected:", tostring(cmd))
		return done(function(r) r.rake.stage = "failed" end)
	end
	api.cmd.sendCommand(cmd, function(_, success)
		if not success then
			logInfo("ghost rake: reverse failed")
			return done(function(r) r.rake.stage = "failed" end)
		end
		scheduleTrace(state, "hidden train after the flip (+4 ticks)", vehicleEntity, 4)
		done(function(r)
			r.rake.stage = "settle"
			r.rake.ticks = 0
			r.flipped = true
		end)
	end)
end

-- The ghost rake's end: the real train swapped back in under the ghosts.
recoupleRake = function(state, run)
	local tv = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	local reversed, why = locoIsReversed(run)
	logInfo("recouple (ghost rake): the real train back in place of the invisible one; loco", reversed and "reversed" or "not reversed", "-", tostring(why))
	if not run.flipped then reversed = run.startReversed end
	local okB, cfg = pcall(buildRealRakeConfig, tv.transportVehicleConfig, run.locoPart, reversed, run.rake.coaches, run.flipped)
	local okC, cmd = false, nil
	if okB then okC, cmd = pcall(api.cmd.makeVehicleReplaceCmd, run.vehicleEntity, cfg) end
	if not okC then
		logInfo("recouple (ghost rake) FAILED:", tostring(okB and cmd or cfg), "- ghosts left in place, train released")
		releaseTrain(run.vehicleEntity)
		return
	end
	api.cmd.sendCommand(cmd, function(_, success)
		if not success then
			logInfo("recouple (ghost rake) replace FAILED - ghosts left in place, train released")
			releaseTrain(run.vehicleEntity)
			return
		end
		scheduleTrace(state, "after the recouple (+3 ticks)", run.vehicleEntity, 3)
		api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost))
		for _, c in ipairs(run.rake.coaches) do
			if c.ghost ~= nil then api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(c.ghost)) end
		end
		run.ghostGone = true
		run.phase = "verify"
		run.verifyWait = 0
		run.locoAtRear = false
		local data = state:get()
		data.runs[#data.runs + 1] = run
		state:set(data)
	end)
end

local function startRunAround(state, vehicleEntity, loop)
	local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		return
	end
	local tvc = tv.transportVehicleConfig
	local locoIdx = nil
	if loop.locoManual then
		locoIdx = findLocoIndex(tvc, loop)
	else
		-- Automatic: the part of the train nearest the first route point is
		-- the one at the front for the run-around.
		local first = loop.waypoints and loop.waypoints[1]
		local okPos, pos = pcall(function() return first and piecePos(first, 0.5) end)
		if okPos and pos ~= nil then
			local okN, idx, dist = pcall(nearestCarriageIndex, vehicleEntity, pos)
			if okN and idx ~= nil and tvc.vehicles[idx] ~= nil then
				locoIdx = idx
				logInfo("loco chosen automatically: part", idx, "of", #tvc.vehicles, "- model", tvc.vehicles[idx].part.modelId, "- about", math.floor(dist), "m from the first route point")
			end
		end
		if locoIdx == nil then
			logInfo("automatic loco choice failed; using the first part of the train")
			locoIdx = 1
		end
	end
	if locoIdx == nil then
		logInfo("startRunAround: no vehicle part with modelId", loop.locoModelId, "found on", vehicleEntity, "loop", loopLabel(loop))
		return
	end
	if #loop.loopEdges == 0 then
		logInfo("startRunAround: no route for loop", loopLabel(loop), "- nothing to animate (" .. tostring(loop.pathStatus) .. ")")
		return
	end

	-- Everything that can fail is prepared BEFORE the train is held, so a
	-- problem here can't leave it stuck at the station.
	local okSnap, locoSnap = pcall(snapshotPart, tvc.vehicles[locoIdx])
	if not okSnap then
		logInfo("startRunAround: could not read the locomotive part:", tostring(locoSnap))
		return
	end
	local okT, locoTransf = pcall(captureLocoTransform, vehicleEntity, locoIdx)
	if not okT then
		logInfo("startRunAround: could not read the loco's position (", tostring(locoTransf), ") - the ghost will appear on the route instead")
		locoTransf = nil
	end
	local locoLength = modelLength(tvc.vehicles[locoIdx].part.modelId)
	local lengthFrom = "its model"
	if locoLength == nil then
		local okLen, measured = pcall(carriageLength, vehicleEntity, locoIdx)
		if okLen and measured ~= nil and measured >= 2 and measured <= 60 then locoLength, lengthFrom = measured, "carriage spacing" end
	end
	local standId, standLength = findStandInModelId(locoLength)
	logInfo("stand-in:", tostring(standLength), "m; loco", locoLength and string.format("%.2f m long (from %s)", locoLength, lengthFrom) or "of unknown length")
	if standId == nil then
		logInfo("startRunAround: no stand-in model found, so the loco will NOT be detached (a wagons-only train crashes the game). Is res/models/runaround_standin/ loaded?")
		return
	end
	local ghostModelId, ghostEffects = findGhostModelId(locoSnap.modelId)
	if CONFIG.useRealModel then
		local ready, why = realModelReady(locoSnap.modelId)
		if ready then
			ghostModelId, ghostEffects = locoSnap.modelId, true
			logInfo("ghost model: using the loco's OWN model", locoSnap.modelId, "(sound and transformator wrapped)")
		else
			logInfo("ghost model: the loco's own model cannot be used -", why, "- using a ghost copy")
		end
	end
	if ghostModelId == nil then
		logInfo("startRunAround: no ghost model available, so the loco will NOT be detached (is res/models/runaround_ghost/ loaded?)")
		return
	end
	local locoTopSpeed = tonumber(modelMeta(locoSnap.modelId, "landVehicle", "topSpeed"))
	if locoTopSpeed ~= nil and locoTopSpeed <= 1 then locoTopSpeed = nil end
	local startHead, startSign = nil, nil
	do
		local okH, hx, hy = pcall(headDirection, vehicleEntity)
		if okH and hx ~= nil and locoTransf ~= nil then
			local c0 = locoTransf:cols(0)
			startHead = { x = hx, y = hy }
			startSign = (c0.x * hx + c0.y * hy) >= 0 and 1 or -1
			logInfo(string.format("loco at start: part reversed=%s, facing dot train head direction = %.2f", tostring(locoSnap.reversed), c0.x * hx + c0.y * hy))
		end
	end
	local origRev = {}
	for i, part in ipairs(tvc.vehicles) do
		if i ~= locoIdx then origRev[#origRev + 1] = part.part.reversed and true or false end
	end
	local addTail = false
	local creep = CONFIG.creepLayout and CONFIG.reverseBeforeRecouple and locoIdx == 1 and #tvc.vehicles > 1
	if creep then
		-- a multiple of 0.5 m, so it splits into two equal stand-ins (in 0.25 m
		-- steps) and the train can be exactly symmetrical at the flip
		local len = 0.5 * math.floor((locoLength or 12.0) / 0.5 + 0.5)
		if len < 0.5 then len = 0.5 end
		if len > 44 then len = 44 end
		standId, standLength = findStandInModelId(len)
	end
	-- The ghost rake, when every coach can be shown (see CONFIG.ghostRake).
	local rakeInfo = nil
	if CONFIG.ghostRake and CONFIG.reverseBeforeRecouple and locoIdx == 1 and #tvc.vehicles > 1 then
		local okF, frames = pcall(carriageFrames, vehicleEntity)
		-- only the loco's length is needed (for its stand-in); the coaches stay in the train
		local lengths = nil
		if okF and locoLength ~= nil then
			lengths = { locoLength }
		elseif okF then
			lengths = partLengths(frames, tvc)
		end
		if lengths == nil then logInfo("ghost rake: the loco's length is unknown") end
		if lengths ~= nil then
			local coaches = {}
			for i = 2, #tvc.vehicles do
				local okS, snap = pcall(snapshotPart, tvc.vehicles[i])
				local gid = coachGhostModel(tvc.vehicles[i].part.modelId)
				if not okS or gid == nil then coaches = nil break end
				local f = frames[i]
				coaches[#coaches + 1] = {
					snap = snap, ghostModel = gid,
					start = { x = f.x, y = f.y, z = f.z, yaw = f.yaw },
					color = snap.color and { snap.color.x, snap.color.y, snap.color.z } or nil,
					dist = 0.0,
				}
			end
			if coaches ~= nil then rakeInfo = { coaches = coaches, lengths = lengths } end
		end
		if rakeInfo == nil then logInfo("ghost rake: not every coach can be shown - using the creep instead") end
	end
	if rakeInfo ~= nil then creep = false end

	local okBuild, strippedConfig
	if rakeInfo ~= nil then
		okBuild, strippedConfig = pcall(buildHiddenRakeConfig, tvc, rakeInfo.lengths, locoSnap)
	elseif creep then
		okBuild, strippedConfig = pcall(buildCreepConfig, tvc, standLength, 0, locoSnap, locoIdx)
	else
		okBuild, strippedConfig = pcall(buildConfigWithStandIn, tvc, locoIdx, standId, locoSnap, addTail)
	end
	if not okBuild then
		logInfo("startRunAround: could not build the consist with the stand-in:", tostring(strippedConfig))
		return
	end
	local okCmd, replaceCmd = pcall(api.cmd.makeVehicleReplaceCmd, vehicleEntity, strippedConfig)
	if not okCmd then
		logInfo("startRunAround: stand-in swap command rejected:", tostring(replaceCmd))
		return
	end

	traceNow("before the detach", vehicleEntity)
	holdTrain(vehicleEntity)

	local sendReplace -- defined below; with a ghost rake it is sent once the coach ghosts are up

	-- Spawns the coach ghosts one after another, each exactly where its coach is,
	-- then sends the replace (so no coach is ever missing from view).
	local function spawnCoachGhosts(i)
		if rakeInfo == nil or i > #rakeInfo.coaches then return sendReplace() end
		local c = rakeInfo.coaches[i]
		api.cmd.sendCommand(api.cmd.makeCustomEntityCreateCmd(c.ghostModel), function(res, ok)
			if not ok then
				logInfo("ghost rake: could not show coach", i, "- run-around not started")
				for j = 1, i - 1 do api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(rakeInfo.coaches[j].ghost)) end
				releaseTrain(vehicleEntity)
				return
			end
			c.ghost = res.resultEntity
			api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(c.ghost,
				api.type.Mat4f.rotZTransl(c.start.yaw, api.type.Vec3f.new(c.start.x, c.start.y, c.start.z))))
			pushCoachState(c, 0.0, nil)
			spawnCoachGhosts(i + 1)
		end)
	end

	sendReplace = function() api.cmd.sendCommand(replaceCmd, function(_, success)
		if not success then
			logInfo("detach replaceVehicle FAILED for vehicle", vehicleEntity, "loop", loopLabel(loop), "- train released")
			releaseTrain(vehicleEntity)
			return
		end

		scheduleTrace(state, "after the detach (+2 ticks)", vehicleEntity, 2)
		scheduleTrace(state, "after the detach (+30 ticks)", vehicleEntity, 30)
		api.cmd.sendCommand(api.cmd.makeCustomEntityCreateCmd(ghostModelId), function(createRes, createSuccess)
			if not createSuccess then
				logInfo("failed to spawn ghost loco entity for loop", loopLabel(loop), "- putting the loco back on the train")
				local tvNow = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
				if tvNow ~= nil then
					local okB, cfg = pcall(buildConfigWithLocoReattached, tvNow.transportVehicleConfig, locoSnap, false, standId)
					local okC, cmd = false, nil
					if okB then okC, cmd = pcall(api.cmd.makeVehicleReplaceCmd, vehicleEntity, cfg) end
					if okC then api.cmd.sendCommand(cmd) else logInfo("could not restore the loco:", tostring(okB and cmd or cfg)) end
				end
				releaseTrain(vehicleEntity)
				return
			end
			local ghost = createRes.resultEntity
			if locoTransf ~= nil then
				api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(ghost, locoTransf))
			end

			local startCursor, startOffset = 1, nil
			local locoYaw = nil
			if locoTransf ~= nil then
				local c0 = locoTransf:cols(0)
				locoYaw = math.atan2(c0.y, c0.x)
			end
			if locoTransf ~= nil then
				local c = locoTransf:cols(3)
				local okL, k, off, dist = pcall(locateOnRoute, loop, { x = c.x, y = c.y })
				if okL and k ~= nil and dist < 40 then
					startCursor, startOffset = k, off
					logInfo(string.format("ghost starts on route piece %d, %d m along it (%d m from the loco's position)", k, math.floor(off), math.floor(dist)))
				else
					logInfo("the loco is not on the first pieces of the route (", tostring(okL and dist or k), ") - the ghost starts at the route's first piece")
				end
			end
			local data = state:get()
			data.runs[#data.runs + 1] = {
				vehicleEntity = vehicleEntity,
				loop = loop,
				locoPart = locoSnap,
				standInModelId = standId,
				standInLength = standLength,
				hasTail = addTail,
				layout = creep and { len = standLength, a = standLength, b = 0, stage = "waiting", timer = 0, busy = false } or nil,
				rake = rakeInfo and { stage = "flip", busy = false, coaches = rakeInfo.coaches } or nil,
				locoLength = locoLength,
				startHead = startHead,
				startSign = startSign,
				startReversed = locoSnap.reversed and true or false,
				effects = ghostEffects,
				color = locoSnap.color and { locoSnap.color.x, locoSnap.color.y, locoSnap.color.z } or nil,
				topSpeed = locoTopSpeed,
				origRev = origRev,
				ghost = ghost,
				edgeCursor = startCursor,
				startOffset = startOffset,
				locoYaw = locoYaw,
				locoPos = locoTransf ~= nil and { x = locoTransf:cols(3).x, y = locoTransf:cols(3).y } or nil,
				edgeLength = nil,
				edgeProgress = 0.0,
				speed = 0.0,
			}
			state:set(data)
			if ghostEffects then
				local run = data.runs[#data.runs]
				startSegment(run, 0.0, 0.0, 0.0)
				pushGhostState(run, 0.0, 0.0, 0.0, 0.0)
				state:set(data)
			end
			logInfo("run-around started for vehicle", vehicleEntity, "loop", loopLabel(loop))
		end)
	end) end
	spawnCoachGhosts(1)
end

-- Ensures state:get() always returns the {runs, loops} shape, even on a
-- fresh save where state:get() starts out nil.
local function ensureData(state)
	local data = state:get()
	if data == nil then
		data = { runs = {}, loops = {} }
		state:set(data)
	end
	if data.runs == nil then data.runs = {} end
	if data.loops == nil then data.loops = {} end
	if data.pending == nil then data.pending = {} end
	return data
end

-- True if this vehicle already has a run in flight or queued to start.
local function vehicleBusy(data, vehicleEntity)
	for _, run in ipairs(data.runs) do
		if run.vehicleEntity == vehicleEntity then return true end
	end
	for _, p in ipairs(data.pending) do
		if p.vehicleEntity == vehicleEntity then return true end
	end
	return false
end

-- Reads a vehicle's consist and current line/stop, for the GUI's
-- "add loop from this vehicle" action. Returns nil if the entity isn't a
-- live transport vehicle right now.
local function readVehicleSnapshot(vehicleEntity)
	local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		return nil
	end
	return {
		lineEntity = tv.line,
		stopIndex = tv.stopIndex,
		vehicles = tv.transportVehicleConfig.vehicles,
	}
end

-- Reads the edge a vehicle currently occupies, from its MOVE_PATH component,
-- for the GUI's "capture edge from this vehicle" action. NOT VERIFIED beyond
-- static type analysis - MOVE_PATH.path.edges[i] is {EdgeId, bool} per
-- api/tealdef/api/type.d.tl's Path record, and dyn.pathPos.edgeIndex is
-- documented as the current 0-based index into that list.
-- No real shipped script anywhere in the base game actually destructures a
-- {EdgeId, boolean} pair out of Path.edges[i] - this shape is declared in
-- the .d.tl types but never exercised in any example we could find, so the
-- runtime representation of that pair is genuinely unconfirmed. A live test
-- showed plain [1]/[2] positional indexing fails ("attempt to index local
-- 'edgeId' (a nil value)"), so this tries several plausible alternate
-- shapes in order and logs which one (if any) actually worked, rather than
-- guess again blind.
local function readVehicleCurrentEdge(vehicleEntity)
	local mp = api.engine.getComponent(vehicleEntity, api.type.ComponentType.MOVE_PATH)
	if mp == nil or mp.path == nil or mp.dyn == nil then
		return nil
	end
	local idx = mp.dyn.pathPos.edgeIndex
	local edgeAndDir = mp.path.edges[idx + 1] -- 0-based -> 1-based
	if edgeAndDir == nil then
		logInfo("readVehicleCurrentEdge: mp.path.edges[", idx + 1, "] is nil (edgeIndex=", idx, ", #edges=", #mp.path.edges, ")")
		return nil
	end

	local function tryShape(label, fn)
		local ok, edgeId, forward = pcall(fn)
		if ok and edgeId ~= nil and edgeId.entity ~= nil and edgeId.index ~= nil then
			logInfo("readVehicleCurrentEdge: shape '" .. label .. "' worked")
			return { entity = edgeId.entity, index = edgeId.index, forward = forward }
		end
		return nil
	end

	local result =
		tryShape("positional [1]/[2]", function() return edgeAndDir[1], edgeAndDir[2] end)
		or tryShape("named .edgeId/.forward", function() return edgeAndDir.edgeId, edgeAndDir.forward end)
		or tryShape("named .edgeId/.dir", function() return edgeAndDir.edgeId, edgeAndDir.dir end)
		or tryShape("named .first/.second", function() return edgeAndDir.first, edgeAndDir.second end)
		or tryShape("bare edgeAndDir as EdgeId itself", function() return edgeAndDir, true end)

	if result ~= nil then
		return result
	end

	-- Nothing worked - log everything we can safely see about the real shape
	-- so the next attempt has actual evidence instead of another guess.
	local okType, tyMsg = pcall(function() return type(edgeAndDir) end)
	logInfo("readVehicleCurrentEdge: all known shapes failed. type(edgeAndDir)=", okType and tyMsg or "?")
	local okLen, lenMsg = pcall(function() return #edgeAndDir end)
	logInfo("readVehicleCurrentEdge: #edgeAndDir=", okLen and lenMsg or "(not measurable)")
	local okKeys, keysMsg = pcall(function()
		local parts = {}
		for k, v in pairs(edgeAndDir) do
			parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
		end
		return table.concat(parts, ", ")
	end)
	logInfo("readVehicleCurrentEdge: pairs(edgeAndDir)=", okKeys and keysMsg or "(pairs() failed - likely a userdata, not a table)")
	return nil
end

-- Handles one "RunAroundGuiCmd" event from runaround_gui.lua. All mutation
-- of persistent loop config happens here (not in the GUI file) so there is
-- a single source of truth and the GUI can stay a thin layer.
local function handleGuiCmd(data, name, param)
	if name == "AddLoopFromVehicle" then
		local snap = readVehicleSnapshot(param.vehicleEntity)
		if snap == nil then
			logInfo("AddLoopFromVehicle: entity", param.vehicleEntity, "is not a live transport vehicle")
			return
		end
		if snap.lineEntity == nil or snap.lineEntity < 0 then
			logInfo("AddLoopFromVehicle: vehicle", param.vehicleEntity, "isn't assigned to a line yet")
			return
		end
		local loop = {
			id = newLoopId(data),
			name = "Loop " .. tostring(#data.loops + 1),
			lineEntity = snap.lineEntity,
			stopIndex = snap.stopIndex,
			locoModelId = snap.vehicles[1] and snap.vehicles[1].part.modelId or nil,
			locoManual = false, -- automatic: the part nearest the first route point
			locoCandidateIndex = 0,
			locoPartCount = #snap.vehicles,
			waypoints = {},
			loopEdges = {},
			pathStatus = "no points yet",
			speed = CONFIG.defaultSpeed,
			accel = CONFIG.defaultAccel,
		}
		data.loops[#data.loops + 1] = loop
		logInfo("GUI: added loop", loopLabel(loop), "from vehicle", param.vehicleEntity)

	elseif name == "AddLoopAtStop" then
		-- From the panel's "Add a run-around at <station>": any stop of the line,
		-- named after its station.
		if param.lineEntity == nil or param.stopIndex == nil then return end
		for _, l in ipairs(data.loops) do
			if l.lineEntity == param.lineEntity and l.stopIndex == param.stopIndex then return end
		end
		local snap = param.vehicleEntity and readVehicleSnapshot(param.vehicleEntity)
		local loop = {
			id = newLoopId(data),
			name = param.name or ("Run-around " .. tostring(#data.loops + 1)),
			lineEntity = param.lineEntity,
			stopIndex = param.stopIndex,
			locoModelId = snap and snap.vehicles[1] and snap.vehicles[1].part.modelId or nil,
			locoManual = false,
			locoCandidateIndex = 0,
			locoPartCount = snap and #snap.vehicles or 0,
			waypoints = {},
			loopEdges = {},
			pathStatus = "no points yet",
			speed = CONFIG.defaultSpeed,
			accel = CONFIG.defaultAccel,
		}
		data.loops[#data.loops + 1] = loop
		logInfo("GUI: added run-around", loopLabel(loop), "at line", param.lineEntity, "stop", param.stopIndex)

	elseif name == "CycleLocoCandidate" then
		-- Steps automatic -> part 1 -> part 2 ... -> last part -> automatic.
		local loop = findLoopById(data.loops, param.loopId)
		local snap = loop and readVehicleSnapshot(param.vehicleEntity)
		if loop ~= nil and snap ~= nil and #snap.vehicles > 0 then
			local n = #snap.vehicles
			local idx = ((loop.locoCandidateIndex or 0) + 1) % (n + 1)
			loop.locoCandidateIndex = idx
			loop.locoPartCount = n
			if idx == 0 then
				loop.locoManual = false
				loop.locoModelName = nil
				logInfo("GUI: loop", loopLabel(loop), "loco choice is now automatic")
			else
				loop.locoManual = true
				loop.locoModelId = snap.vehicles[idx].part.modelId
				local okName, name2 = pcall(api.res.modelRep.getName, loop.locoModelId)
				loop.locoModelName = okName and tostring(name2):gsub("^.*/", ""):gsub("%.mdl$", "") or nil
				logInfo("GUI: loop", loopLabel(loop), "loco is now part", idx, "of", n, "- model", loop.locoModelId, loop.locoModelName or "")
			end
		end

	elseif name == "AddLoopEdgeFromVehicle" then
		-- The edge a train is currently on becomes a route point (its own
		-- direction is ignored - the planner chooses directions).
		local loop = findLoopById(data.loops, param.loopId)
		local edge = loop and readVehicleCurrentEdge(param.vehicleEntity)
		if loop ~= nil and edge ~= nil then
			loop.waypoints = loop.waypoints or {}
			local last = loop.waypoints[#loop.waypoints]
			if not sameEdge(last, edge) then
				loop.waypoints[#loop.waypoints + 1] = { entity = edge.entity, index = edge.index }
				logInfo("GUI: loop", loopLabel(loop), "added route point from train position", edge.entity, edge.index)
				recomputeLoopRoute(loop)
			end
		else
			logInfo("AddLoopEdgeFromVehicle: could not read current edge for vehicle", param.vehicleEntity)
		end

	elseif name == "AddLoopEdgeFromWorldClick" then
		-- A click on track in the world becomes a route point: click the
		-- track in front of the station, then the loop, then the track after
		-- the points (more clicks for a wye). No train needs to be there.
		local loop = findLoopById(data.loops, param.loopId)
		if loop ~= nil then
			loop.waypoints = loop.waypoints or {}
			local point = { entity = param.entity, index = param.index }
			if sameEdge(loop.waypoints[#loop.waypoints], point) then
				logInfo("GUI: loop", loopLabel(loop), "ignored a repeat click on the same track piece")
			else
				loop.waypoints[#loop.waypoints + 1] = point
				logInfo("GUI: loop", loopLabel(loop), "added route point (world click)", param.entity, param.index)
				recomputeLoopRoute(loop)
			end
		end

	elseif name == "RemoveLastLoopEdge" then
		local loop = findLoopById(data.loops, param.loopId)
		if loop ~= nil and loop.waypoints ~= nil and #loop.waypoints > 0 then
			loop.waypoints[#loop.waypoints] = nil
			recomputeLoopRoute(loop)
		elseif loop ~= nil and #loop.loopEdges > 0 then
			loop.loopEdges[#loop.loopEdges] = nil -- loop saved by an older version
		end

	elseif name == "ClearLoopPoints" then
		local loop = findLoopById(data.loops, param.loopId)
		if loop ~= nil then
			loop.waypoints = {}
			recomputeLoopRoute(loop)
		end

	elseif name == "RemoveLoop" then
		for i, loop in ipairs(data.loops) do
			if loop.id == param.loopId then
				table.remove(data.loops, i)
				break
			end
		end

	elseif name == "RenameLoop" then
		local loop = findLoopById(data.loops, param.loopId)
		if loop ~= nil then
			loop.name = param.newName
		end

	elseif name == "SetLoopNumberField" then
		-- param.field is one of "speed" / "accel"; kept generic to avoid
		-- repeating this block per field.
		local loop = findLoopById(data.loops, param.loopId)
		if loop ~= nil and (param.field == "speed" or param.field == "accel") then
			loop[param.field] = param.value
		end
	end
end

function data()
return {
	update = function(_userParams, state, dt)
		-- Deliberately unconditional, not gated behind hasEventSubscriptions().
		-- That guard only tells you SOME subscription exists, not that THIS
		-- one does - on a save that was already running before a new
		-- subscribeToEvent call was added to the code (exactly what happened
		-- during development here), the guard sees old subscriptions from a
		-- prior version of this script and permanently skips ever adding the
		-- new one. Repeated calls are assumed idempotent/cheap.
		state:subscribeToEvent("OnArriveAtStop")
		state:subscribeToEvent("RunAroundGuiCmd")

		local data = ensureData(state)

		if dt == 0.0 then return nil end -- paused

		-- Work that needs command CALLBACKS (starting a run-around: detach the
		-- loco then spawn its ghost; finishing one: recouple) cannot be done
		-- here: sendCommand with a callback in update() fails with "Callbacks
		-- are currently disallowed" (hit live). The base game's own scripts
		-- (fun_elements.script.tl) return a result table from update() and do
		-- that work in postUpdate(), so this does the same. Nor can it be done
		-- from handleEvent for OnArriveAtStop (mid-modification assert), which
		-- is why that handler only queues.
		local result = nil

		if #data.pending > 0 then
			result = result or {}
			result.starts = data.pending
			data.pending = {}
		end

		if #data.runs > 0 then
			local remaining = {}
			for _, run in ipairs(data.runs) do
				if advanceGhost(run, dt) then
					result = result or {}
					result.finishes = result.finishes or {}
					result.finishes[#result.finishes + 1] = run
				else
					remaining[#remaining + 1] = run
					if advanceRake(run, dt) then
						result = result or {}
						result.rakeFlips = result.rakeFlips or {}
						result.rakeFlips[#result.rakeFlips + 1] = run.vehicleEntity
					end
					if advanceLayout(run, dt) then
						result = result or {}
						result.layout = result.layout or {}
						result.layout[#result.layout + 1] = run.vehicleEntity
					end
					if run.phase == "flip" and not run.flipSent then
						run.flipSent = true
						result = result or {}
						result.flips = result.flips or {}
						result.flips[#result.flips + 1] = run.vehicleEntity
					end
				end
			end
			data.runs = remaining
		end

		if data.traces ~= nil and #data.traces > 0 then
			local keep = {}
			for _, t in ipairs(data.traces) do
				t.ticks = t.ticks - 1
				if t.ticks <= 0 then traceNow(t.label, t.vehicleEntity) else keep[#keep + 1] = t end
			end
			data.traces = keep
		end

		state:set(data)
		return result
	end,

	postUpdate = function(_userParams, state, _dt, updateResult)
		if updateResult == nil then return end

		if updateResult.starts ~= nil then
			local data = ensureData(state)
			for _, p in ipairs(updateResult.starts) do
				local loop = findLoopById(data.loops, p.loopId)
				if loop ~= nil then
					startRunAround(state, p.vehicleEntity, loop)
				end
			end
		end

		if updateResult.rakeFlips ~= nil then
			for _, vehicleEntity in ipairs(updateResult.rakeFlips) do
				rakeFlipStep(state, vehicleEntity)
			end
		end

		if updateResult.layout ~= nil then
			for _, vehicleEntity in ipairs(updateResult.layout) do
				layoutStep(state, vehicleEntity)
			end
		end

		if updateResult.flips ~= nil then
			for _, vehicleEntity in ipairs(updateResult.flips) do
				flipRun(state, vehicleEntity)
			end
		end

		if updateResult.finishes ~= nil then
			for _, run in ipairs(updateResult.finishes) do
				if run.phase == "verify" then verifyRun(state, run) else finishRun(state, run) end
			end
		end
	end,

	handleEvent = function(_userParams, state, _src, id, name, param)
		if id == "TransportVehicleSystem" and name == "OnArriveAtStop" then
			local data = ensureData(state)
			if CONFIG.LOG_ARRIVALS then
				logInfo("arrival: vehicle=", param.vehicleEntity, "line=", param.lineEntity, "stop=", param.stopIndex)
			end

			local loop = findLoopForArrival(data.loops, param.lineEntity, param.stopIndex)
			if loop ~= nil then
				if loop.locoManual and loop.locoModelId == nil then
					logInfo("startRunAround: loop", loopLabel(loop), "has no locoModelId set yet (configure it from the GUI)")
					return
				end
				if not CONFIG.detachEnabled then
					logInfo("run-around for loop", loopLabel(loop), "NOT started: detaching is switched off (a train of only wagons crashes the game)")
					return
				end
				-- Queue only; update() sends the commands (see there).
				if not vehicleBusy(data, param.vehicleEntity) then
					data.pending[#data.pending + 1] = { vehicleEntity = param.vehicleEntity, loopId = loop.id }
					state:set(data)
					logInfo("queued run-around for vehicle", param.vehicleEntity, "loop", loopLabel(loop))
				end
			end

		elseif name == "RunAroundGuiCmd" then
			-- subscribeToEvent matches on the event's NAME field, not its id
			-- (confirmed from the base game's own achievements.script.tl:
			-- it subscribes to "OnArriveAtStop", which is the NAME of an
			-- event whose id is "TransportVehicleSystem"). So the fixed
			-- channel string has to be the name here, and the per-command
			-- string (previously sent as name) has to travel as id instead -
			-- this was backwards before, which is why no GUI command ever
			-- reached this handler regardless of button or console.
			local data = ensureData(state)
			handleGuiCmd(data, id, param)
			state:set(data)
		end
	end,
}
end
