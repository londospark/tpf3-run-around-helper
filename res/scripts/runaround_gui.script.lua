--[[
	Runaround Railways - GUI

	  * A "Run-around" card in the train window (VehicleEowExtensionPoint): set up
	    a run-around at the stop the train is at, see the route and a live run,
	    edit the route on the map, and tune it.
	  * The route tool: while it is active the loop's route is drawn on the
	    track (builtin.NodeViewer: a colour gradient from start to finish, the
	    reversing pieces highlighted, the clicked pieces marked), and in edit mode
	    clicking track adds a point (builtin.Selector).

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

	local function stopStationName(lineEntity, stopIndex)
		local ok, name = pcall(function()
			local l = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE)
			return entityName(l.stops[stopIndex + 1].stationGroup)
		end)
		return ok and name or nil
	end

	-- A loop's display name: its own, unless it still has an old default name
	-- ("Loop 3"), in which case the station it is at.
	local function loopName(loop)
		local name = loop.name
		if name == nil or name == "" or string.match(name, "^Loop %d+$") then
			return stopStationName(loop.lineEntity, loop.stopIndex) or name or "Run-around"
		end
		return name
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

	-- A group of buttons one above the other with the entity window's spacing
	-- (buttons side by side had no gap between them).
	local function Buttons(list)
		return Column(list, "box-plugin-vertical-space")
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
		pop = function(_ctx, param)
			if routeTool ~= nil and routeTool.loopId == param.loopId then routeTool = nil end
		end,
		shelve = function(_ctx, _param, _shelve) end,
	})

	-- Which loop / mode the route tool is showing: tracked here (asking the tool
	-- stack did not report it back, so the Show button never turned into Hide).
	local routeTool = nil -- { loopId, mode, key }
	local function activeRouteTool()
		if routeTool == nil then return nil end
		return routeTool.loopId, routeTool.mode, routeTool.key
	end

	-- Switches the route tool for a loop on (in the given mode) or off.
	local function toggleRouteTool(loopId, edit, vehicleEntity)
		pcall(function()
			local stack = getToolStackApi()
			local mode = edit and "edit" or "view"
			if routeTool ~= nil then
				local same = routeTool.loopId == loopId and routeTool.mode == mode
				pcall(stack.pop, RunAroundRouteTool, routeTool.key)
				routeTool = nil
				if same then return end
			end
			local key = TOOL_KEY_PREFIX .. mode .. ":" .. tostring(loopId)
			local keepWindowId = vehicleEntity ~= nil and ("temp.view.entity_" .. tostring(vehicleEntity)) or nil
			routeTool = { loopId = loopId, mode = mode, key = key }
			stack.push(RunAroundRouteTool, key, { loopId = loopId, edit = edit, keepWindowId = keepWindowId }, true)
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
			Buttons({
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
			children[#children + 1] = Buttons({
				IconButton(ICON.undo, "Undo point", "Remove the last point", function() sendGuiCmd("RemoveLastLoopEdge", { loopId = loop.id }) end, "secondary"),
				IconButton(ICON.trash, "Clear points", "Remove every point", function() sendGuiCmd("ClearLoopPoints", { loopId = loop.id }) end, "secondary"),
			})
		end
		return Column(children, "box-plugin-vertical-space")
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
					value = loopName(loop),
					maxLength = 40,
					onValueChange = function(value)
						sendGuiCmd("RenameLoop", { loopId = loop.id, newName = value })
						renaming:set(false)
					end,
					onCancel = function() renaming:set(false) end,
				} or Text(loopName(loop), "font-scale-body"),
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
		if content_card == nil or params == nil then return Card(loopName(loop), summary, settings) end
		local key = "runaround_settings_" .. tostring(loop.id)
		return content_card.ContentCard{
			title = "Run-around: " .. loopName(loop),
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
		local taken = {}
		for _, loop in ipairs(state.loops) do
			if loop.lineEntity == line then
				cards[#cards + 1] = LoopCard(loop, state, params, vehicleEntity)
				taken[loop.stopIndex] = true
			end
		end
		-- "Add a run-around at <station>" for every stop of the line without one,
		-- the stop the train is at first.
		local stops = {}
		pcall(function()
			local l = api.engine.getComponent(line, api.type.ComponentType.LINE)
			for i = 1, #l.stops do stops[#stops + 1] = i - 1 end
		end)
		table.sort(stops, function(a, b) return (a == stop) and b ~= stop end)
		local addButtons = {}
		for _, s in ipairs(stops) do
			if not taken[s] then
				local station = stopStationName(line, s) or ("stop " .. tostring(s + 1))
				addButtons[#addButtons + 1] = IconButton(ICON.add, station .. (s == stop and "  (this stop)" or ""),
					"Set up a run-around for this line at " .. station,
					function() sendGuiCmd("AddLoopAtStop", { lineEntity = line, stopIndex = s, name = station, vehicleEntity = vehicleEntity }) end,
					(#cards == 0 and s == stop) and "primary" or "secondary")
			end
		end
		if #addButtons > 0 then
			local intro = Column({
				Text(#cards == 0 and "Have the loco run round its train at a terminus instead of the instant flip. Add a run-around at:"
					or "Add a run-around at:", "font-scale-body"),
				Buttons(addButtons),
			}, "box-plugin-vertical-space")
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

	local RunAroundHelperVehiclePlugin = nil
	if vehicle_eow ~= nil then
		local ok, recipe = pcall(function()
			return react.RegisterPluginRecipe(vehicle_eow.VehicleEowExtensionPoint, "RunAroundHelperVehiclePlugin", function(params)
				-- A plugin's own child must be a layout ("Recipe child must be a
				-- layout", seen live), so the panel component goes inside one.
				return Column({ VehiclePanel(params) })
			end)
		end)
		if ok then RunAroundHelperVehiclePlugin = recipe else print("[RunAroundHelper] vehicle window plugin failed:", recipe) end
	end

	print("[RunAroundHelper] GUI registered")

	return {
		RunAroundHelperVehiclePlugin = RunAroundHelperVehiclePlugin,
	}
end
