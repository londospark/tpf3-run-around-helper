--[[
	Runaround Railways - game script (TpF3)

	At a terminus configured in game (a "loop": line + stop + a few clicked route
	points), an arriving train's locomotive runs around its train instead of the
	game's instant flip. With the ghost rake (CONFIG.ghostRake, the usual case):

	  1. every coach is shown as a "ghost" (a free entity drawn from its own
	     model) exactly where it stands;
	  2. detach: the real loco and coaches are hidden, still in the train (the
	     loco too: taking it off would sell it, and a train with no powered part
	     crashes the game), with their passengers and goods; the loco's ghost
	     appears where the loco stood;
	  3. out of sight, the hidden train is turned with the game's reverse command;
	  4. the pull: the loco ghost draws the coach ghosts forward a loco length,
	     to where the turned train's coaches now are, then uncouples;
	  5. the loco ghost drives the planned route (reversing where the planner
	     chose), keeping its facing, with its own sound, smoke, wheels and paint
	     (see ghost_real.script.lua and ghost_build.script.lua);
	  6. it brakes against the far coach; the real loco and coaches get their
	     paint back, the ghosts go, and the train leaves.

	The loco is never taken off the train (that would sell it and buy it back):
	it is hidden in place like the coaches. A coach that can't be hidden makes the
	coaches stay in view and move at the flip. Whatever fails, finishRun puts the
	real train back (see
	recoupleFailed and watchdog): a train is never left stuck or broken.

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
	-- When every coach can be hidden: ghost copies of the loco AND the coaches are
	-- shown in their places, and the real loco and coaches are HIDDEN (not removed: they stay in the train with their passengers
	-- and goods - passengers and cargo belong to the train, and taking coaches out
	-- lowers its capacity). They are hidden by a flag colour that the wrapped
	-- transformator (ghost_real.script.lua) turns into "draw nothing". Out of sight
	-- the train is turned; the loco (still coupled, as ghosts) draws the whole
	-- train forward a loco length to where the coaches now are, stops, uncouples
	-- and runs around; at the end the coaches get their own paint back under their
	-- ghosts. The game's vehicle marker only re-attaches three times.
	ghostRake = true,
	rakePullSpeed = 2.0,  -- m/s: top speed of the train drawing forward before the uncouple
	uncouplePause = 2.5,  -- seconds the train stands before the loco uncouples and sets off
	-- Once the loco is back on, check its real facing against the ghost's and
	-- correct it if they differ (a safety net; see verifyRun).
	verifyFacing = true,
	-- A run that takes longer than watchdogFactor times its route at the loop's
	-- speed, plus watchdogExtraSeconds, has stalled: the real train is put back
	-- and released (see watchdog).
	watchdogFactor = 3.0,
	watchdogExtraSeconds = 60.0,
	-- A refused recouple is tried again recoupleRetries times, recoupleRetrySeconds
	-- apart, with the train held; after that it is "stuck" and tried every
	-- stuckRetrySeconds (see recoupleFailed).
	recoupleRetries = 3,
	recoupleRetrySeconds = 1.0,
	stuckRetrySeconds = 30.0,

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

-- Whether a model has an engine: locos list theirs under landVehicle.engines
-- (with a power), coaches and wagons have an empty list. nil if it can't be read.
local function isPowered(modelId)
	local ok, power = pcall(function() return api.res.modelRep.get(modelId).metadata.landVehicle.engines[1].power end)
	if not ok then
		local okE, n = pcall(function() return #api.res.modelRep.get(modelId).metadata.landVehicle.engines end)
		if okE and n == 0 then return false end
		return nil
	end
	return type(power) == "number" and power > 0
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

-- The player's money, or nil if it can't be read.
local function playerBalance()
	local ok, b = pcall(function()
		return api.engine.getComponent(api.engine.util.getPlayer(), api.type.ComponentType.ACCOUNT).balance
	end)
	return ok and b or nil
end

-- A vehicle replace. The command is the game's "replace vehicles", which charges
-- for parts it adds and refunds parts it removes. The run-around never adds or
-- removes a part (the loco stays on the train, hidden: see isLocoPart), so there
-- is nothing to charge. Its data also has applyPurchaseCost
-- (VehicleReplaceCommandData); setting it on the command is tried as a second line
-- of defence, but the game refused the write live ("COULD NOT be switched off"),
-- and nothing in the game sets it. The detach and recouple log the money change.
local costFlagLogged = false
local function makeReplaceCmd(vehicleEntity, config)
	local cmd = api.cmd.makeVehicleReplaceCmd(vehicleEntity, config)
	local set = pcall(function() cmd.applyPurchaseCost = false end)
	local okR, back = pcall(function() return cmd.applyPurchaseCost end)
	if not (set and okR and back == false) then
		set = pcall(function() cmd.data.applyPurchaseCost = false end)
		okR, back = pcall(function() return cmd.data.applyPurchaseCost end)
	end
	if not costFlagLogged then
		costFlagLogged = true
		logInfo("vehicle replace: purchase-cost flag", (set and okR and back == false) and "set" or "not settable (fine: the run-around never adds or removes a part)")
	end
	return cmd
end

-- Logs how much a replace changed the player's money (should be 0).
local function logMoneyChange(label, before)
	local after = playerBalance()
	if before ~= nil and after ~= nil then logInfo(string.format("money: %s changed the balance by %d", label, after - before)) end
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

local function carriagePos(carriageEntity)
	local mil = api.engine.getComponent(carriageEntity, api.type.ComponentType.MODEL_INSTANCE_LIST)
	return mil.fatInstances[1].transf:cols(3)
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

-- Whether a real vehicle can be hidden (drawn as nothing) while its copy runs
-- around: its transformator was wrapped or chained at load, which ghost_build
-- marks with "runaround_ghost_hide/<file>.mdl".
local hideMarkers = nil
local function canHide(modelId)
	local okAll, all = pcall(api.res.modelRep.getAll, true)
	if not okAll or all == nil then return false end
	if hideMarkers == nil then
		hideMarkers = {}
		for _, name in pairs(all) do
			local marked = type(name) == "string" and string.match(name, "runaround_ghost_hide/(.+)%.mdl$")
			if marked then hideMarkers[marked] = true end
		end
	end
	local base = type(all[modelId]) == "string" and string.match(all[modelId], "([^/]+)%.mdl$") or nil
	return base ~= nil and hideMarkers[base] == true
end

-- The model a coach's ghost is drawn from, or nil if it cannot have one. It is the
-- coach's own model, and only when its transformator was wrapped at load: the same
-- wrapper is what hides the real coach while its ghost is shown, so a coach
-- without it could not be hidden either (the coaches then stay in view).
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
	-- s0: the distance along the copy's facing so far (backwards counts down), for
	-- the axles ghost_real turns; each segment runs one way (run.pushedDir)
	local prev, s0 = run.seg, 0.0
	if prev ~= nil then s0 = (prev.s0 or 0.0) + (run.pushedDir or 1) * ((run.gdist or 0.0) - (prev.d0 or 0.0)) end
	run.seg = { d0 = run.gdist or 0.0, v0 = v0, acc = acc, vmax = vmax, t0 = gameTimeMs(), s0 = s0 }
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
	if run.phase == "approach" and run.approachBackwards ~= nil then
		-- the glide's own direction: the route may end facing either way (a last
		-- reverse back to the coaches that was never clicked is driven only here)
		backwards = run.approachBackwards and 1 or 0
	end
	local dir = (backwards % 2 == 1) and -1 or 1
	local ok, cmd = pcall(api.cmd.makeCustomEntityUpdateStateCmd, run.ghost, {
		speed01 = speed01,
		power01 = power,
		state = {
			speed = speed, power = power, vx = vx, vy = vy,
			color = run.color,
			dist = run.gdist or 0.0,
			seg = run.seg,
			dir = dir,
			track = run.track,
		},
	})
	run.pushedDir = dir
	if ok then
		api.cmd.sendCommand(cmd)
		run.lastSpeed = speed
		run.stateAge = 0.0
		run.segChanged = false
	end
end

-- The colour that tells the wrapped transformator to draw a real carriage as
-- nothing (it is unlikely to be anyone's paint; see ghost_real.script.lua).
local HIDE_COLOUR = { 0.1234567, 0.7654321, 0.3141593 }
local function hideColour() return api.type.Vec3f.new(HIDE_COLOUR[1], HIDE_COLOUR[2], HIDE_COLOUR[3]) end

-- The loco never leaves the train: it is hidden in its place while its ghost runs
-- around, and shown again at the recouple. Taking it out (for an invisible
-- stand-in, as before) made each vehicle replace sell it and buy it back, with
-- the money shown in the world (seen live): a replace is the game's "replace
-- vehicles", which charges for parts it adds and refunds parts it removes. Now
-- every replace only repaints, reorders or turns parts the train already has.

-- The train's own loco part (its model and purchase time).
local function isLocoPart(part, locoSnap)
	return part.part.modelId == locoSnap.modelId and part.purchaseTime == locoSnap.purchaseTime
end

-- The loco for the recouple: the train's own loco part, with its paint back and
-- the given facing (nothing bought). nil if it is no longer on the train (the
-- player rebuilt the train by hand mid-run): nothing is added then - building a
-- new one would buy it - and the train is left as it is, coaches shown again.
local function locoForRecouple(config, locoSnap, reversed)
	for _, part in ipairs(config.vehicles) do
		if isLocoPart(part, locoSnap) then
			part.part.reversed = reversed
			if locoSnap.color ~= nil then part.part.color = api.type.Vec3f.new(locoSnap.color.x, locoSnap.color.y, locoSnap.color.z) end
			return part
		end
	end
	logInfo("recouple: the loco is no longer on the train (rebuilt by hand?) - nothing is added; the train is left as it is")
	return nil
end

-- The train with its loco hidden in place, everything else as it is.
local function buildConfigWithHiddenLoco(tvc, locoIdx)
	local config = api.type.TransportVehicleConfig.new(tvc)
	local parts = {}
	for i, part in ipairs(config.vehicles) do
		if i == locoIdx then part.part.color = hideColour() end
		parts[#parts + 1] = part
	end
	return finishConfig(config, parts)
end

-- The train with the hidden loco slot taken out and the loco put back at one
-- end. A loco cannot pass through its consist, so it can only couple onto the
-- end it arrives at (see chooseAttachEnd). It then faces OUTWARD, away from the
-- wagons, so that it can pull them: a loco at the front of the parts list is not
-- reversed, one at the rear is.
--
-- origRev (the wagons' original reversed flags, in original order) is given
-- after a flip: the loco goes at the head and the wagons are re-listed in the
-- opposite order with their flags toggled, which is exactly the flip's mirror
-- undone, so every wagon ends up where it stood and facing as it did.
local function buildConfigWithLocoReattached(currentTvc, locoSnap, attachAtRear, locoReversed, origRev)
	local config = api.type.TransportVehicleConfig.new(currentTvc)
	if locoReversed == nil then locoReversed = attachAtRear end
	local loco = locoForRecouple(config, locoSnap, locoReversed)
	local wagons = {}
	for _, part in ipairs(config.vehicles) do
		if not isLocoPart(part, locoSnap) then wagons[#wagons + 1] = part end
	end
	if origRev ~= nil then
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
	for _, part in ipairs(wagons) do parts[#parts + 1] = part end
	if attachAtRear then parts[#parts + 1] = loco end
	return finishConfig(config, parts)
end

-- Reads the loco's current world transform off the live carriage entity (the
-- carriage list is in the same order as the config's parts: seen live, the ghost
-- appears exactly where the loco stood).
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
local PULL_BRAKE = 0.5         -- m/s^2: braking as the train draws up before the uncouple
local CLEAR_M = 10.0          -- a reversal happens this far into the track piece, i.e. just clear of the points, not at the piece's end
local STATES = { { true, true }, { true, false }, { false, true }, { false, false } } -- {arrive dir, depart dir}
-- How far the loco may stand from the planned route and still count as on it:
-- half the game's spacing between parallel tracks (trackDistance = 5 m for every
-- track type). On the planned platform the loco stands on the route (about 0 m);
-- on any other platform it is a whole track spacing away. Also how near the
-- way back to the station must pass the loco's coupling place.
local ON_ROUTE_M = 2.5

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

-- Unit direction of travel where a piece is entered (atEnd false) or left.
local function travelDir(e, atEnd)
	local g = getEdgeGeometry(e)
	local calc = api.engine.util.transport.calcPosition
	local nearHigh = (atEnd == e.forward) -- the end of the piece at u = 1
	local pa = calc(g, nearHigh and 0.95 or 0.0)
	local pb = calc(g, nearHigh and 1.0 or 0.05)
	local dx, dy = pb.x - pa.x, pb.y - pa.y
	if not e.forward then dx, dy = -dx, -dy end
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1e-9 then return nil end
	return dx / d, dy / d
end

-- Whether a run of pieces doubles back on itself at a node (a hairpin from one
-- branch of a set of points to the other), which no train can do. A pathfinder
-- route that starts at a node doesn't know which piece the loco came in on, so
-- it can turn back there. A reversal (the same piece taken back) is fine.
local function hasHairpin(edges)
	for i = 2, #edges do
		local a, b = edges[i - 1], edges[i]
		if not sameEdge(a, b) then
			local ok, bad = pcall(function()
				local ax, ay = travelDir(a, true)
				local bx, by = travelDir(b, false)
				return ax ~= nil and bx ~= nil and ax * bx + ay * by < 0.0
			end)
			if ok and bad then return true end
		end
	end
	return false
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
	if hasHairpin(out) then return nil, "the only route doubles back at a set of points" end
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
	if hasHairpin(out) then return nil, "the only route doubles back at a set of points" end
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
					if p2 ~= nil and (b == nil or endsAlong(p2, b, dB)) then
						local raw = {}
						for _, e in ipairs(firstEdges) do raw[#raw + 1] = e end
						for _, e in ipairs(p1) do raw[#raw + 1] = e end
						raw[#raw + 1] = { entity = c.entity, index = c.index, forward = not c.forward }
						for _, e in ipairs(p2) do raw[#raw + 1] = e end
						local cost = edgesCost(raw) + REVERSAL_PENALTY
						if cost < bestCost and not hasHairpin(raw) then best, bestCost = raw, cost end
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

-- Edges from piece a (leaving in direction dA, a included) to a track node.
local function legToNode(a, dA, node)
	local ea = getTnEdge(a.entity, a.index)
	if ea == nil then return nil, "a clicked track piece no longer exists" end
	local mid, err = pathBetweenNodes(dA and ea.conns[2] or ea.conns[1], node)
	if mid == nil then return nil, err end
	local raw = { { entity = a.entity, index = a.index, forward = dA } }
	for _, e in ipairs(mid) do raw[#raw + 1] = e end
	local out = dedupeEdges(raw)
	if hasHairpin(out) then return nil, "the only route doubles back at a set of points" end
	return out
end

-- Same, or, if there is none, one with an automatically chosen reversing place.
local function legToNodeAuto(a, dA, node, nodePos)
	local edges, err = legToNode(a, dA, node)
	if edges ~= nil then return edges end
	local ea = getTnEdge(a.entity, a.index)
	if ea == nil then return nil, err end
	local first = { { entity = a.entity, index = a.index, forward = dA } }
	local raw = findCuspLeg(first, dA and ea.conns[2] or ea.conns[1], node, nil, nil, { piecePos(first[1], dA and 1.0 or 0.0), nodePos })
	if raw == nil then return nil, err end
	return dedupeEdges(raw)
end

-- backTo: a track node (the station stop) the route goes on to after the last
-- point, so that the loco also sets back onto its coaches along the track
-- (the "way back"); nil for a route that ends at the last point.
local function planRouteTo(waypoints, startNode, startPos, backTo)
	local n = #waypoints
	if n < 2 then return nil, "need at least 2 points" end

	local memo = {}
	local back = {}
	if backTo ~= nil then
		for _, d in ipairs({ true, false }) do
			local edges = legToNodeAuto(waypoints[n], d, backTo, startPos)
			back[d] = { edges = edges, cost = edges and edgesCost(edges) or math.huge }
		end
	end
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
			if i == n and a ~= d and backTo == nil then
				best[i][s] = math.huge -- departure at the last point is meaningless
			else
				local penalty = (a ~= d) and REVERSAL_PENALTY or 0
				if i == n and backTo ~= nil then penalty = penalty + back[d].cost end
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
	local backFrom = nil
	if backTo ~= nil then
		local before = #route
		append(back[STATES[chosen[n]][2]].edges)
		if #route > before then backFrom = before + 1 end
	end
	return route, { length = endCost, reversals = reversals, backFrom = backFrom }
end

-- Best route through all waypoints and then back to the station stop; if there
-- is no way back from the last point, the route ends there as before.
local function planRoute(waypoints, startNode, startPos)
	if startNode ~= nil then
		local route, info = planRouteTo(waypoints, startNode, startPos, startNode)
		if route ~= nil then return route, info end
	end
	return planRouteTo(waypoints, startNode, startPos, nil)
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
local ROUTE_VERSION = 2 -- 2: the route goes on back to the station stop (loop.backFrom)

local function recomputeLoopRoute(loop)
	loop.waypoints = loop.waypoints or {}
	loop.routeLength, loop.routePieces, loop.routeReversals = nil, nil, nil
	loop.backFrom = nil
	loop.routeVersion = ROUTE_VERSION
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
	-- where the way back to the station starts (the last pieces), or nil
	loop.backFrom = info.backFrom
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
	loop.pathStatus = string.format("%d points, %d track pieces, %d reversal(s), about %d m%s", #loop.waypoints, #route, info.reversals, math.floor(info.length),
		info.backFrom and ", back to the station" or "")
	logInfo("route for loop", loopLabel(loop), "-", loop.pathStatus)
end

-- The distance the ghost will drive from piece k0, off0 metres into it, to the
-- route's end, by advanceGhost's own rules: a piece driven back over (a reversal)
-- is only driven CLEAR_M into, not to its far end. For the card's progress bar
-- (the route's length counts such pieces twice in full). nil if unreadable.
-- The stretch of each piece the ghost drives, from piece k0 (off0 metres in) to
-- the route's end: { k, from, to, len } per piece, in metres along the way of
-- travel. nil if a piece is unreadable.
local function drivenRanges(loop, k0, off0)
	local out, startOffset = {}, off0
	for k = k0 or 1, #loop.loopEdges do
		local e = loop.loopEdges[k]
		local ok, len = pcall(function() return estimateEdgeLength(getEdgeGeometry(e)) end)
		if not ok then return nil end
		local from, to = startOffset or 0.0, len
		startOffset = nil
		local nextDef = loop.loopEdges[k + 1]
		if nextDef ~= nil and nextDef.reversal and sameEdge(nextDef, e) and len > CLEAR_M * 1.5 then
			to = math.max(CLEAR_M, from + 1.0)
			startOffset = len - to
		end
		out[#out + 1] = { k = k, from = from, to = math.max(to, from), len = len }
	end
	return out
end

local function routeDriveLength(loop, k0, off0)
	local ranges = drivenRanges(loop, k0, off0)
	if ranges == nil then return nil end
	local total = 0.0
	for _, r in ipairs(ranges) do total = total + (r.to - r.from) end
	return total
end

-- On the way back to the station (from piece k0, off0 metres in), the point the
-- ghost drives over that is nearest pos (where the loco couples on): the
-- distance driven to reach it, and how far it is from pos. nil if unreadable.
local function locateOnWayBack(loop, k0, off0, pos)
	local ranges = drivenRanges(loop, k0, off0)
	if ranges == nil then return nil end
	local calc = api.engine.util.transport.calcPosition
	local bestAt, bestD2, driven = nil, math.huge, 0.0
	for _, r in ipairs(ranges) do
		local edgeDef = loop.loopEdges[r.k]
		local ok, geometry = pcall(getEdgeGeometry, edgeDef)
		if not ok then return nil end
		local span = r.to - r.from
		local steps = math.max(4, math.min(2000, math.ceil(span / 0.25))) -- every 25 cm
		for i = 0, steps do
			local s = r.from + span * i / steps
			local along = r.len > 0 and s / r.len or 0.0
			local p = calc(geometry, edgeDef.forward and along or (1.0 - along))
			local d2 = (p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2
			if d2 < bestD2 then bestAt, bestD2 = driven + (s - r.from), d2 end
		end
		driven = driven + span
	end
	if bestAt == nil then return nil end
	return bestAt, math.sqrt(bestD2)
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
	-- (not on the way back to the station: after a loop with no reversal that
	-- runs over the platform again)
	local last = math.min(#edges, 120, (loop.backFrom or math.huge) - 1)
	for k = 1, last do
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


-- The route is done: with the flip enabled the train is flipped next and the
-- ghost then glides to where the loco goes back on; without it, the run ends.
local function routeFinished(run)
	if run.rake ~= nil and run.phase == nil then
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

-- The middle of a model's extent along x (its length), or nil. A model's
-- origin need not be there: the Su's is 4.65 m off, the Black 5's 3.55 m.
local function extentCentreX(modelId)
	local function x(v)
		if v == nil then return nil end
		local ok, r = pcall(function() return v.x end)
		if ok and type(r) == "number" then return r end
		ok, r = pcall(function() return v[1] end)
		return (ok and type(r) == "number") and r or nil
	end
	local lo, hi = x(modelMeta(modelId, "extent", "bbMin")), x(modelMeta(modelId, "extent", "bbMax"))
	if lo == nil or hi == nil then return nil end
	return (lo + hi) / 2
end

-- Where the loco's origin will be when it is shown again, facing as the copy
-- does now. When a vehicle is turned round in a train, the engine keeps its
-- extent where it is, so its origin moves to the other side of the extent's
-- middle. The copy used to stop on the hidden loco's origin (which faces the
-- other way after a run-around), twice that offset short of the coaches, and
-- jumped onto them at the recouple (seen live: about 9 m with the Su).
local function placeTarget(run)
	local h = run.hiddenLoco
	if h == nil or h.yaw == nil or run.gyaw == nil then return end
	local cx = run.locoPart and extentCentreX(run.locoPart.modelId) or nil
	local hx, hy = math.cos(h.yaw), math.sin(h.yaw)
	local same = hx * math.cos(run.gyaw) + hy * math.sin(run.gyaw) >= 0
	local shift = (cx ~= nil and not same) and 2 * cx or 0.0
	run.target = { x = h.x + shift * hx, y = h.y + shift * hy, z = h.z }
	if not run.targetLogged then
		run.targetLogged = true
		logInfo(string.format("coupling place: %s - the loco's origin %.2f m from the hidden loco's", same and "facing as the hidden loco" or "turned round from the hidden loco", math.abs(shift)))
	end
end

-- Glide in a straight line to run.target (the hidden loco, after the flip: where the loco
-- goes back on), braking evenly to a stop there. The facing stays as it was.
local function advanceApproach(run, dt)
	if run.approachDecel == nil then placeTarget(run) end
	local dx, dy, dz = run.target.x - run.gx, run.target.y - run.gy, run.target.z - run.gz
	local dist = math.sqrt(dx * dx + dy * dy)
	if run.approachDecel == nil then
		-- Set off at the route speed and brake at a constant rate to stop at the
		-- hidden loco (the wheel animation follows the same motion).
		-- (after setting back along the track, only what is left, at a crawl)
		local v0 = run.backStopped and 0.5 or math.max(run.loopSpeed or CONFIG.defaultSpeed, 1.0)
		run.approachDecel = (dist > 0.1) and (v0 * v0 / (2.0 * dist)) or 1.0
		if dist > 0.1 then -- (a few centimetres say nothing about the direction)
			run.approachBackwards = (dx * math.cos(run.gyaw or 0.0) + dy * math.sin(run.gyaw or 0.0)) < 0.0
		end
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

-- Where the flipped train's head part (the hidden loco) is, or nil.
local function readHeadPosition(vehicleEntity)
	local ok, c = pcall(function()
		local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
		return carriagePos(cl.carriages[1])
	end)
	if ok then return { x = c.x, y = c.y, z = c.z } end
	return nil
end

-- Phases the watchdog leaves alone: already ending, or held on purpose.
local WATCHDOG_SKIP = { finish = true, done = true, verify = true, retry = true, stuck = true }

-- Every stage waits for a command callback or a position, and if one never comes
-- the train would stay held for ever. So: a run whose train has gone, or that has
-- taken longer than watchdogFactor times its route at the loop's speed plus
-- watchdogExtraSeconds, is sent to "finish", and finishRun puts the real train
-- back (or clears the ghosts, if the train has gone) and releases it.
local function watchdog(run, dt)
	if WATCHDOG_SKIP[run.phase or ""] then return end
	local okTv, tv = pcall(api.engine.getComponent, run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if okTv and tv == nil then
		logInfo("watchdog: vehicle", run.vehicleEntity, "has gone mid-run - clearing its ghosts")
		run.phase, run.aborted = "finish", true
		return
	end
	run.age = (run.age or 0.0) + dt
	if run.timeLimit == nil then
		local loop = run.loop or {}
		local speed = math.max(loop.speed or CONFIG.defaultSpeed, 1.0)
		run.timeLimit = (loop.routeLength or 1000.0) / speed * CONFIG.watchdogFactor + CONFIG.watchdogExtraSeconds
	end
	if run.age > run.timeLimit then
		logInfo(string.format("watchdog: the run-around for vehicle %s has stalled (%.0f s, limit %.0f s; phase %s, ghost rake %s) - putting the real train back",
			tostring(run.vehicleEntity), run.age, run.timeLimit, tostring(run.phase or "route"), tostring(run.rake and run.rake.stage)))
		run.phase, run.aborted = "finish", true
	end
end

-- The track under the loco copy, for ghost_real to put its tender and bogies on
-- (a free entity gets no help from the engine there): points every TRACK_STEP
-- metres from -TRACK_HALF to +TRACK_HALF along the copy's facing, in its own
-- frame. They follow the route both ways from where the copy is, onto the next
-- or previous piece where that joins on (not across a reversal: there the
-- piece the copy is on goes on, and beyond its ends the track runs straight).
local TRACK_HALF, TRACK_STEP = 16.0, 2.0
local pieceLengths = {}
local function pieceLength(e)
	local key = tostring(e.entity) .. ":" .. tostring(e.index)
	local len = pieceLengths[key]
	if len == nil then
		len = estimateEdgeLength(getEdgeGeometry(e))
		pieceLengths[key] = len
	end
	return len
end
-- t metres along piece e in its direction of travel
local function piecePoint(e, len, t)
	local u = len > 0 and t / len or 0.0
	return api.engine.util.transport.calcPosition(getEdgeGeometry(e), e.forward and u or (1.0 - u))
end
local function beyondPiece(e, len, t0, extra)
	local p = piecePoint(e, len, t0)
	local q = piecePoint(e, len, (t0 > 0) and math.max(t0 - 1.0, 0.0) or math.min(1.0, len))
	local dx, dy = p.x - q.x, p.y - q.y
	if t0 <= 0 then dx, dy = -dx, -dy end
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1e-6 then return p end
	local sign = (t0 > 0) and 1 or -1
	return { x = p.x + dx / d * extra * sign, y = p.y + dy / d * extra * sign, z = p.z }
end
local function joins(a, b) return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < 0.25 end
-- The point d metres on (back, if negative) along the route from piece k, p
-- metres into it.
local function routePointFrom(edges, k, p, d)
	for _ = 1, 32 do
		local e = edges[k]
		local len = pieceLength(e)
		local t = p + d
		if t >= 0.0 and t <= len then return piecePoint(e, len, t) end
		if t > len then
			local j = k + 1
			while edges[j] ~= nil and sameEdge(edges[j], e) do j = j + 1 end
			local nxt = edges[j]
			if nxt == nil or not joins(piecePoint(nxt, pieceLength(nxt), 0.0), piecePoint(e, len, len)) then
				return beyondPiece(e, len, len, t - len)
			end
			k, p, d = j, 0.0, t - len
		else
			local j = k - 1
			while edges[j] ~= nil and sameEdge(edges[j], e) do j = j - 1 end
			local prv = edges[j]
			if prv == nil or not joins(piecePoint(prv, pieceLength(prv), pieceLength(prv)), piecePoint(e, len, 0.0)) then
				return beyondPiece(e, len, 0.0, -t)
			end
			k, p, d = j, pieceLength(prv), t
		end
	end
	return nil
end
local function trackStrip(run, loop, facingSign)
	local edges = loop.loopEdges
	if run.gx == nil or run.gyaw == nil or edges[run.edgeCursor] == nil then return nil end
	local c, s = math.cos(run.gyaw), math.sin(run.gyaw)
	local pts = {}
	for x = -TRACK_HALF, TRACK_HALF + 1e-6, TRACK_STEP do
		local w = routePointFrom(edges, run.edgeCursor, run.edgeProgress or 0.0, x * facingSign)
		if w == nil then return nil end
		local dx, dy = w.x - run.gx, w.y - run.gy
		pts[#pts + 1] = math.floor((c * dx + s * dy) * 1000 + 0.5) / 1000
		pts[#pts + 1] = math.floor((-s * dx + c * dy) * 1000 + 0.5) / 1000
	end
	return { s0 = -TRACK_HALF, ds = TRACK_STEP, pts = pts }
end

-- Advances one run by dt seconds. Returns true when the run needs its next
-- step done in postUpdate (recouple, or the facing check after it).
local function advanceGhost(run, dt)
	local loop = run.loop
	if run.phase == "flip" then return false end -- waiting for the train to be flipped
	if run.phase == "settle" then
		-- Just after a flip the carriages still report their old positions for a
		-- tick or two: wait, then read where the hidden loco (now the head) is.
		run.settleTicks = (run.settleTicks or 0) + 1
		if run.settleTicks >= 4 then
			run.target = readHeadPosition(run.vehicleEntity)
			local okF, frames = pcall(carriageFrames, run.vehicleEntity)
			if run.target ~= nil and okF and frames[1] ~= nil then
				run.hiddenLoco = { x = run.target.x, y = run.target.y, z = run.target.z, yaw = frames[1].yaw }
			end
			-- (the ghost goes onto the hidden loco itself)
			if run.target ~= nil then
				run.phase = "approach"
				logInfo(string.format("ghost heading for the hidden loco at %.1f, %.1f", run.target.x, run.target.y))
			else
				logInfo("could not read the hidden loco's position after the flip - it is shown again where it is")
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
	if run.phase == "approach" then return advanceApproach(run, dt) end
	if run.phase == "verify" then
		run.verifyWait = (run.verifyWait or 0) + 1
		return run.verifyWait >= 4
	end
	if run.phase == "retry" or run.phase == "stuck" then -- the recouple failed (see recoupleFailed)
		run.retryWait = (run.retryWait or 0) - dt
		return run.retryWait <= 0
	end
	if run.phase == "done" or run.phase == "finish" then return true end

	-- Ghost rake: first the train draws forward a loco length with the loco still
	-- coupled (the coach ghosts follow the loco ghost, see advanceRake), stops and
	-- the loco uncouples; only then does it set off round the route. Until then it
	-- stands: while the hidden train is turned, after the pull, while uncoupling.
	local R = run.rake
	local pullLeft = nil
	if R ~= nil and run.phase == nil and R.stage ~= "done" and R.stage ~= "failed" then
		if R.stage == "pull" then pullLeft = math.max(R.pullTo - (run.gdist or 0.0), 0.0) end
		if pullLeft == nil or pullLeft <= 1e-4 then
			run.speed = 0.0
			if run.seg == nil or run.seg.acc ~= 0.0 or run.seg.v0 ~= 0.0 then startSegment(run, 0.0, 0.0, 0.0) end
			pushGhostState(run, 0.0, 0.0, 0.0, dt)
			return false
		end
	end

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
	if run.edgeLength == nil and run.edgeCursor == loop.backFrom and run.backStop == nil then
		-- The way back to the station: driven along the track to where the loco
		-- couples on, when that is known (the ghost rake) and on the way back.
		local why = nil
		if run.rake == nil or run.rake.stage ~= "done" or run.target == nil then
			why = "where the loco couples on isn't known yet"
		else
			placeTarget(run)
			local okB, at, off = pcall(locateOnWayBack, loop, run.edgeCursor, run.startOffset, run.target)
			if not okB or at == nil then
				why = "the way back could not be read: " .. tostring(at)
			elseif off > ON_ROUTE_M then
				why = string.format("the coaches are %.1f m from the way back", off)
			else
				run.backStop = (run.gdist or 0.0) + at
				run.driveTotal = run.backStop
				logInfo(string.format("way back: the loco sets back %.1f m along the track to its coaches (%.2f m off the track there)", at, off))
			end
		end
		if why ~= nil then
			logInfo("way back: glided instead -", why)
			run.edgeCursor = #loop.loopEdges + 1
			return routeFinished(run)
		end
	end
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
	local vmax = loop.speed
	if pullLeft ~= nil then vmax = math.min(loop.speed, CONFIG.rakePullSpeed) end
	if run.speed == 0.0 and (run.seg == nil or run.seg.acc == 0.0) then
		startSegment(run, 0.0, loop.accel, vmax)
	end
	run.speed = math.min(vmax, run.speed + loop.accel * dt)
	local advance = run.speed * dt
	if pullLeft ~= nil then
		-- drawing forward: brake evenly to stop exactly a loco length on
		local brakeSpeed = math.sqrt(2.0 * PULL_BRAKE * pullLeft)
		if brakeSpeed < run.speed then
			if not run.pullBraking then
				run.pullBraking = true
				startSegment(run, run.speed, -PULL_BRAKE, 0.0)
			end
			run.speed = math.max(brakeSpeed, 0.2)
		end
		advance = math.min(run.speed * dt, pullLeft)
	end
	if run.backStop ~= nil then
		-- setting back onto the coaches: brake evenly to stop at them
		local left = math.max(run.backStop - (run.gdist or 0.0), 0.0)
		local brake = loop.accel or CONFIG.defaultAccel
		local brakeSpeed = math.sqrt(2.0 * brake * left)
		if brakeSpeed < run.speed then
			if not run.backBraking then
				run.backBraking = true
				startSegment(run, run.speed, -brake, 0.0)
			end
			run.speed = math.max(brakeSpeed, 0.2)
		end
		advance = math.min(run.speed * dt, left)
	end
	local endAt = run.edgeLimit or run.edgeLength
	local before = run.edgeProgress
	run.edgeProgress = math.min(run.edgeProgress + advance, endAt)
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
	-- the facing against the way of travel: driving backwards, or facing back
	local against = ((run.headingFlipped and 1 or 0) + (((run.yawOffset or 0) > 1) and 1 or 0)) % 2 == 1
	local okT, strip = pcall(trackStrip, run, loop, against and -1 or 1)
	run.track = okT and strip or nil
	pushGhostState(run, run.speed, pvx, pvy, dt)

	api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(run.ghost, transf))

	if run.backStop ~= nil and run.backStop - run.gdist <= 1e-3 then
		run.backStopped = true
		run.edgeCursor = #loop.loopEdges + 1
		return routeFinished(run)
	end

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
	-- guarded: a train deleted mid-run would make the command throw inside a callback
	pcall(function() api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(vehicleEntity, false)) end)
	pcall(function() api.cmd.sendCommand(api.cmd.makeVehicleSetStoppedByUserCmd(vehicleEntity, false)) end)
end

-- Keeps the train where it is. Sent again after every flip and replace: after a
-- flip the train crept 18 m towards the exit on its two 1 kW stand-ins before the
-- loco came back (traced live).
local function holdTrain(vehicleEntity)
	pcall(function() api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(vehicleEntity, true)) end)
	pcall(function() api.cmd.sendCommand(api.cmd.makeVehicleSetStoppedByUserCmd(vehicleEntity, true)) end)
end

-- True to attach at the rear (last part) of the consist, false for the front
-- (first part): whichever end is nearer the last route point the user clicked,
-- since that is where the loco has just arrived. Also returns a description
-- for the log.
local function chooseAttachEnd(vehicleEntity, loop, tvc, locoSnap)
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
	-- The hidden loco is about to be moved to an end, so the ends that matter are
	-- those of the wagons.
	local first, last = nil, nil
	for i, part in ipairs(tvc.vehicles) do
		if not isLocoPart(part, locoSnap) then
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

-- Removes the coach ghosts (ghost rake) that are still up. Called wherever a run
-- ends or fails to start, so none is left standing in the world.
local function destroyCoachGhosts(coaches)
	for _, c in ipairs(coaches or {}) do
		if c.ghost ~= nil then
			local ghost = c.ghost
			c.ghost = nil
			pcall(function() api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(ghost)) end)
		end
	end
end

-- Ends a run: the ghost goes, the train is released. The game reports the train
-- arriving at the same stop again straight after (traced live: OnArriveAtStop at
-- the same second, the train not having moved), so the stop is remembered and
-- such an arrival ignored (see handleEvent) - it had turned the train, and the
-- second run picked a coach as the loco.
local function finalizeRun(state, run)
	local data = state:get()
	if data ~= nil and run.loop ~= nil then
		data.ranAt = data.ranAt or {}
		data.ranAt[tostring(run.vehicleEntity)] = { line = run.loop.lineEntity, stop = run.loop.stopIndex }
		state:set(data)
	end
	if not run.ghostGone and run.ghost ~= nil then api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost)) end
	releaseTrain(run.vehicleEntity)
	api.cmd.sendCommand(api.cmd.makeVehicleTryToDepartCmd(run.vehicleEntity))
	if run.restore then
		logInfo("train put back as it was for vehicle", run.vehicleEntity, "loop", loopLabel(run.loop), "- no run-around this time")
	else
		logInfo("run-around complete for vehicle", run.vehicleEntity, "loop", loopLabel(run.loop))
	end
end

-- The loco could not be shown again. Releasing the train now would send it off
-- invisible (with hidden coaches, after a ghost rake), so it
-- stays held with its ghosts up and the recouple is tried again: a few times
-- soon, then every stuckRetrySeconds for as long as the train exists. The card
-- shows "stuck" meanwhile (see runaround_gui.script.lua).
local function recoupleFailed(state, run, why)
	run.recoupleTries = (run.recoupleTries or 0) + 1
	local stuck = run.recoupleTries >= CONFIG.recoupleRetries
	run.phase = stuck and "stuck" or "retry"
	run.retryWait = stuck and CONFIG.stuckRetrySeconds or CONFIG.recoupleRetrySeconds
	logInfo("recouple FAILED for vehicle", run.vehicleEntity, "loop", loopLabel(run.loop), "-", why, "- try", run.recoupleTries,
		"- train held, trying again in", run.retryWait, "s", stuck and "(STUCK: the loco is not on the train)" or "")
	holdTrain(run.vehicleEntity)
	local data = state:get()
	data.runs[#data.runs + 1] = run
	state:set(data)
end

local function recouple(state, run, tv, atRear, locoReversed, why, origRev)
	logInfo("recouple: the loco shown again at the", atRear and "REAR" or "FRONT", "of the consist,", locoReversed and "reversed" or "not reversed", "-", why)

	local okBuild, newConfig = pcall(buildConfigWithLocoReattached, tv.transportVehicleConfig, run.locoPart, atRear, locoReversed, origRev)
	if not okBuild then
		return recoupleFailed(state, run, "could not build the new consist: " .. tostring(newConfig))
	end
	local okCmd, cmd = pcall(makeReplaceCmd, run.vehicleEntity, newConfig)
	if not okCmd then
		return recoupleFailed(state, run, "replace command rejected: " .. tostring(cmd))
	end

	local moneyBefore = playerBalance()
	api.cmd.sendCommand(cmd, function(_, success)
		if not success then
			return recoupleFailed(state, run, "replace refused")
		end
		logMoneyChange("the recouple", moneyBefore)
		scheduleTrace(state, "after the recouple (+1 tick)", run.vehicleEntity, 1)
		scheduleTrace(state, "after the recouple (+3 ticks)", run.vehicleEntity, 3)
		-- The ghost goes at once: the real loco is on the train now, and leaving the
		-- ghost up while the facing is verified showed two locos for a moment.
		if not run.ghostGone and run.ghost ~= nil then api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost)) end
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
			finalizeRun(state, run)
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

-- Edits one run in the saved state (a run handed to postUpdate is a copy). A run
-- the watchdog has taken over (aborted) is left alone: a late callback from a
-- command sent before that must not set it going again.
local function updateRun(state, vehicleEntity, fn)
	local data = state:get()
	local found = false
	for _, r in ipairs(data.runs) do
		if r.vehicleEntity == vehicleEntity and not r.aborted then fn(r); found = true end
	end
	state:set(data)
	return found
end



-- The game flips a train that has to leave a terminus by the way it came (it
-- mirrors the consist end for end and keeps the parts list order), and it does
-- that at departure. A loco coupled on at the exit end was therefore flipped
-- straight back to the buffer end (seen live). So the train is flipped HERE
-- (game's own reverse command), while the loco on it is hidden: the head then
-- faces the exit and the hidden loco sits at the exit end. The ghost then glides
-- onto it (position read off the live carriage) and it is shown again, so nothing
-- snaps and nothing is flipped at departure. Live run: parts order is preserved
-- by the flip.
local function flipRun(state, vehicleEntity)
	local function fail(reason)
		logInfo("flip failed (", reason, ") - the loco will be put back without flipping")
		updateRun(state, vehicleEntity, function(r) r.phase = "done" end)
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
		finalizeRun(state, run)
		return
	end
	local dot = math.cos(run.gyaw) * math.cos(yaw) + math.sin(run.gyaw) * math.sin(yaw)
	logInfo(string.format("verify: loco facing against ghost facing, dot = %.2f", dot))
	if dot >= 0 or run.corrected then
		finalizeRun(state, run)
		return
	end
	local okFix, cmd = pcall(function()
		local tv = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
		local config = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
		local parts = {}
		for i, part in ipairs(config.vehicles) do parts[i] = part end
		local idx = run.locoAtRear and #parts or 1
		parts[idx].part.reversed = not parts[idx].part.reversed
		return makeReplaceCmd(run.vehicleEntity, finishConfig(config, parts))
	end)
	if not okFix then
		logInfo("verify: could not turn the loco round:", tostring(cmd))
		finalizeRun(state, run)
		return
	end
	logInfo("verify: the loco faces the wrong way, flipping its reversed flag")
	api.cmd.sendCommand(cmd, function(_, success)
		if not success then logInfo("verify: the correction was refused") end
		finalizeRun(state, run)
	end)
end

local recoupleRake -- defined with the ghost rake, below

local function finishRun(state, run)
	local tv = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		logInfo("finishRun: vehicle", run.vehicleEntity, "no longer exists, clearing its ghosts")
		if not run.ghostGone and run.ghost ~= nil then api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost)) end
		run.ghostGone = true
		destroyCoachGhosts(run.rake and run.rake.coaches)
		return
	end
	if run.rake ~= nil then
		return recoupleRake(state, run) -- also when it failed: the real train goes back
	end
	if run.restore then
		-- The run never got going: the loco goes back where it was, facing as it did.
		local atRear = run.locoIdx ~= nil and run.locoIdx > 1 and run.locoIdx == run.partCount
		recouple(state, run, tv, atRear, run.startReversed, "putting the train back as it was")
		return
	end
	local reversed, why = locoIsReversed(run)
	if run.flipped then
		-- Head faces the exit and the hidden loco is the head part: shown there.
		local restore = run.origRev or {}
		recouple(state, run, tv, false, reversed, "train was flipped first, loco takes the head; " .. tostring(why), restore)
		return
	end
	local okEnd, atRear, endWhy = pcall(chooseAttachEnd, run.vehicleEntity, run.loop, tv.transportVehicleConfig, run.locoPart)
	if not okEnd then
		logInfo("could not work out which end to attach at (", tostring(atRear), ") - defaulting to the rear")
		atRear, endWhy = true, "fallback"
	end
	recouple(state, run, tv, atRear, reversed, "no flip; " .. tostring(endWhy) .. "; " .. tostring(why))
end

-- ---------------------------------------------------------------------
-- Ghost rake (see CONFIG.ghostRake)
-- ---------------------------------------------------------------------



-- The train while its ghosts are shown: the loco hidden in its place, then the
-- REAL coaches, hidden, in reverse order and turned. After the flip that is, from
-- the new head, loco then last coach ... first coach, each facing as it did: the
-- train the loco couples back onto, with nothing taken out of it or added to it.
local function buildHiddenRakeConfig(tvc)
	local config = api.type.TransportVehicleConfig.new(tvc)
	local loco = config.vehicles[1]
	loco.part.color = hideColour()
	local parts = { loco }
	for i = #config.vehicles, 2, -1 do
		local part = config.vehicles[i]
		part.part.reversed = not part.part.reversed
		part.part.color = hideColour()
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
	local loco = locoForRecouple(config, locoSnap, locoReversed)
	for _, part in ipairs(config.vehicles) do
		if not isLocoPart(part, locoSnap) then
			local idx, c = matchCoach(part, coaches)
			if c ~= nil and c.snap.color ~= nil then
				part.part.color = api.type.Vec3f.new(c.snap.color.x, c.snap.color.y, c.snap.color.z)
			end
			found[#found + 1] = { part = part, idx = idx or (#found + 1), c = c }
		end
	end
	local parts = { loco }
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

-- Where a coach ghost is, a fraction f of the way through the pull, and its yaw.
-- It moves along a cubic Hermite curve that leaves its start along the track (the
-- start's axis) and arrives along it (the target's axis): close to the track on a
-- curved platform, and exactly the straight line on a straight one. It turns with
-- the curve and keeps its own facing. Only the target's axis is used (the hidden
-- coach beneath it may face either way); an axis more than 45 degrees off the
-- chord is not trusted, and the chord's direction is used instead.
local function pullFrame(c, f)
	local s, t = c.start, c.target
	local dx, dy = t.x - s.x, t.y - s.y
	local L = math.sqrt(dx * dx + dy * dy)
	local z = s.z + (t.z - s.z) * f
	if L < 0.01 then return s.x + dx * f, s.y + dy * f, z, s.yaw end
	local ux, uy = dx / L, dy / L
	-- a tangent along the direction of travel, scaled by the chord length
	local function tangent(yaw)
		local tx, ty = math.cos(yaw), math.sin(yaw)
		local dot = tx * ux + ty * uy
		if math.abs(dot) < 0.7071 then tx, ty, dot = ux, uy, 1 end
		if dot < 0 then tx, ty = -tx, -ty end
		return tx * L, ty * L
	end
	local t0x, t0y = tangent(s.yaw)
	local t1x, t1y = tangent(t.yaw)
	local f2, f3 = f * f, f * f * f
	local h00, h10, h01, h11 = 2 * f3 - 3 * f2 + 1, f3 - 2 * f2 + f, -2 * f3 + 3 * f2, f3 - f2
	local d00, d10, d01, d11 = 6 * f2 - 6 * f, 3 * f2 - 4 * f + 1, -6 * f2 + 6 * f, 3 * f2 - 2 * f
	local x = h00 * s.x + h10 * t0x + h01 * t.x + h11 * t1x
	local y = h00 * s.y + h10 * t0y + h01 * t.y + h11 * t1y
	local vx = d00 * s.x + d10 * t0x + d01 * t.x + d11 * t1x
	local vy = d00 * s.y + d10 * t0y + d01 * t.y + d11 * t1y
	-- facing: the direction of travel, or half a turn from it for a coach that
	-- faced against the travel at the start
	local backwards = math.cos(s.yaw) * t0x + math.sin(s.yaw) * t0y < 0
	return x, y, z, math.atan2(vy, vx) + (backwards and math.pi or 0.0)
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
		-- Where everything will be: the hidden loco and coaches, the coaches ordered
		-- from the buffer end (where the loco stood) outwards, first to last.
		local ok, frames = pcall(carriageFrames, run.vehicleEntity)
		if not ok then R.stage = "failed" return false end
		local from = run.locoPos
		local coachFrames, locoFrame = {}, nil
		for _, f in ipairs(frames) do
			if f.modelId == run.locoPart.modelId then locoFrame = f else coachFrames[#coachFrames + 1] = f end
		end
		table.sort(coachFrames, function(a, b)
			return (a.x - from.x) ^ 2 + (a.y - from.y) ^ 2 < (b.x - from.x) ^ 2 + (b.y - from.y) ^ 2
		end)
		if locoFrame == nil or #coachFrames ~= #R.coaches then R.stage = "failed" return false end
		-- each ghost goes onto (and shows the load of) the hidden coach at its
		-- place: they must be the same model, or the pairing is wrong (M5)
		for i, c in ipairs(R.coaches) do
			if coachFrames[i].modelId ~= c.snap.modelId then
				logInfo("ghost rake: coach", i, "is model", c.snap.modelId, "but the hidden coach at its place is", coachFrames[i].modelId, "- putting the real train back")
				R.stage = "failed"
				return false
			end
		end
		for i, c in ipairs(R.coaches) do
			c.target = coachFrames[i]
			c.mirror = coachFrames[i].entity -- the real coach under this ghost: its load nodes
			pushCoachState(c, 0.0, nil)
		end
		run.target = { x = locoFrame.x, y = locoFrame.y, z = locoFrame.z }
		run.hiddenLoco = { x = locoFrame.x, y = locoFrame.y, z = locoFrame.z, yaw = locoFrame.yaw }
		-- The pull: the loco ghost draws forward along its route by as far as the
		-- coaches have to go (a loco length), and the coach ghosts go with it.
		local far, turn = 0, 0
		for _, c in ipairs(R.coaches) do
			c.slide = math.sqrt((c.target.x - c.start.x) ^ 2 + (c.target.y - c.start.y) ^ 2)
			c.dist0 = c.dist or 0.0
			if c.slide > far then far = c.slide end
			-- the angle between the start and target axes (pullFrame turns the ghost through it)
			local a = math.abs(math.atan2(math.sin(c.target.yaw - c.start.yaw), math.cos(c.target.yaw - c.start.yaw)))
			if a > math.pi / 2 then a = math.pi - a end
			if a > turn then turn = a end
		end
		R.pullLen = math.max(far, 0.01)
		R.gdist0 = run.gdist or 0.0
		R.pullTo = R.gdist0 + R.pullLen
		R.stage = "pull"
		logInfo(string.format("ghost rake: the train draws forward %.1f m (coaches turn up to %.1f degrees), then the loco uncouples",
			R.pullLen, math.deg(turn)))
		return false
	end
	if R.stage == "pull" then
		local f = ((run.gdist or 0.0) - R.gdist0) / R.pullLen
		if f < 0 then f = 0 elseif f > 1 then f = 1 end
		-- the coaches' wheels follow the loco's motion segment, scaled to each coach's slide
		local seg = run.seg
		local segKey = seg and (tostring(seg.t0) .. ":" .. tostring(seg.d0)) or nil
		local newSeg = segKey ~= R.segKey
		R.segKey = segKey
		for _, c in ipairs(R.coaches) do
			local x, y, z, yaw = pullFrame(c, f)
			pcall(function()
				api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(c.ghost,
					api.type.Mat4f.rotZTransl(yaw, api.type.Vec3f.new(x, y, z))))
			end)
			if newSeg and seg ~= nil then
				local k = c.slide / R.pullLen
				c.dist = c.dist0 + ((seg.d0 or 0.0) - R.gdist0) * k
				pushCoachState(c, (run.speed or 0.0) * k, { d0 = c.dist, v0 = (seg.v0 or 0.0) * k, acc = (seg.acc or 0.0) * k, vmax = (seg.vmax or 0.0) * k, t0 = seg.t0 })
			end
		end
		if f >= 1 then
			R.stage = "uncouple"
			R.t = 0
			for _, c in ipairs(R.coaches) do
				c.dist = c.dist0 + c.slide
				pushCoachState(c, 0.0, { d0 = c.dist, v0 = 0.0, acc = 0.0, vmax = 0.0, t0 = gameTimeMs() })
			end
			-- the loco should be where it would be coupled: moved as far as the coaches
			local lx, ly = (run.locoPos and run.locoPos.x or 0) + (R.coaches[1].target.x - R.coaches[1].start.x), (run.locoPos and run.locoPos.y or 0) + (R.coaches[1].target.y - R.coaches[1].start.y)
			logInfo(string.format("ghost rake: train drawn up %.1f m; loco ghost %.2f m from where it would be coupled",
				R.pullLen, math.sqrt(((run.gx or lx) - lx) ^ 2 + ((run.gy or ly) - ly) ^ 2)))
		end
		return false
	end
	if R.stage == "uncouple" then
		R.t = R.t + dt
		if R.t >= CONFIG.uncouplePause then
			R.stage = "done"
			logInfo("ghost rake: loco uncoupled")
		end
	end
	return false
end

local function rakeFlipStep(state, vehicleEntity)
	local function done(fn)
		local live = updateRun(state, vehicleEntity, function(r) if r.rake then r.rake.busy = false; fn(r) end end)
		if live then holdTrain(vehicleEntity) end -- not once the watchdog has released it
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
	if okB then okC, cmd = pcall(makeReplaceCmd, run.vehicleEntity, cfg) end
	if not okC then
		return recoupleFailed(state, run, "(ghost rake) " .. tostring(okB and cmd or cfg))
	end
	local moneyBefore = playerBalance()
	api.cmd.sendCommand(cmd, function(_, success)
		if not success then
			return recoupleFailed(state, run, "(ghost rake) replace refused")
		end
		logMoneyChange("the recouple", moneyBefore)
		scheduleTrace(state, "after the recouple (+3 ticks)", run.vehicleEntity, 3)
		if not run.ghostGone and run.ghost ~= nil then api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost)) end
		destroyCoachGhosts(run.rake.coaches)
		run.ghostGone = true
		if CONFIG.verifyFacing and run.gyaw ~= nil then
			run.phase = "verify"
			run.verifyWait = 0
			run.locoAtRear = false
			local data = state:get()
			data.runs[#data.runs + 1] = run
			state:set(data)
		else
			finalizeRun(state, run)
		end
	end)
end


-- Unit direction of travel along the route at piece k, s metres into it.
local function routeDirectionAt(loop, k, s)
	local edgeDef = loop.loopEdges[k]
	local geometry = getEdgeGeometry(edgeDef)
	local len = estimateEdgeLength(geometry)
	local t = len > 0 and math.min(math.max(s / len, 0.0), 1.0) or 0.0
	local u = edgeDef.forward and t or (1.0 - t)
	local calc = api.engine.util.transport.calcPosition
	local pa, pb = calc(geometry, math.max(0.0, u - 0.02)), calc(geometry, math.min(1.0, u + 0.02))
	local dx, dy = pb.x - pa.x, pb.y - pa.y
	if not edgeDef.forward then dx, dy = -dx, -dy end
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1e-9 then return nil end
	return dx / d, dy / d
end

-- Records why the last arrival at a loop did not run around (nil: it did), for
-- the run-around card.
local function setLoopProblem(state, loopId, text)
	local data = state:get()
	local loop = data and findLoopById(data.loops or {}, loopId)
	if loop ~= nil and loop.lastProblem ~= text then
		loop.lastProblem = text
		state:set(data)
	end
end

-- Whether this train can run around on this loop's route, from where it stands:
-- it must be on the route's first leg, at the platform the route was planned
-- from (a line stop can send trains to alternative platforms), and the route
-- must leave away from the coaches (a loco cannot drive through its own train).
-- Returns the piece and metres along it where the loco stands, or nil and why.
local function checkStartOnRoute(vehicleEntity, loop, locoIdx, locoTransf, partCount)
	if locoTransf == nil then return nil, nil, "the loco's position could not be read" end
	local c = locoTransf:cols(3)
	local okL, k, off, dist = pcall(locateOnRoute, loop, { x = c.x, y = c.y })
	if not okL or k == nil then return nil, nil, "the route could not be read: " .. tostring(k) end
	if dist > ON_ROUTE_M then
		-- another part of the train on the route: the loco is at the wrong end
		local okO, other = pcall(function()
			local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
			for i = 1, partCount do
				if i ~= locoIdx then
					local p = carriagePos(cl.carriages[i])
					local _, _, d = locateOnRoute(loop, { x = p.x, y = p.y })
					if d ~= nil and d <= ON_ROUTE_M then return true end
				end
			end
			return false
		end)
		if okO and other then
			return nil, nil, string.format("the loco is at the other end of the train from where the route starts (it is %d m from the route)", math.floor(dist + 0.5))
		end
		return nil, nil, string.format("the train is not at the platform the route starts from (the loco is %d m from the route)", math.floor(dist + 0.5))
	end
	-- away from the coaches: from the neighbouring carriage to the loco
	local nb = (locoIdx == 1) and 2 or ((locoIdx == partCount) and partCount - 1 or nil)
	if nb ~= nil then
		local okD, ok2 = pcall(function()
			local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
			local n = carriagePos(cl.carriages[nb])
			local ax, ay = c.x - n.x, c.y - n.y
			local dx, dy = routeDirectionAt(loop, k, off)
			if dx == nil then return true end
			return ax * dx + ay * dy >= 0
		end)
		if okD and not ok2 then
			return nil, nil, "the route sets off towards the coaches, not away from them: check the route's first points"
		end
	end
	return k, off, string.format("%.1f m from the route", dist)
end

local function startRunAround(state, vehicleEntity, loop)
	pieceLengths = {} -- (the track may have been rebuilt since the last run)
	local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		return
	end
	local tvc = tv.transportVehicleConfig
	if #tvc.vehicles < 2 then
		logInfo("vehicle", vehicleEntity, "is a light engine: nothing to run around")
		return
	end
	local function refuse(why)
		logInfo("run-around NOT started for vehicle", vehicleEntity, "loop", loopLabel(loop), "-", why, "- the train leaves the normal way")
		setLoopProblem(state, loop.id, why)
	end
	local n = #tvc.vehicles
	local locoIdx = nil
	if loop.locoManual then
		locoIdx = findLocoIndex(tvc, loop)
		if locoIdx == nil then return refuse("the chosen loco is not on this train") end
		if isPowered(tvc.vehicles[locoIdx].part.modelId) ~= true then return refuse("the chosen part has no engine") end
	else
		-- Automatic: a powered part at an end of the train (a loco can only run
		-- around from an end); with one at each end, the one nearer the first route
		-- point. Never a coach or wagon, whatever is nearest.
		local ends = {}
		for _, i in ipairs(n > 1 and { 1, n } or { 1 }) do
			local powered = isPowered(tvc.vehicles[i].part.modelId)
			if powered == nil then return refuse("could not tell which part of the train is the loco") end
			if powered then ends[#ends + 1] = i end
		end
		if #ends == 0 then return refuse("there is no loco at either end of the train") end
		locoIdx = ends[1]
		if #ends == 2 then
			local first = loop.waypoints and loop.waypoints[1]
			local okD, nearer = pcall(function()
				local pos = piecePos(first, 0.5)
				local cl = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
				local a, b = carriagePos(cl.carriages[1]), carriagePos(cl.carriages[n])
				return ((b.x - pos.x) ^ 2 + (b.y - pos.y) ^ 2 < (a.x - pos.x) ^ 2 + (a.y - pos.y) ^ 2) and n or 1
			end)
			if okD then locoIdx = nearer end
		end
		logInfo("loco chosen automatically: part", locoIdx, "of", n, "- model", tvc.vehicles[locoIdx].part.modelId,
			#ends == 2 and "(a loco at each end; the one nearer the first route point)" or "(the powered end of the train)")
	end
	if (loop.routeVersion or 1) < ROUTE_VERSION and loop.waypoints ~= nil and #loop.waypoints >= 2 then
		logInfo("route for loop", loopLabel(loop), "saved by an older version: planning it again")
		recomputeLoopRoute(loop)
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
	if not okT then locoTransf = nil end
	local startCursor, startOffset, where = checkStartOnRoute(vehicleEntity, loop, locoIdx, locoTransf, #tvc.vehicles)
	if startCursor == nil then return refuse(where) end
	logInfo(string.format("ghost starts on route piece %d, %d m along it (%s)", startCursor, math.floor(startOffset), where))
	-- The loco stays on the train, hidden, while its ghost runs around (so nothing
	-- is sold or bought): it must be hideable, i.e. its transformator wrapped or
	-- chained at load (ghost_build leaves a marker). If not, no run-around.
	if not canHide(locoSnap.modelId) then
		return refuse("this loco can't be hidden while its copy runs around (another mod's animation script could not be wrapped)")
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
		return refuse("no copy of this loco is available to run around")
	end
	local locoTopSpeed = tonumber(modelMeta(locoSnap.modelId, "landVehicle", "topSpeed"))
	if locoTopSpeed ~= nil and locoTopSpeed <= 1 then locoTopSpeed = nil end
	local startHead, startSign = nil, nil
	do
		local okH, hx, hy = pcall(headDirection, vehicleEntity)
		if okH and hx ~= nil then
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
	-- The ghost rake, when every coach can be shown (see CONFIG.ghostRake);
	-- otherwise the coaches stay visible and jump once at the flip.
	local rakeInfo = nil
	if CONFIG.ghostRake and CONFIG.reverseBeforeRecouple and locoIdx == 1 and #tvc.vehicles > 1 then
		local okF, frames = pcall(carriageFrames, vehicleEntity)
		if okF then
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
			if coaches ~= nil then rakeInfo = { coaches = coaches } end
		end
		if rakeInfo == nil then logInfo("ghost rake: not every coach can be hidden - the coaches stay in view and move at the flip") end
	end

	local okBuild, strippedConfig
	if rakeInfo ~= nil then
		okBuild, strippedConfig = pcall(buildHiddenRakeConfig, tvc)
	else
		okBuild, strippedConfig = pcall(buildConfigWithHiddenLoco, tvc, locoIdx)
	end
	if not okBuild then
		logInfo("startRunAround: could not build the train with the loco hidden:", tostring(strippedConfig))
		return
	end
	local okCmd, replaceCmd = pcall(makeReplaceCmd, vehicleEntity, strippedConfig)
	if not okCmd then
		logInfo("startRunAround: hiding the loco was rejected:", tostring(replaceCmd))
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
				destroyCoachGhosts(rakeInfo.coaches)
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

	-- The run's record. Also made (with no ghost, phase "finish", restore set) when
	-- the loco ghost cannot be shown after the detach: finishRun then puts the real
	-- train back exactly as it would at the end of a run, with the same retries, so
	-- a ghost rake's coaches get back their order, facing and paint (they are
	-- hidden, reversed and in reverse order at that point).
	local function newRun(ghost)
		return {
			vehicleEntity = vehicleEntity,
			loop = loop,
			locoPart = locoSnap,
			locoIdx = locoIdx,
			partCount = #tvc.vehicles,
			rake = rakeInfo and { stage = "flip", busy = false, coaches = rakeInfo.coaches } or nil,
			startHead = startHead,
			startSign = startSign,
			startReversed = locoSnap.reversed and true or false,
			effects = ghostEffects,
			color = locoSnap.color and { locoSnap.color.x, locoSnap.color.y, locoSnap.color.z } or nil,
			topSpeed = locoTopSpeed,
			origRev = origRev,
			ghost = ghost,
			ghostGone = ghost == nil,
			edgeCursor = 1,
			edgeLength = nil,
			edgeProgress = 0.0,
			speed = 0.0,
			age = 0.0,
		}
	end

	sendReplace = function()
		local moneyBefore = playerBalance()
		api.cmd.sendCommand(replaceCmd, function(_, success)
		if not success then
			logInfo("detach replaceVehicle FAILED for vehicle", vehicleEntity, "loop", loopLabel(loop), "- train released")
			destroyCoachGhosts(rakeInfo and rakeInfo.coaches)
			releaseTrain(vehicleEntity)
			return
		end
		logMoneyChange("the detach", moneyBefore)

		scheduleTrace(state, "after the detach (+2 ticks)", vehicleEntity, 2)
		scheduleTrace(state, "after the detach (+30 ticks)", vehicleEntity, 30)
		api.cmd.sendCommand(api.cmd.makeCustomEntityCreateCmd(ghostModelId), function(createRes, createSuccess)
			if not createSuccess then
				logInfo("failed to spawn ghost loco entity for loop", loopLabel(loop), "- putting the train back as it was")
				local run = newRun(nil)
				run.phase = "finish"
				run.restore = true
				run.aborted = true
				local data = state:get()
				data.runs[#data.runs + 1] = run
				state:set(data)
				return
			end
			local ghost = createRes.resultEntity
			api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(ghost, locoTransf))

			local c0 = locoTransf:cols(0)
			local locoYaw = math.atan2(c0.y, c0.x)
			local run = newRun(ghost)
			run.edgeCursor = startCursor
			run.startOffset = startOffset
			run.locoYaw = locoYaw
			run.locoPos = { x = locoTransf:cols(3).x, y = locoTransf:cols(3).y }
			run.driveTotal = routeDriveLength(loop, startCursor, startOffset)
			local data = state:get()
			data.runs[#data.runs + 1] = run
			state:set(data)
			if ghostEffects then
				local run = data.runs[#data.runs]
				startSegment(run, 0.0, 0.0, 0.0)
				pushGhostState(run, 0.0, 0.0, 0.0, 0.0)
				state:set(data)
			end
			setLoopProblem(state, loop.id, nil)
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

-- Reads a vehicle's consist and current line/stop, for the GUI's "add a
-- run-around" and loco choice. Returns nil if the entity isn't a live
-- transport vehicle right now.
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

-- Handles one "RunAroundGuiCmd" event from runaround_gui.lua. All mutation
-- of persistent loop config happens here (not in the GUI file) so there is
-- a single source of truth and the GUI can stay a thin layer.
local function handleGuiCmd(data, name, param)
	if name == "AddLoopAtStop" then
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
		local range = ({ speed = { 10 / 3.6, 100 / 3.6 }, accel = { 0.5, 4.0 } })[param.field]
		if loop ~= nil and range ~= nil and type(param.value) == "number" then
			loop[param.field] = math.min(math.max(param.value, range[1]), range[2])
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
				watchdog(run, dt)
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

			-- The arrival the game reports again straight after a run-around (see
			-- finalizeRun) is ignored; arriving anywhere else clears the record.
			local key = tostring(param.vehicleEntity)
			local ran = data.ranAt and data.ranAt[key]
			if ran ~= nil then
				if ran.line == param.lineEntity and ran.stop == param.stopIndex then
					logInfo("vehicle", param.vehicleEntity, "reported at the stop it has just run around at - ignored")
					return
				end
				data.ranAt[key] = nil
				state:set(data)
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
