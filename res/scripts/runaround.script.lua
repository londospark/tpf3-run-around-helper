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

	-- Kill switch for the whole detach. A wagons-only consist crashes the game
	-- (see standin.mdl), so the loco is never simply removed: it is swapped for
	-- the invisible stand-in model in res/models/runaround_standin/ while the
	-- ghost loco is away, and the run is refused if that model isn't found.
	detachEnabled = true,

	-- Logs the structure of the chosen loco's model table when a loop is
	-- created (read-only). Not needed now the stand-in model is authored.
	DUMP_LOCO_MODEL = false,

	-- Defaults applied to a newly-added loop; edit per-loop from the GUI afterwards.
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

-- The invisible stand-in loco (res/models/runaround_standin/standin.mdl).
-- Found by name because a mod's resource path prefix isn't known in advance.
local standInId = nil
local function findStandInModelId()
	if standInId ~= nil then return standInId end
	local ok, all = pcall(api.res.modelRep.getAll, true)
	if ok and all ~= nil then
		for id, name in pairs(all) do
			if type(name) == "string" and string.find(name, "runaround_standin/standin.mdl", 1, true) then
				standInId = id
				logInfo("stand-in model found:", name, "id", id)
				return id
			end
		end
	end
	return nil
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
local function buildConfigWithStandIn(tvc, locoIdx, standId, locoSnap)
	local config = api.type.TransportVehicleConfig.new(tvc)
	local parts = {}
	for i, part in ipairs(config.vehicles) do
		if i == locoIdx then
			parts[#parts + 1] = makeStandInPart(standId, locoSnap)
		else
			parts[#parts + 1] = part
		end
	end
	return finishConfig(config, parts)
end

-- Config with the stand-in taken out and the real locomotive put back on the
-- train. A loco cannot pass through its consist, so it can only couple onto the
-- end it arrives at; which end that is comes from where the run finished (see
-- chooseAttachEnd), not from a setting. It then faces OUTWARD, away from the
-- wagons, so that it can pull them: a loco at the front of the parts list is
-- not reversed, one at the rear is.
local function buildConfigWithLocoReattached(currentTvc, locoSnap, attachAtRear, standId)
	local config = api.type.TransportVehicleConfig.new(currentTvc)
	local loco = partFromSnapshot(locoSnap, attachAtRear)
	local parts = {}
	if not attachAtRear then parts[1] = loco end
	for _, part in ipairs(config.vehicles) do
		if part.part.modelId ~= standId then -- the stand-in goes away here
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

-- Lets a train that was held for a run-around go again. Used on every failure
-- path so a problem here never leaves a train stuck at the station.
local function releaseTrain(vehicleEntity)
	api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(vehicleEntity, false))
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

local function finishRun(run)
	local tv = api.engine.getComponent(run.vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then
		logInfo("finishRun: vehicle", run.vehicleEntity, "no longer exists, aborting recouple")
		api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost))
		return
	end

	local okEnd, atRear, why = pcall(chooseAttachEnd, run.vehicleEntity, run.loop, tv.transportVehicleConfig, run.standInModelId)
	if not okEnd then
		logInfo("could not work out which end to attach at (", tostring(atRear), ") - defaulting to the rear")
		atRear, why = true, "fallback"
	end
	logInfo("recouple: removing the stand-in and attaching the loco at the", atRear and "REAR" or "FRONT", "of the consist, facing outward -", why)

	local okBuild, newConfig = pcall(buildConfigWithLocoReattached, tv.transportVehicleConfig, run.locoPart, atRear, run.standInModelId)
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
		api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(run.ghost))
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
	local standId = findStandInModelId()
	if standId == nil then
		logInfo("startRunAround: the stand-in model was not found, so the loco will NOT be detached (a wagons-only train crashes the game). Is res/models/runaround_standin/standin.mdl loaded?")
		return
	end
	local okBuild, strippedConfig = pcall(buildConfigWithStandIn, tvc, locoIdx, standId, locoSnap)
	if not okBuild then
		logInfo("startRunAround: could not build the consist with the stand-in:", tostring(strippedConfig))
		return
	end
	local okCmd, replaceCmd = pcall(api.cmd.makeVehicleReplaceCmd, vehicleEntity, strippedConfig)
	if not okCmd then
		logInfo("startRunAround: stand-in swap command rejected:", tostring(replaceCmd))
		return
	end

	api.cmd.sendCommand(api.cmd.makeVehicleSetManualDepartureCmd(vehicleEntity, true))

	api.cmd.sendCommand(replaceCmd, function(_, success)
		if not success then
			logInfo("detach replaceVehicle FAILED for vehicle", vehicleEntity, "loop", loopLabel(loop), "- train released")
			releaseTrain(vehicleEntity)
			return
		end

		api.cmd.sendCommand(api.cmd.makeCustomEntityCreateCmd(locoSnap.modelId), function(createRes, createSuccess)
			if not createSuccess then
				logInfo("failed to spawn ghost loco entity for loop", loopLabel(loop), "- the loco is now missing from the train")
				return
			end
			local ghost = createRes.resultEntity
			if locoTransf ~= nil then
				api.cmd.sendCommand(api.cmd.makeCustomEntityUpdateTransformationCmd(ghost, locoTransf))
			end

			local data = state:get()
			data.runs[#data.runs + 1] = {
				vehicleEntity = vehicleEntity,
				loop = loop,
				locoPart = locoSnap,
				standInModelId = standId,
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
-- Read-only probe: prints the shape of a model table (keys, value types,
-- lengths) to the log, depth- and size-limited.
local function dumpModelShape(modelId)
	local ok, t = pcall(api.res.modelRep.getAsTable, modelId)
	if not ok or type(t) ~= "table" then
		logInfo("model probe: getAsTable failed for", modelId, tostring(t))
		return
	end
	local budget = 220
	local function dump(v, indent, depth)
		if budget <= 0 then return end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			if budget <= 0 then return end
			local val = v[k]
			local tv = type(val)
			local desc
			if tv == "table" then
				local n = 0
				for _ in pairs(val) do n = n + 1 end
				desc = "table(" .. n .. ")"
			elseif tv == "string" then
				desc = '"' .. string.sub(val, 1, 60) .. '"'
			else
				desc = tostring(val)
			end
			budget = budget - 1
			logInfo("model probe: " .. string.rep("  ", indent) .. tostring(k) .. " = " .. desc)
			if tv == "table" and depth < 4 then dump(val, indent + 1, depth + 1) end
		end
	end
	logInfo("model probe: model", modelId, "structure follows")
	dump(t, 0, 0)
end

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
		if CONFIG.DUMP_LOCO_MODEL and loop.locoModelId ~= nil then
			pcall(dumpModelShape, loop.locoModelId)
		end

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
				end
			end
			data.runs = remaining
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

		if updateResult.finishes ~= nil then
			for _, run in ipairs(updateResult.finishes) do
				finishRun(run)
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
