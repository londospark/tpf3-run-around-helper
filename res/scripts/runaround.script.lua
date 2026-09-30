--[[
	Run Around Helper - scaffold for TpF3

	GOAL
	At each configured terminus, when a tagged train arrives, its locomotive
	is pulled out, physically driven (as a non-simulated "ghost" model)
	around a loop/wye, and reinserted at the other end - instead of the
	train doing the instant vanilla flip. The return trip back through the
	OTHER terminus of each line is left to vanilla behaviour (auto-flip),
	which is fine for this project's goal. Supports any number of
	independently-configured loops (different lines/termini) at once.

	VERIFIED AGAINST THE SHIPPED GAME FILES (api/tealdef/*, base/content/*):
	  - api.cmd.makeVehicleReplaceCmd(vehicleEntity, config) swaps a live
	    train's consist in place (not depot-only - confirmed via
	    VehicleReplaceCommandData / the factory signature in cmd.d.tl).
	  - api.cmd.makeCustomEntityCreateCmd / UpdateTransformationCmd / DestroyCmd
	    spawn, move and remove a free-floating model entity outside the
	    line/depot system (used by the base game for blimps/UFOs/rockets -
	    see game_mechanics/fun_elements/custom_entity_util.tl).
	  - "OnArriveAtStop" from src "TransportVehicleSystem" fires with
	    {vehicleEntity, lineEntity, stopIndex, lastStopIndex} - confirmed
	    from game_mechanics/achievements/achievements.script.tl.
	  - Component field names (TRANSPORT_VEHICLE.transportVehicleConfig,
	    CARRIAGE_LIST.carriages, MODEL_INSTANCE_LIST.fatInstances[1].transf,
	    TransportVehicleConfig.vehicles[i].part.{modelId,reversed}) are taken
	    directly from api/tealdef/api/type.d.tl and api/tealdef/api/engine.d.tl.

	NOT VERIFIED / YOU WILL NEED TO TUNE THESE IN-GAME, PER LOOP:
	  - Whether CARRIAGE_LIST.carriages is index-aligned with
	    TransportVehicleConfig.vehicles (assumed here; if the captured loco
	    transform looks wrong, this is the first thing to check).
	  - Which physical end of the vehicles array should hold the loco after
	    recoupling, and whether its `reversed` flag needs to flip. Both are
	    exposed as per-loop booleans - flip them if the loco comes back
	    facing/positioned wrong.
	  - Edge length isn't a field on Edge/EdgeGeometry in the declarations,
	    so it's estimated by sampling calcPosition() - fine for animation
	    purposes but not exact.
	  - Multiple-unit (MU) consists are NOT handled - this assumes a simple
	    loco + separate wagons consist. vehicleGroups is rebuilt as all-1s.

	SETUP STEPS (per loop - repeat for each terminus you want this at)
	  1. Load this mod, load into a save, and stop a train (with the loco
	     you want to detach) at your chosen terminus.
	  2. Open that vehicle's info window in-game and use the "Run Around
	     Helper" panel added to it (see res/scripts/runaround_gui.lua) to
	     click "Add loop from this vehicle" - this captures the line, stop
	     and a starting loco candidate automatically, no ids to hunt for.
	  3. Drive that same locomotive around your loop/wye track segment by
	     segment, clicking "Capture edge here" once per edge, to record the
	     ordered path. There's no automatic loop-finding - you drive the
	     exact route because pathfinding around a specifically-shaped
	     run-around loop while avoiding the main line is exactly the kind
	     of thing that needs a human's track layout knowledge, not a
	     generic solver.
	  4. Test, then use the panel's toggle buttons to flip that loop's
	     "loco end" and/or "flip on recouple" if the loco ends up on the
	     wrong end or facing the wrong way after recoupling.

	If the GUI doesn't show up for some reason (see runaround_gui.lua's
	header for why that's the least-certain part of this mod), the log (see
	LOG_ARRIVALS below) still prints every vehicle/line/stop id it sees as a
	fallback for hand-driving the same setup via "RunAroundGuiCmd" scripting
	events sent from the dev console.

	GUI: loops are configured in-game (see res/scripts/runaround_gui.lua)
	rather than hand-edited here. The GUI adds/edits/removes entries in
	persistent state (state:get().loops) by sending "RunAroundGuiCmd"
	scripting events, handled below. This file has no more static loop
	config - CONFIG below only holds defaults for newly-added loops and the
	discovery-logging toggle. See runaround_gui.lua's own header comment
	for what's solidly grounded vs. best-effort in the GUI layer itself -
	that part of the API is far less charted than this scripting core.
]]

local CONFIG = {
	-- Set to true to log every vehicle arrival (vehicle/line/stop ids) -
	-- useful for debugging even with the GUI, and as a fallback if the GUI
	-- turns out not to load (see runaround_gui.lua's header for why that's
	-- the single least-certain part of this mod).
	LOG_ARRIVALS = true,

	-- Defaults applied to a newly-added loop; edit per-loop from the GUI afterwards.
	defaultSpeed = 8.0,
	defaultAccel = 2.0,
	defaultLocoLeadsWithFirstArrayEntry = false,
	defaultFlipLocoReversedOnRecouple = true,
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

-- Shallow-copies a TransportVehiclePart (keeps purchaseTime/maintenanceState
-- so the loco doesn't lose its age/depreciation across replaceVehicle calls,
-- matching the approach used by the community "Train Autosizer" mod).
local function copyVehiclePart(tvp)
	return {
		part = {
			modelId = tvp.part.modelId,
			reversed = tvp.part.reversed,
			compartment2loadConfig = tvp.part.compartment2loadConfig,
			color = tvp.part.color,
		},
		purchaseTime = tvp.purchaseTime,
		maintenanceChange = tvp.maintenanceChange,
		maintenanceState = tvp.maintenanceState,
		autoLoadConfig = tvp.autoLoadConfig,
	}
end

local function buildConfigFromVehicles(vehicles)
	local groups = {}
	for i = 1, #vehicles do
		groups[i] = 1
	end
	return {
		vehicles = vehicles,
		vehicleGroups = groups,
		muFileNames = {},
	}
end

-- Config with the locomotive removed, wagons kept in their original order.
local function buildConfigWithoutLoco(tvc, locoIdx)
	local vehicles = {}
	for i, tvp in ipairs(tvc.vehicles) do
		if i ~= locoIdx then
			vehicles[#vehicles + 1] = copyVehiclePart(tvp)
		end
	end
	return buildConfigFromVehicles(vehicles)
end

-- Config with the locomotive reinserted at whichever end this loop's config
-- says should lead after the run-around.
local function buildConfigWithLocoReattached(wagonsOnlyTvc, locoTvp, loop)
	local loco = copyVehiclePart(locoTvp)
	if loop.flipLocoReversedOnRecouple then
		loco.part.reversed = not loco.part.reversed
	end

	local vehicles = {}
	if loop.locoLeadsWithFirstArrayEntry then
		vehicles[1] = loco
		for i, tvp in ipairs(wagonsOnlyTvc.vehicles) do
			vehicles[i + 1] = tvp
		end
	else
		for i, tvp in ipairs(wagonsOnlyTvc.vehicles) do
			vehicles[i] = tvp
		end
		vehicles[#vehicles + 1] = loco
	end
	return buildConfigFromVehicles(vehicles)
end

-- Reads the loco's current world transform off the live carriage entity,
-- before it gets replaced away. ASSUMES carriages[] is index-aligned with
-- transportVehicleConfig.vehicles - verify this the first time you run it.
local function captureLocoTransform(vehicleEntity, locoIdx)
	local carriageList = api.engine.getComponent(vehicleEntity, api.type.ComponentType.CARRIAGE_LIST)
	local carriageEntity = carriageList.carriages[locoIdx]
	local mil = api.engine.getComponent(carriageEntity, api.type.ComponentType.MODEL_INSTANCE_LIST)
	return mil.fatInstances[1].transf
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

-- Edges to drive from waypoint a (leaving in direction dA) to waypoint b
-- (entering in direction dB), both endpoints included. nil + message if no route.
local function legPath(a, dA, b, dB)
	local ea, eb = getTnEdge(a.entity, a.index), getTnEdge(b.entity, b.index)
	if ea == nil or eb == nil then return nil, "a clicked track piece no longer exists" end
	local startNode = dA and ea.conns[2] or ea.conns[1]
	local destNode = dB and eb.conns[1] or eb.conns[2]

	local path = {}
	if not (startNode.entity == destNode.entity and startNode.index == destNode.index) then
		local ok, res = pcall(api.engine.util.pathfinding.findPathNodeToNode, { startNode }, { destNode }, { api.type.enum.TransportMode.TRAIN })
		if not ok then return nil, "pathfinder error: " .. tostring(res) end
		path = res
		if #path == 0 then return nil, "no track route" end
	end

	local raw = { { entity = a.entity, index = a.index, forward = dA } }
	for i = 1, #path do
		local eid, dir = unpackPathPair(path[i])
		if eid == nil then return nil, "unreadable pathfinder entry " .. i end
		raw[#raw + 1] = { entity = eid.entity, index = eid.index, forward = dir }
	end
	raw[#raw + 1] = { entity = b.entity, index = b.index, forward = dB }

	local out = {}
	for _, e in ipairs(raw) do
		local last = out[#out]
		if not (sameEdge(last, e) and last.forward == e.forward) then
			out[#out + 1] = e
		end
	end
	return out
end

-- Best route through all waypoints, or nil + message.
-- Returns route (list of {entity,index,forward[,reversal]}), info {length, reversals}.
local function planRoute(waypoints)
	local n = #waypoints
	if n < 2 then return nil, "need at least 2 points" end

	local memo = {}
	local function leg(i, d, a)
		local key = i .. ":" .. tostring(d) .. ":" .. tostring(a)
		local m = memo[key]
		if m == nil then
			local edges, err = legPath(waypoints[i], d, waypoints[i + 1], a)
			local cost = math.huge
			if edges ~= nil then
				cost = 0
				for _, e in ipairs(edges) do
					cost = cost + estimateEdgeLength(getEdgeGeometry(e))
				end
			end
			m = { edges = edges, cost = cost, err = err }
			memo[key] = m
		end
		return m
	end

	local best, from = { {} }, {}
	for s, st in ipairs(STATES) do
		best[1][s] = (st[1] == st[2]) and 0 or math.huge -- no arrival at the first point
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
		for i = 1, n - 1 do
			local any = false
			local lastErr = "no track route"
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

	local route, reversals, length = {}, 0, 0
	for i = 1, n - 1 do
		local l = leg(i, STATES[chosen[i]][2], STATES[chosen[i + 1]][1])
		for _, e in ipairs(l.edges) do
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
	return route, { length = endCost, reversals = reversals }
end

-- Rebuilds loop.loopEdges from loop.waypoints and records a one-line status
-- for the panel. Never throws.
local function recomputeLoopRoute(loop)
	loop.waypoints = loop.waypoints or {}
	if #loop.waypoints < 2 then
		loop.loopEdges = {}
		loop.pathStatus = (#loop.waypoints == 0) and "no points yet" or "1 point - click at least one more"
		return
	end
	local ok, route, info = pcall(planRoute, loop.waypoints)
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
	loop.pathStatus = string.format("%d points, %d track pieces, %d reversal(s), about %d m", #loop.waypoints, #route, info.reversals, math.floor(info.length))
	logInfo("route for loop", loopLabel(loop), "-", loop.pathStatus)
end

-- Advances one run's ghost loco by dt seconds. Returns true once it has
-- reached the end of its loop's loopEdges.
local function advanceGhost(run, dt)
	local loop = run.loop
	if run.edgeCursor > #loop.loopEdges then
		return true
	end

	-- Waiting at a reversal point (loco changing ends).
	if run.pause ~= nil and run.pause > 0 then
		run.pause = run.pause - dt
		run.speed = 0.0
		return false
	end

	local edgeDef = loop.loopEdges[run.edgeCursor]
	if run.edgeLength == nil then
		if edgeDef.reversal and not run.reversalDone then
			run.reversalDone = true
			run.headingFlipped = not run.headingFlipped
			run.pause = REVERSAL_PAUSE
			return false
		end
		run.edgeLength = estimateEdgeLength(getEdgeGeometry(edgeDef))
		run.edgeProgress = 0.0
	end

	run.speed = math.min(loop.speed, run.speed + loop.accel * dt)
	run.edgeProgress = run.edgeProgress + run.speed * dt
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
	local yaw = math.atan2(dy, dx)
	if run.headingFlipped then
		yaw = yaw + math.pi -- driving backwards: the loco keeps facing the way it faced
	end
	local transf = api.type.Mat4f.rotZTransl(yaw, pos)

	api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(run.ghost, transf))

	if run.edgeProgress >= run.edgeLength then
		run.edgeCursor = run.edgeCursor + 1
		run.edgeLength = nil
		run.reversalDone = false
	end

	return run.edgeCursor > #loop.loopEdges
end

local function finishRun(run)
	api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost))

	local tv = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		logInfo("finishRun: vehicle", run.vehicleEntity, "no longer exists, aborting recouple")
		return
	end

	local newConfig = buildConfigWithLocoReattached(tv.transportVehicleConfig, run.locoPart, run.loop)
	api.cmd.sendCommand(api.cmd.makeVehicleReplaceCmd(run.vehicleEntity, newConfig), function(_, success)
		if not success then
			logInfo("recouple replaceVehicle FAILED for vehicle", run.vehicleEntity, "loop", loopLabel(run.loop))
			return
		end
		api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(run.vehicleEntity, false))
		api.cmd.sendCommand(api.cmd.makeVehicleTryToDepartCmd(run.vehicleEntity))
		logInfo("run-around complete for vehicle", run.vehicleEntity, "loop", loopLabel(run.loop))
	end)
end

local function startRunAround(state, vehicleEntity, loop)
	local tv = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		return
	end
	local tvc = tv.transportVehicleConfig
	local locoIdx = findLocoIndex(tvc, loop)
	if locoIdx == nil then
		logInfo("startRunAround: no vehicle part with modelId", loop.locoModelId, "found on", vehicleEntity, "loop", loopLabel(loop))
		return
	end
	if #loop.loopEdges == 0 then
		logInfo("startRunAround: loopEdges is empty for loop", loopLabel(loop), "- nothing to animate")
		return
	end

	api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(vehicleEntity, true))

	local locoTvp = tvc.vehicles[locoIdx]
	local locoTransf = captureLocoTransform(vehicleEntity, locoIdx)
	local strippedConfig = buildConfigWithoutLoco(tvc, locoIdx)

	api.cmd.sendCommand(api.cmd.makeVehicleReplaceCmd(vehicleEntity, strippedConfig), function(_, success)
		if not success then
			logInfo("detach replaceVehicle FAILED for vehicle", vehicleEntity, "loop", loopLabel(loop))
			return
		end

		api.cmd.sendCommand(api.cmd.makeCustomEntityCreateCmd(locoTvp.part.modelId), function(createRes, createSuccess)
			if not createSuccess then
				logInfo("failed to spawn ghost loco entity for loop", loopLabel(loop))
				return
			end
			local ghost = createRes.resultEntity
			api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(ghost, locoTransf))

			local data = state:get()
			data.runs[#data.runs + 1] = {
				vehicleEntity = vehicleEntity,
				loop = loop,
				locoPart = locoTvp,
				ghost = ghost,
				edgeCursor = 1,
				edgeLength = nil,
				edgeProgress = 0.0,
				speed = 0.0,
			}
			state:set(data)
			logInfo("run-around started for vehicle", vehicleEntity, "loop", loopLabel(loop))
		end)
	end)
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
-- a single source of truth and the GUI can stay a thin, best-effort layer.
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
			locoCandidateIndex = 1,
			waypoints = {},
			loopEdges = {},
			pathStatus = "no points yet",
			speed = CONFIG.defaultSpeed,
			accel = CONFIG.defaultAccel,
			locoLeadsWithFirstArrayEntry = CONFIG.defaultLocoLeadsWithFirstArrayEntry,
			flipLocoReversedOnRecouple = CONFIG.defaultFlipLocoReversedOnRecouple,
		}
		data.loops[#data.loops + 1] = loop
		logInfo("GUI: added loop", loopLabel(loop), "from vehicle", param.vehicleEntity)

	elseif name == "CycleLocoCandidate" then
		local loop = findLoopById(data.loops, param.loopId)
		local snap = loop and readVehicleSnapshot(param.vehicleEntity)
		if loop ~= nil and snap ~= nil and #snap.vehicles > 0 then
			loop.locoCandidateIndex = (loop.locoCandidateIndex or 0) % #snap.vehicles + 1
			loop.locoModelId = snap.vehicles[loop.locoCandidateIndex].part.modelId
			logInfo("GUI: loop", loopLabel(loop), "locoModelId now", loop.locoModelId, "(candidate", loop.locoCandidateIndex .. ")")
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

	elseif name == "ToggleLoopBoolField" then
		-- param.field is one of "locoLeadsWithFirstArrayEntry" / "flipLocoReversedOnRecouple".
		local loop = findLoopById(data.loops, param.loopId)
		if loop ~= nil and (param.field == "locoLeadsWithFirstArrayEntry" or param.field == "flipLocoReversedOnRecouple") then
			loop[param.field] = not loop[param.field]
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

		-- Start any run-arounds queued by handleEvent. Commands must be sent
		-- from here, not from handleEvent: OnArriveAtStop is dispatched while
		-- the engine is mid-modification, and a sendCommand from inside that
		-- dispatch asserts "!m_betweenChanges" (Engine.cpp:545) and takes the
		-- whole game down - hit live on the first real run-around.
		if #data.pending > 0 then
			local queued = data.pending
			data.pending = {}
			state:set(data)
			for _, p in ipairs(queued) do
				local loop = findLoopById(data.loops, p.loopId)
				if loop ~= nil then
					startRunAround(state, p.vehicleEntity, loop)
				end
			end
			-- startRunAround's callbacks add to the run list through state,
			-- so re-read rather than trust the table held above.
			data = ensureData(state)
		end

		if #data.runs == 0 then
			return
		end

		local remaining = {}
		for _, run in ipairs(data.runs) do
			local done = advanceGhost(run, dt)
			if done then
				finishRun(run)
			else
				remaining[#remaining + 1] = run
			end
		end
		data.runs = remaining
		state:set(data)
	end,

	handleEvent = function(_userParams, state, _src, id, name, param)
		if id == "TransportVehicleSystem" and name == "OnArriveAtStop" then
			local data = ensureData(state)
			if CONFIG.LOG_ARRIVALS then
				logInfo("arrival: vehicle=", param.vehicleEntity, "line=", param.lineEntity, "stop=", param.stopIndex)
			end

			local loop = findLoopForArrival(data.loops, param.lineEntity, param.stopIndex)
			if loop ~= nil then
				if loop.locoModelId == nil then
					logInfo("startRunAround: loop", loopLabel(loop), "has no locoModelId set yet (configure it from the GUI)")
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
