--[[
	Run Around Helper - GUI

	  * A "Run-around" card in the train window (VehicleEowExtensionPoint): set up
	    a run-around at the stop the train is at, see the route and a live run,
	    edit the route on the map, and tune it.
	  * A "Run-Around" button in the mod-button area listing every loop.
	  * The route tool: while it is active the loop's route is drawn on the
	    track (builtin.NodeViewer: a colour gradient from start to finish, the
	    reversing pieces highlighted), markers flow along it in the direction of
	    travel and sit on the clicked points (api.gui.spawnEphemeralHudImage), and
	    in edit mode clicking track adds a point (builtin.Selector).

	Loading: each plugin needs a ".res.lua" descriptor (runaround_*.res.lua) whose
	filePath points here ("<modId>::/res/scripts/runaround_gui.script@<Export>").

	Talking to the game script: commands go through makeScriptingSendEventCmd with
	the fixed channel "RunAroundGuiCmd" as the NAME (subscriptions match on name)
	and the command as the id. State is read back from the game script entity's
	GAME_SCRIPT component (state.loops, state.runs).

	Lessons kept: builtin.Selector and builtin.NodeViewer only work inside an
	ActionDescriptor returned from a registered tool's action function (a Selector
	in a panel crashes the game); a tool pushed stacked shelves the train window,
	so it is shown again explicitly.
]]

function data()
	local react = ug_require "::/gui/main/react.lua"
	local builtin = ug_require "::/gui/main/builtin.lua"
	local gui_react_util = ug_require "::/gui/main/gui_react_util.tl"
	local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"
	local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl"
	local okCard, content_card = pcall(function() return ug_require "::/gui/main/content_card.tl" end)
	if not okCard then content_card = nil end
	local okEow, vehicle_eow = pcall(function() return ug_require "::/gui/entity_window/vehicle/vehicle_eow.script.tl" end)
	if not okEow then
		print("[RunAroundHelper] no vehicle window extension point:", vehicle_eow)
		vehicle_eow = nil
	end

	local V = builtin.type.Orientation.Vertical
	local H = builtin.type.Orientation.Horizontal

	local ICON = {
		route = "::/gui/debug_panel/icons/path.tga",
		reverse = "::/gui/entity_window/icons/symbol_arrow_reverse.tga",
		edit = "::/gui/builtin/window/icons/symbol_pencil.tga",
		trash = "::/gui/entity_window/icons/symbol_trash_bin.tga",
		undo = "::/gui/entity_window/icons/arrow_head_left.tga",
		eye = "::/gui/game_bar/icons/symbol_eye.tga",
		train = "::/gui/game_bar/icons/vehicle_train_30.tga",
		waypoint = "::/gui/hud/icons/signal_waypoint.tga",
		dot = "::/gui/hud/rendering/point.tga",
		ok = "::/gui/entity_window/icons/circle_check.tga",
		warn = "::/gui/hud/icons/line_vehicle_warning.tga",
		add = "::/gui/camera_tool/icons/plus19.tga",
	}

	-- ------------------------------------------------------------------
	-- Game script state and commands
	-- ------------------------------------------------------------------
	local GAME_SCRIPT_NAMES = { "runaround_helper_1::/res/scripts/runaround.gs", "runaround_helper_1::/res/scripts/runaround", "runaround" }
	local scriptName = nil
	local function scriptEntity()
		if scriptName ~= nil then
			return api.engine.system.gameScriptSystem.getEntityForGameScript(scriptName)
		end
		for _, name in ipairs(GAME_SCRIPT_NAMES) do
			local ok, e = pcall(api.engine.system.gameScriptSystem.getEntityForGameScript, name)
			if ok and e ~= nil and e >= 0 then
				scriptName = name
				return e
			end
		end
		return nil
	end

	local function readState()
		local ok, st = pcall(function()
			local e = scriptEntity()
			local comp = e and api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
			return comp and comp.state
		end)
		if not ok or st == nil then return { loops = {}, runs = {} } end
		return { loops = st.loops or {}, runs = st.runs or {} }
	end

	local function findLoop(state, loopId)
		for _, loop in ipairs(state.loops) do
			if loop.id == loopId then return loop end
		end
		return nil
	end

	local function sendGuiCmd(commandName, param)
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", commandName, "RunAroundGuiCmd", param))
	end

	local function entityName(entity)
		local ok, name = pcall(api.engine.util.getEntityName, entity)
		return ok and name ~= nil and name ~= "" and name or nil
	end

	-- "Line name, at Station name" for a loop.
	local function loopPlace(loop)
		local line = entityName(loop.lineEntity) or ("line " .. tostring(loop.lineEntity))
		local okStop, station = pcall(function()
			local l = api.engine.getComponent(loop.lineEntity, api.type.ComponentType.LINE)
			local stop = l.stops[loop.stopIndex + 1]
			return entityName(stop.stationGroup)
		end)
		return line .. (okStop and station and (", at " .. station) or "")
	end

	local function vehicleLineAndStop(vehicleEntity)
		local ok, tv = pcall(api.engine.getComponent, vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
		if not ok or tv == nil then return nil, nil end
		return tv.line, tv.stopIndex
	end

	local function kmh(ms) return math.floor((ms or 0) * 3.6 + 0.5) end

	-- ------------------------------------------------------------------
	-- Small building blocks
	-- ------------------------------------------------------------------
	local function Text(text, class)
		return builtin.TextView{ meta = class and { class = class } or nil, text = text }
	end

	local function Icon(path)
		return builtin.ImageView{ path = path }
	end

	local function Row(children)
		return builtin.BoxLayout{ orientation = H, children = children }
	end

	local function Column(children, class)
		return builtin.BoxLayout{ meta = class and { class = class } or nil, orientation = V, children = children }
	end

	local function IconButton(icon, text, tooltip, onClick, class)
		return builtin.Button{
			meta = { tooltip = tooltip, class = class },
			content = Row({ icon and Icon(icon) or nil, text and Text(text, "font-scale-body") or nil }),
			onClick = onClick,
		}
	end

	-- ------------------------------------------------------------------
	-- Route drawing (used inside the route tool's action)
	-- ------------------------------------------------------------------
	local COLOUR_START = { 0.25, 0.78, 1.0, 0.95 }
	local COLOUR_END = { 1.0, 0.62, 0.18, 0.95 }
	local COLOUR_REVERSE = { 0.93, 0.32, 1.0, 1.0 }

	local function mix(a, b, t)
		return api.type.Vec4f.new(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t)
	end
	local function vec4(c) return api.type.Vec4f.new(c[1], c[2], c[3], c[4]) end

	local function edgeGeometry(e)
		local tn = api.engine.getComponent(e.entity, api.type.ComponentType.TRANSPORT_NETWORK)
		return tn.edges[e.index + 1].geometry
	end

	-- Points every `spacing` metres along the route, in travel order, plus the
	-- positions of the reversals. Cached per route.
	local sampleCache = {}
	local function routeSamples(loop, spacing)
		local edges = loop.loopEdges or {}
		local key = tostring(loop.id) .. ":" .. #edges .. ":" .. tostring(loop.routeLength)
		if sampleCache[key] ~= nil then return sampleCache[key] end
		local calc = api.engine.util.transport.calcPosition
		local points, reversals = {}, {}
		local carry = 0.0
		for i, e in ipairs(edges) do
			local ok = pcall(function()
				local g = edgeGeometry(e)
				local n = 16
				local prev = calc(g, e.forward and 0.0 or 1.0)
				if e.reversal then reversals[#reversals + 1] = prev end
				for k = 1, n do
					local t = k / n
					local p = calc(g, e.forward and t or (1.0 - t))
					local d = math.sqrt((p.x - prev.x) ^ 2 + (p.y - prev.y) ^ 2)
					carry = carry + d
					while carry >= spacing do
						carry = carry - spacing
						local f = d > 0 and (1.0 - carry / d) or 1.0
						points[#points + 1] = api.type.Vec3f.new(prev.x + (p.x - prev.x) * f, prev.y + (p.y - prev.y) * f, prev.z + (p.z - prev.z) * f + 1.5)
					end
					prev = p
				end
			end)
			if not ok then break end
		end
		local result = { points = points, reversals = reversals }
		sampleCache[key] = result
		return result
	end

	-- NodeViewer config: every route piece coloured along the start-to-end
	-- gradient, reversing pieces in their own colour and wider.
	local function routeNodeConfig(loop)
		local edges = loop.loopEdges or {}
		local config = {}
		local n = #edges
		for i, e in ipairs(edges) do
			local d = api.type.NodeViewerData.new()
			d.edgeIdx = e.index
			if e.reversal or (edges[i + 1] ~= nil and edges[i + 1].reversal) then
				d.colors = { vec4(COLOUR_REVERSE), vec4(COLOUR_REVERSE) }
				d.width = 1.8
				d.order = 2
			else
				local t0, t1 = (i - 1) / math.max(n, 1), i / math.max(n, 1)
				local c0, c1 = mix(COLOUR_START, COLOUR_END, t0), mix(COLOUR_START, COLOUR_END, t1)
				d.colors = e.forward and { c0, c1 } or { c1, c0 } -- colours run start -> end of the piece
				d.width = 1.2
				d.order = 1
			end
			config[e.entity] = config[e.entity] or {}
			table.insert(config[e.entity], d)
		end
		-- the clicked pieces, as thin white lines on top
		for _, w in ipairs(loop.waypoints or {}) do
			local d = api.type.NodeViewerData.new()
			d.edgeIdx = w.index
			d.colors = { api.type.Vec4f.new(1, 1, 1, 0.9), api.type.Vec4f.new(1, 1, 1, 0.9) }
			d.width = 0.45
			d.order = 3
			config[w.entity] = config[w.entity] or {}
			table.insert(config[w.entity], d)
		end
		return config
	end

	local function pieceMiddle(piece)
		local ok, p = pcall(function() return api.engine.util.transport.calcPosition(edgeGeometry(piece), 0.5) end)
		return ok and p or nil
	end

	-- Markers on the map, called every frame: dots flowing along the route in
	-- the direction of travel, a marker on each clicked point, and one at each
	-- reversal.
	local function spawnRouteMarkers(loop, frame)
		if frame % 10 == 0 then
			local s = routeSamples(loop, 12.0)
			local phase = math.floor(frame / 10) % 4
			for i = 1 + phase, #s.points, 4 do
				pcall(api.gui.spawnEphemeralHudImage, ICON.dot, nil, api.type.Vec4f.new(1, 1, 1, 0.9), s.points[i], 0.3, true, true)
			end
		end
		if frame % 60 == 0 then
			for _, w in ipairs(loop.waypoints or {}) do
				local p = pieceMiddle(w)
				if p ~= nil then
					pcall(api.gui.spawnEphemeralHudImage, ICON.waypoint, nil, nil, api.type.Vec3f.new(p.x, p.y, p.z + 4.0), 1.05, false, false)
				end
			end
			for _, r in ipairs(routeSamples(loop, 12.0).reversals) do
				pcall(api.gui.spawnEphemeralHudImage, ICON.reverse, nil, vec4(COLOUR_REVERSE), api.type.Vec3f.new(r.x, r.y, r.z + 6.0), 1.05, false, false)
			end
		end
	end

	-- ------------------------------------------------------------------
	-- The route tool: draws the route; in edit mode, clicking track adds points.
	-- ------------------------------------------------------------------
	local TOOL_KEY_PREFIX = "RunAroundRoute:"

	local function getToolStackApi()
		local globals = ug_require "::/gui/main/game_react_globals.tl"
		return globals.getDefaultToolStackApi()
	end

	local function selectorColours()
		local ok, result = pcall(function()
			local color_util = ug_require "::/gui/main/color_util.tl"
			local selection = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/selection_colors.gres")).data.default
			local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data
			return {
				selectionColor = color_util.toVec4(selection.selectionColor),
				selectionOutlineColor = color_util.withTransparency(selection.selectionOutlineColor, transparency.Low),
				selectionOutlineColor1 = color_util.toVec4(selection.selectionOutlineColor),
				circleBorderColor = color_util.withTransparency(selection.selectionCircleColor, transparency.Low),
				crosshairColor = color_util.toVec4(selection.crosshairColor),
			}
		end)
		return ok and result or {}
	end

	-- A click on the map. Track gives either rich edge details or the track
	-- segment's entity (then its first transport-network edge is used).
	local function addPointFromClick(loopId, entity, apiDetails)
		local handled = false
		pcall(function()
			local data = apiDetails and apiDetails.data
			if data ~= nil and data.kind == api.gui.SelectionDetails.Type.TransportNetworkEdge then
				local edgeId = data.snap.edgeId
				sendGuiCmd("AddLoopEdgeFromWorldClick", { loopId = loopId, entity = edgeId.entity, index = edgeId.index })
				handled = true
				return
			end
			if entity ~= nil and entity >= 0 and api.engine.getComponent(entity, api.type.ComponentType.BASE_EDGE) ~= nil then
				local tn = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_NETWORK)
				if tn ~= nil and tn.edges ~= nil and #tn.edges > 0 then
					sendGuiCmd("AddLoopEdgeFromWorldClick", { loopId = loopId, entity = entity, index = 0 })
					handled = true
				end
			end
		end)
		return handled
	end

	-- The tool's action: returns the ActionDescriptor directly (the shape the base
	-- game and the previous, working version of this tool use).
	local function routeToolAction(param)
		local stateRef = react.useState(readState())
		local frame = react.useRef(0)
		react.onStep(function()
			local f = frame:get() + 1
			frame:set(f)
			if f < 10 and param.keepWindowId ~= nil then
				pcall(api.gui.byId.setVisible, param.keepWindowId, true)
			end
			if f % 15 == 0 then stateRef:set(readState()) end
			local loop = findLoop(stateRef:old() or { loops = {} }, param.loopId)
			if loop ~= nil then pcall(spawnRouteMarkers, loop, f) end
		end)
		local loop = findLoop(stateRef:old() or { loops = {} }, param.loopId)
		local children = {}
		if loop ~= nil then
			local okCfg, cfg = pcall(routeNodeConfig, loop)
			if okCfg then children[#children + 1] = builtin.NodeViewer{ nodeConfig = cfg } end
		end
		if param.edit then
			local selector = {
				stopOnMenuBack = false,
				filter = function(_entity) return true end,
				onHover = function() end,
				onSelect = function(entity, _indices, apiDetails) return addPointFromClick(param.loopId, entity, apiDetails) end,
				onSelectNothing = function() return false end,
				onSelectSecondary = function()
					param.finish()
					return true
				end,
			}
			for k, v in pairs(selectorColours()) do selector[k] = v end
			children[#children + 1] = builtin.Selector(selector)
		end
		return builtin.ActionDescriptor{
			horizontalPromptList = true,
			children = children,
			terrainCirclePolicy = "Never",
			onBack = param.finish,
		}
	end

	local RunAroundRouteTool = react.RegisterTool({
		name = "RunAroundRouteTool",
		push = function(ctx, param)
			local function finish() ctx.popSelf() end
			if param.keepWindowId ~= nil then pcall(api.gui.byId.setVisible, param.keepWindowId, true) end
			ctx.setActionFn(function()
				return routeToolAction({ loopId = param.loopId, edit = param.edit, keepWindowId = param.keepWindowId, finish = finish })
			end)
		end,
		pop = function(_ctx, _param) end,
		shelve = function(_ctx, _param, _shelve) end,
	})

	-- Which loop / mode the route tool is showing, or nil.
	local function activeRouteTool()
		local ok, key = pcall(function()
			local _, k = getToolStackApi().getActiveTool()
			return k
		end)
		if not ok or type(key) ~= "string" or string.sub(key, 1, #TOOL_KEY_PREFIX) ~= TOOL_KEY_PREFIX then return nil end
		local mode, id = string.match(string.sub(key, #TOOL_KEY_PREFIX + 1), "^(%a+):(%d+)$")
		return tonumber(id), mode, key
	end

	-- Switches the route tool for a loop on (in the given mode) or off.
	local function toggleRouteTool(loopId, edit, vehicleEntity)
		pcall(function()
			local stack = getToolStackApi()
			local activeId, activeMode, activeKey = activeRouteTool()
			local mode = edit and "edit" or "view"
			if activeKey ~= nil then
				stack.pop(RunAroundRouteTool, activeKey)
				if activeId == loopId and activeMode == mode then return end
			end
			local keepWindowId = vehicleEntity ~= nil and ("temp.view.entity_" .. tostring(vehicleEntity)) or nil
			stack.push(RunAroundRouteTool, TOOL_KEY_PREFIX .. mode .. ":" .. tostring(loopId),
				{ loopId = loopId, edit = edit, keepWindowId = keepWindowId }, true)
		end)
	end

	-- ------------------------------------------------------------------
	-- Loop card content
	-- ------------------------------------------------------------------
	local PHASES = {
		[""] = "Running round",
		flip = "Turning the train",
		settle = "Turning the train",
		approach = "Coupling on",
		finish = "Coupling on",
		verify = "Coupled",
	}

	local function routeLine(loop)
		local points = loop.waypoints and #loop.waypoints or 0
		if points == 0 then return "No route yet: click a few points on the track.", ICON.warn end
		if loop.routeLength == nil then return tostring(loop.pathStatus or "No route yet"), ICON.warn end
		local rev = loop.routeReversals or 0
		return string.format("%d m, %d reversal%s, %d point%s", math.floor(loop.routeLength + 0.5), rev, rev == 1 and "" or "s",
			points, points == 1 and "" or "s"), ICON.ok
	end

	local function RunStatus(loop, runs, vehicleEntity)
		for _, run in ipairs(runs) do
			if run.loop ~= nil and run.loop.id == loop.id and (vehicleEntity == nil or run.vehicleEntity == vehicleEntity) then
				local text = PHASES[run.phase or ""] or "Running round"
				local progress = 0.0
				if run.phase == nil and (loop.routeLength or 0) > 0 then
					progress = math.min((run.gdist or 0) / loop.routeLength, 1.0)
				elseif run.phase ~= nil then
					progress = 1.0
				end
				return Column({
					Row({ Icon(ICON.train), Text(text, "font-scale-body") }),
					builtin.ProgressBar{ value = progress, applyGradient = false },
				})
			end
		end
		return nil
	end

	local LoopSummary = react.RegisterRecipe("RunAroundLoopSummary", function(param)
		local loop = param.loop
		local text, icon = routeLine(loop)
		local activeId, activeMode = activeRouteTool()
		local editing = activeId == loop.id and activeMode == "edit"
		local viewing = activeId == loop.id and activeMode == "view"
		local children = {
			Text(loopPlace(loop), "font-scale-annotation"),
			Row({ Icon(icon), Text(text, "font-scale-body") }),
			RunStatus(loop, param.runs, param.vehicleEntity),
			Row({
				IconButton(ICON.edit, editing and "Done" or "Edit route on map",
					"Draws the route on the track. Click a few points along where the loco should go, in order; the route and the reversals are worked out for you. Right-click or Esc when done.",
					function() toggleRouteTool(loop.id, true, param.vehicleEntity) end, editing and "secondary" or "primary"),
				IconButton(ICON.eye, viewing and "Hide" or "Show",
					"Show the route on the track",
					function() toggleRouteTool(loop.id, false, param.vehicleEntity) end, "secondary"),
			}),
		}
		if editing then
			children[#children + 1] = Text("Click track to add points in order (a piece of the loop, then track at the far end of the train). Right-click or Esc to finish.", "font-scale-annotation")
			children[#children + 1] = Row({
				IconButton(ICON.undo, "Undo point", "Remove the last point", function() sendGuiCmd("RemoveLastLoopEdge", { loopId = loop.id }) end, "secondary"),
				IconButton(ICON.trash, "Clear points", "Remove every point", function() sendGuiCmd("ClearLoopPoints", { loopId = loop.id }) end, "secondary"),
			})
		end
		return Column(children)
	end)

	local LoopSettings = react.RegisterRecipe("RunAroundLoopSettings", function(param)
		local loop = param.loop
		local renaming = react.useState(false)
		local confirmDelete = react.useState(false)
		local speed = kmh(loop.speed)
		local accel = math.floor((loop.accel or 2.0) * 10 + 0.5)
		local locoText = loop.locoManual
			and ("Part " .. tostring(loop.locoCandidateIndex) .. " of the train (" .. tostring(loop.locoModelName or loop.locoModelId) .. ")")
			or "Automatic: the part nearest the first route point"
		return Column({
			Row({
				renaming:old() and gui_react_util.FocusTextInputField{
					value = loop.name or "",
					maxLength = 40,
					onValueChange = function(value)
						sendGuiCmd("RenameLoop", { loopId = loop.id, newName = value })
						renaming:set(false)
					end,
					onCancel = function() renaming:set(false) end,
				} or Text(loop.name or "Run-around", "font-scale-body"),
				not renaming:old() and IconButton(ICON.edit, nil, "Rename", function() renaming:set(true) end, "secondary") or nil,
			}),
			Text("Speed: " .. speed .. " km/h", "font-scale-body"),
			builtin.Slider{
				min = 10, max = 100, step = 5, pageStep = 10, value = speed,
				onValueChange = function(v)
					sendGuiCmd("SetLoopNumberField", { loopId = loop.id, field = "speed", value = v / 3.6 })
				end,
			},
			Text(string.format("Acceleration: %.1f m/s²", accel / 10), "font-scale-body"),
			builtin.Slider{
				min = 5, max = 40, step = 1, pageStep = 5, value = accel,
				onValueChange = function(v)
					sendGuiCmd("SetLoopNumberField", { loopId = loop.id, field = "accel", value = v / 10 })
				end,
			},
			Text("Loco: " .. locoText, "font-scale-body"),
			param.vehicleEntity ~= nil and IconButton(ICON.train, "Change loco choice", "Step through automatic and each part of this train",
				function() sendGuiCmd("CycleLocoCandidate", { loopId = loop.id, vehicleEntity = param.vehicleEntity }) end, "secondary") or nil,
			confirmDelete:old() and Row({
				Text("Delete this run-around?", "font-scale-body"),
				IconButton(nil, "Delete", "Delete it", function()
					sendGuiCmd("RemoveLoop", { loopId = loop.id })
					confirmDelete:set(false)
				end, "negative"),
				IconButton(nil, "Keep", "Keep it", function() confirmDelete:set(false) end, "secondary"),
			}) or IconButton(ICON.trash, "Delete run-around", "Delete this run-around", function() confirmDelete:set(true) end, "negative"),
		})
	end)

	-- A plain fallback when the game's content card is not available.
	local function Card(title, permanent, collapsible)
		return Column({ Text(title, "font-scale-title-4"), permanent, collapsible }, "box-plugin-vertical-space")
	end

	local function LoopCard(loop, st, params, vehicleEntity)
		local summary = LoopSummary{ loop = loop, runs = st.runs, vehicleEntity = vehicleEntity }
		local settings = LoopSettings{ loop = loop, vehicleEntity = vehicleEntity }
		if content_card == nil or params == nil then return Card(loop.name or "Run-around", summary, settings) end
		local key = "runaround_settings_" .. tostring(loop.id)
		return content_card.ContentCard{
			title = "Run-around: " .. (loop.name or ""),
			extraChildrenPermanent = { summary },
			hasPermanentFocusables = true,
			initialCalloutTextCollapsible = "",
			recipeAndParamCollapsible = content_card.makeRecipeAndParam(LoopSettings, { loop = loop, vehicleEntity = vehicleEntity }),
			setCollapsibleExpanded = params.setCollapsibleExpanded and function(v) params.setCollapsibleExpanded(key, v) end or nil,
			collapsibleExpanded = params.getCollapsibleExpanded and params.getCollapsibleExpanded(key) or nil,
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		}
	end

	-- ------------------------------------------------------------------
	-- Train window card
	-- ------------------------------------------------------------------
	local VehiclePanel = react.RegisterRecipe("RunAroundVehiclePanel", function(params)
		local vehicleEntity = params.entityId
		local st = react.useState(readState())
		local tick = react.useRef(0)
		react.onStep(function()
			tick:set(tick:get() + 1)
			if tick:get() % 10 == 0 then st:set(readState()) end
		end)
		local state = st:old() or { loops = {}, runs = {} }
		local line, stop = vehicleLineAndStop(vehicleEntity)
		if line == nil or line < 0 then return Column({}) end

		local cards = {}
		local hereHasLoop = false
		for _, loop in ipairs(state.loops) do
			if loop.lineEntity == line then
				cards[#cards + 1] = LoopCard(loop, state, params, vehicleEntity)
				if loop.stopIndex == stop then hereHasLoop = true end
			end
		end
		if not hereHasLoop then
			local intro = Column({
				Text("Have the loco run round its train at this stop instead of the instant flip.", "font-scale-body"),
				IconButton(ICON.add, "Set up a run-around here", "Creates a run-around for this line at the stop this train is at",
					function() sendGuiCmd("AddLoopFromVehicle", { vehicleEntity = vehicleEntity }) end, "primary"),
			})
			if content_card ~= nil and #cards == 0 then
				cards[#cards + 1] = content_card.ContentCard{
					title = "Run-around",
					extraChildrenPermanent = { intro },
					hasPermanentFocusables = true,
					gameCtx = params.gameCtx,
					showOnRightSide = params.showCalloutOnRightSide,
				}
			else
				cards[#cards + 1] = intro
			end
		end
		return Column(cards, "box-plugin-vertical-space")
	end)

	-- ------------------------------------------------------------------
	-- Mod-button panel: every loop
	-- ------------------------------------------------------------------
	local AllLoopsPanel = react.RegisterRecipe("RunAroundAllLoops", function()
		local st = react.useState(readState())
		local tick = react.useRef(0)
		react.onStep(function()
			tick:set(tick:get() + 1)
			if tick:get() % 15 == 0 then st:set(readState()) end
		end)
		local state = st:old() or { loops = {}, runs = {} }
		local rows = { Text("Run-arounds", "font-scale-title-4") }
		if #state.loops == 0 then
			rows[#rows + 1] = Text("None yet. Open a train's window at a terminus and choose \"Set up a run-around here\".", "font-scale-body")
		end
		for _, loop in ipairs(state.loops) do
			local text, icon = routeLine(loop)
			rows[#rows + 1] = Column({
				Text(loop.name or "Run-around", "font-scale-body"),
				Text(loopPlace(loop), "font-scale-annotation"),
				Row({ Icon(icon), Text(text, "font-scale-annotation") }),
				RunStatus(loop, state.runs, nil),
				Row({
					IconButton(ICON.eye, "Show on map", "Draw this route on the track (Esc to hide)", function() toggleRouteTool(loop.id, false, nil) end, "secondary"),
					IconButton(ICON.edit, "Edit route", "Edit this route on the map", function() toggleRouteTool(loop.id, true, nil) end, "secondary"),
				}),
				LoopSettings{ loop = loop, vehicleEntity = nil },
			}, "box-plugin-vertical-space")
		end
		return Column(rows)
	end)

	local function ToggleButtonPanel()
		local open = react.useState(false)
		return Column({
			IconButton(ICON.route, "Run-Around", "Run Around Helper: every run-around", function() open:set(not open:old()) end),
			open:old() and AllLoopsPanel{} or nil,
		})
	end

	local RunAroundHelperButton = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "RunAroundHelperButton", ToggleButtonPanel)
	local RunAroundHelperEntry = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "RunAroundHelperEntry", ToggleButtonPanel)

	local RunAroundHelperVehiclePlugin = nil
	if vehicle_eow ~= nil then
		local ok, recipe = pcall(function()
			return react.RegisterPluginRecipe(vehicle_eow.VehicleEowExtensionPoint, "RunAroundHelperVehiclePlugin", function(params)
				return VehiclePanel(params)
			end)
		end)
		if ok then RunAroundHelperVehiclePlugin = recipe else print("[RunAroundHelper] vehicle window plugin failed:", recipe) end
	end

	print("[RunAroundHelper] GUI registered")

	return {
		RunAroundHelperButton = RunAroundHelperButton,
		RunAroundHelperEntry = RunAroundHelperEntry,
		RunAroundHelperVehiclePlugin = RunAroundHelperVehiclePlugin,
	}
end
