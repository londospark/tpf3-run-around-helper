--[[
	Run Around Helper - GUI layer

	LOADING MECHANISM (confirmed working - third attempt, and this one is
	backed by two independent real, shipped TpF3 mods, not inference):

	A react-based GUI plugin needs a companion ".res.lua" resource
	descriptor - a bare script file that calls react.RegisterPluginRecipe is
	NEVER require()'d on its own; nothing auto-discovers it the way *.gs.lua
	files are auto-discovered. This was confirmed by two real mods' source:
	  - github.com/Juliansgith/Transport-Fever-3-Multiplayer-Mod (tpf3mp_1),
	    whose own res.lua's comment states outright: "react-plugin resources
	    are how mods made for Transport Fever 3 build 40391 get their code
	    run".
	  - github.com/schbrongx/tf3mod-minimap, which registers on the SAME two
	    extension points this file already used before this fix
	    (MainModButtonAreaExtension, ModEntryPointExtension) - confirming
	    those extension point choices were right all along; the missing
	    piece was purely the .res.lua descriptor(s), one per plugin.

	The .res.lua pattern (see runaround_button.res.lua / runaround_entry.res.lua
	next to this file):
		function data()
			return {
				type = "react-plugin ::<ExtensionPointName>",
				data = { filePath = "<modId>::/<path-to-this-file-minus-extension>@<ExportedName>" }
			}
		end
	filePath resolves from the MOD ROOT (same rule already confirmed for
	*.gs.lua's fileName), and <ExportedName> is looked up in whatever this
	file's data() function (or bare top-level return - both real examples
	were checked and use different styles, so both are apparently accepted)
	returns.

	WHAT THIS PANEL DOES
	Lets you configure run-around loops from inside the game instead of
	hand-editing Lua: pick a vehicle sitting at your chosen terminus, click
	"Add loop from this vehicle" (captures line/stop/candidate loco
	automatically), then drive that same loco around your loop track and
	click "Capture edge here" once per edge to record the path. A
	"Run-Around" button (mounted two ways - see below) lists/renames/tunes/
	deletes configured loops.

	Mounted in three places, in descending order of confidence:
	  1. MainModButtonAreaExtension (RunAroundHelperButton) - confirmed real
	     extension point (tf3mod-minimap uses it for its own toggle button).
	  2. ModEntryPointExtension (RunAroundHelperEntry) - also confirmed real
	     (tf3mod-minimap's second plugin; gui/main/game.tl mounts these into
	     the main screen's floating layout).
	  3. VehicleEowExtensionPoint (RunAroundHelperVehiclePlugin) - NOT
	     confirmed by either real example found so far, kept as a bonus
	     best-effort attempt (wrapped in pcall so a failure here can't break
	     the other two, confirmed ones). This is the only one that gets a
	     concrete vehicleEntity for free, which is why it's worth keeping
	     even at lower confidence - if it works, "Add loop from this
	     vehicle" and "Capture edge here" become available; if not, loops
	     can still be renamed/tuned/deleted from the other two mount points,
	     just not created (see the console fallback below).

	HOW IT TALKS TO THE ENGINE-SIDE SCRIPT
	This file never touches persistent state directly. Every action fires
	api.cmd.makeScriptingSendEventCmd("", <commandName>, "RunAroundGuiCmd", <param>)
	- note "RunAroundGuiCmd" is the NAME argument (3rd), not the id (2nd):
	subscribeToEvent matches by name, so the fixed channel string has to be
	there, with the per-command string traveling as id. (Got this backwards
	in an earlier version - cost a full debug cycle to find, since a
	swapped id/name pair fails silently with zero error anywhere.)
	runaround.script.lua's handleEvent receives it and applies to its own
	state. This file only ever *reads* the current loop list back out via
	api.engine.getComponent(...).state.loops.

	REMAINING RISK
	  - The exact resource-name string api.engine.system.gameScriptSystem.
	    getEntityForGameScript(...) expects for our "runaround" game script
	    is still a guess with a fallback candidate list (see
	    tryGetGameScriptEntity below) - if none resolve, the loop list here
	    shows empty even though the engine side works fine.
	  - VehicleEowExtensionPoint itself (see point 3 above).

	If any of this still doesn't render, the manual, no-GUI path (send
	"RunAroundGuiCmd" events yourself from the TpF3 dev console) still
	works, since none of this changed the underlying engine-side data shape:
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "AddLoopFromVehicle", "RunAroundGuiCmd", {vehicleEntity = <id>}))
]]

function data()
	local react = ug_require "::/gui/main/react.lua"
	local builtin = ug_require "::/gui/main/builtin.lua"
	local gui_react_util = ug_require "::/gui/main/gui_react_util.tl"
	local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"
	local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl"

	print("[RunAroundHelper] runaround_gui.script.lua data() executing")

	-- Best-effort require of the vehicle entity-window extension point -
	-- see "REMAINING RISK" above. Wrapped so a failure here can't take out
	-- the two confirmed mount points below.
	local vehicle_eow_ok, vehicle_eow = pcall(function()
		return ug_require "::/gui/entity_window/vehicle/vehicle_eow.script.tl"
	end)
	if not vehicle_eow_ok then
		print("[RunAroundHelper] could not require vehicle_eow.script.tl - vehicle-window panel will not be available:", vehicle_eow)
	end

	local GAME_SCRIPT_NAME_CANDIDATES = {
		"runaround",
		"runaround_helper_1::/res/scripts/runaround",
		"runaround_helper_1::/res/scripts/runaround.gs",
		"::/res/scripts/runaround",
		"res/scripts/runaround",
	}

	local resolvedGameScriptName = nil

	-- Tries each candidate resource name once and remembers whichever (if
	-- any) resolves to a real entity.
	local function tryGetGameScriptEntity()
		if resolvedGameScriptName ~= nil then
			return api.engine.system.gameScriptSystem.getEntityForGameScript(resolvedGameScriptName)
		end
		for _, candidate in ipairs(GAME_SCRIPT_NAME_CANDIDATES) do
			local ok, entity = pcall(api.engine.system.gameScriptSystem.getEntityForGameScript, candidate)
			if ok and entity ~= nil and entity >= 0 then
				resolvedGameScriptName = candidate
				print("[RunAroundHelper] GUI: resolved game script entity via name '" .. candidate .. "'")
				return entity
			end
		end
		return nil
	end

	-- Reads the live loop list straight off the engine-side GAME_SCRIPT
	-- component's state table. Returns {} if the entity/name couldn't be
	-- resolved rather than erroring, so the panel still renders.
	local function readLoops()
		local entity = tryGetGameScriptEntity()
		if entity == nil then
			return {}
		end
		local comp = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
		if comp == nil or comp.state == nil or comp.state.loops == nil then
			return {}
		end
		return comp.state.loops
	end

	-- makeScriptingSendEventCmd(src, id, name, param) - subscribeToEvent on
	-- the receiving end matches by NAME, so the fixed "RunAroundGuiCmd"
	-- channel has to be the name argument, and the per-command string
	-- (add/rename/etc) travels as id. This was swapped before and silently
	-- dropped every command, regardless of button or console.
	local function sendGuiCmd(commandName, param)
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", commandName, "RunAroundGuiCmd", param))
	end

	-- ------------------------------------------------------------------
	-- Click-to-pick tool.
	--
	-- CRASH LESSON (live, TpF3 build 40408): builtin.Selector CANNOT be a
	-- child of a window/panel widget tree. Doing that made the UI
	-- transformer assert "!IsTransformWithContext(node.recipeId)"
	-- (react_transform.cpp:97) and the whole game went down with an
	-- "Ungraceful exit" the first time the toggle was switched on. The base
	-- game only ever places a Selector inside a builtin.ActionDescriptor
	-- returned from a TOOL's action function (see vehicle.tl's
	-- params.setActionFn(...), and tool_react_util.tl where a tool's push()
	-- hands ctx.setActionFn on). So the toggle button below pushes a real
	-- registered tool (react.RegisterTool, same shape pause_menu.tl uses via
	-- prepareDefaultToolWithWindowDefinition) whose push() installs the
	-- action function; popping the tool removes the Selector again.
	-- ------------------------------------------------------------------
	local PICK_KEY_PREFIX = "RunAroundPickEdges:"

	-- Required lazily (minimap mod does the same for game_react_globals):
	-- pulling it in at load time drags in base-game modules before a game
	-- exists.
	local function getToolStackApi()
		local globals = ug_require "::/gui/main/game_react_globals.tl"
		return globals.getDefaultToolStackApi()
	end

	-- Highlight colours copied from selector_react_util.makeDefaultSelector.
	-- Guarded: if anything about this lookup is off we just skip the colours
	-- rather than risk the tool failing to install.
	local function makeSelectorColours()
		local ok, result = pcall(function()
			local color_util = ug_require "::/gui/main/color_util.tl"
			local selectionGres = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/selection_colors.gres")).data
			local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data
			local colours = selectionGres.default
			return {
				selectionColor = color_util.toVec4(colours.selectionColor),
				selectionOutlineColor = color_util.withTransparency(colours.selectionOutlineColor, transparency.Low),
				selectionOutlineColor1 = color_util.toVec4(colours.selectionOutlineColor),
				circleBorderColor = color_util.withTransparency(colours.selectionCircleColor, transparency.Low),
				crosshairColor = color_util.toVec4(colours.crosshairColor),
			}
		end)
		if not ok then
			print("[RunAroundHelper] pick tool: could not build selector colours (continuing without):", result)
			return {}
		end
		return result
	end

	-- What a click on the map turns into. Logs what it actually received so
	-- a click that does nothing is diagnosable from the log alone.
	local function handlePickSelect(loopId, entity, apiDetails)
		local handled = false
		local ok, err = pcall(function()
			local data = apiDetails and apiDetails.data
			local kind = data and data.kind
			print("[RunAroundHelper] pick: clicked entity=", entity, "kind=", kind)

			-- Preferred: the rich selection details carry the track edge
			-- directly (same field path manager_window.tl reads).
			if data ~= nil and kind == api.gui.SelectionDetails.Type.TransportNetworkEdge then
				local edgeId = data.snap.edgeId
				sendGuiCmd("AddLoopEdgeFromWorldClick", { loopId = loopId, entity = edgeId.entity, index = edgeId.index })
				handled = true
				return
			end

			-- Fallback: a plain click on track selects the track segment's
			-- own entity (it carries BASE_EDGE + TRANSPORT_NETWORK - the
			-- base game's default selector deliberately filters these out).
			-- No hit position tells us WHICH transport-network edge of that
			-- entity was meant, so take index 0 and say so.
			if entity ~= nil and entity >= 0 and api.engine.getComponent(entity, api.type.ComponentType.BASE_EDGE) ~= nil then
				local tn = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_NETWORK)
				if tn ~= nil and tn.edges ~= nil and #tn.edges > 0 then
					print("[RunAroundHelper] pick: no edge details in click; falling back to edge index 0 of track entity", entity, "(it has", #tn.edges, "edges)")
					sendGuiCmd("AddLoopEdgeFromWorldClick", { loopId = loopId, entity = entity, index = 0 })
					handled = true
				end
			end
		end)
		if not ok then
			print("[RunAroundHelper] pick: error while handling a click:", err)
		end
		return handled
	end

	local RunAroundPickTool = react.RegisterTool({
		name = "RunAroundPickTool",
		push = function(ctx, param)
			local colours = makeSelectorColours()
			ctx.setActionFn(function()
				local selectorParam = {
					stopOnMenuBack = false,
					-- Allow track-segment entities (the default filter
					-- rejects BASE_EDGE ones).
					filter = function(_entity) return true end,
					onHover = function(_entity, _indices, _apiDetails) end,
					onSelect = function(entity, _indices, apiDetails)
						return handlePickSelect(param.loopId, entity, apiDetails)
					end,
					onSelectNothing = function() return false end,
				}
				for k, v in pairs(colours) do
					selectorParam[k] = v
				end
				return builtin.ActionDescriptor{
					horizontalPromptList = true,
					children = { builtin.Selector(selectorParam) },
					terrainCirclePolicy = "Never",
				}
			end)
		end,
		pop = function(_ctx, _param) end,
		shelve = function(_ctx, _param, _shelve) end,
	})

	local function loopSummaryText(loop)
		return (loop.name or "?") ..
			"  line=" .. tostring(loop.lineEntity) ..
			" stop=" .. tostring(loop.stopIndex) ..
			" loco=" .. tostring(loop.locoModelId) ..
			" points=" .. tostring(loop.waypoints and #loop.waypoints or 0)
	end

	-- One row per configured loop: rename field, tuning toggles, and (when
	-- vehicleEntity is available, i.e. we're inside the vehicle-window
	-- variant) the buttons that need a concrete vehicle to read from.
	local function LoopRow(loop, vehicleEntity)
		local nameEditState = react.useState(false)
		local pickModeState = react.useState(false)

		local children = {
			builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					nameEditState:old()
						and gui_react_util.FocusTextInputField{
							value = loop.name or "",
							onValueChange = function(value)
								sendGuiCmd("RenameLoop", { loopId = loop.id, newName = value })
								nameEditState:set(false)
							end,
							onCancel = function() nameEditState:set(false) end,
							maxLength = 40,
						}
						or builtin.TextView{ text = loopSummaryText(loop) },
					builtin.TextView{ text = "Route: " .. (loop.pathStatus or "no points yet") },
					builtin.Button{
						meta = { tooltip = "Rename" },
						content = builtin.TextView{ text = "Rename" },
						onClick = function() nameEditState:set(true) end,
					},
					builtin.Button{
						meta = { tooltip = "Cruise speed (m/s), click to bump +1, tuned in-file beyond that" },
						content = builtin.TextView{ text = "Speed " .. tostring(loop.speed) },
						onClick = function()
							sendGuiCmd("SetLoopNumberField", { loopId = loop.id, field = "speed", value = (loop.speed or 8.0) + 1.0 })
						end,
					},
					builtin.Button{
						meta = { tooltip = "Toggle which end of the consist the loco reattaches to" },
						content = builtin.TextView{ text = "Loco end: " .. (loop.locoLeadsWithFirstArrayEntry and "front" or "back") },
						onClick = function()
							sendGuiCmd("ToggleLoopBoolField", { loopId = loop.id, field = "locoLeadsWithFirstArrayEntry" })
						end,
					},
					builtin.Button{
						meta = { tooltip = "Toggle whether the loco's reversed flag flips on recouple" },
						content = builtin.TextView{ text = "Flip on recouple: " .. (loop.flipLocoReversedOnRecouple and "yes" or "no") },
						onClick = function()
							sendGuiCmd("ToggleLoopBoolField", { loopId = loop.id, field = "flipLocoReversedOnRecouple" })
						end,
					},
					builtin.Button{
						meta = { tooltip = "Remove the last route point (the route is re-planned)" },
						content = builtin.TextView{ text = "Undo last point" },
						onClick = function() sendGuiCmd("RemoveLastLoopEdge", { loopId = loop.id }) end,
					},
					builtin.Button{
						meta = { tooltip = "Delete this loop entirely" },
						content = builtin.TextView{ text = "Delete loop" },
						onClick = function() sendGuiCmd("RemoveLoop", { loopId = loop.id }) end,
					},
				},
			},
		}

		if vehicleEntity ~= nil then
			children[#children + 1] = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					builtin.Button{
						meta = { tooltip = "Use this vehicle's current model as the loco to detach" },
						content = builtin.TextView{ text = "Cycle loco candidate" },
						onClick = function() sendGuiCmd("CycleLocoCandidate", { loopId = loop.id, vehicleEntity = vehicleEntity }) end,
					},
					builtin.Button{
						meta = { tooltip = "Adds the track piece this train is on as the next route point (the train has to be sitting there)" },
						content = builtin.TextView{ text = "Add point at this train" },
						onClick = function() sendGuiCmd("AddLoopEdgeFromVehicle", { loopId = loop.id, vehicleEntity = vehicleEntity }) end,
					},
				},
			}
		end

		-- Click-to-pick: toggles RunAroundPickTool (defined above) on/off.
		-- The Selector lives inside that tool's action function, NOT in this
		-- panel - putting it here crashed the game (see the comment on the
		-- tool). While the tool is active, clicking track in the world
		-- appends an edge to this loop - no train needs to be sitting on
		-- the track, unlike "Capture edge here".
		children[#children + 1] = builtin.Button{
			meta = { tooltip = "Toggle click-to-pick mode, then click track in the world to append edges to this loop" },
			content = builtin.TextView{ text = "Pick route points on map: " .. (pickModeState:old() and "ON (click track)" or "off") },
			onClick = function()
				local key = PICK_KEY_PREFIX .. tostring(loop.id)
				local ok, err = pcall(function()
					local toolStack = getToolStackApi()
					if pickModeState:old() then
						toolStack.pop(RunAroundPickTool, key)
						pickModeState:set(false)
					else
						toolStack.push(RunAroundPickTool, key, { loopId = loop.id }, false)
						pickModeState:set(true)
					end
				end)
				if not ok then
					print("[RunAroundHelper] pick mode toggle failed:", err)
				end
			end,
		}

		if pickModeState:old() then
			children[#children + 1] = builtin.TextView{ text = "The route starts at this station stop. Click track in the order the loco travels:" }
			children[#children + 1] = builtin.TextView{ text = " 1) the track beyond the points, where the loco stops and reverses" }
			children[#children + 1] = builtin.TextView{ text = " 2) a piece of the loop" }
			children[#children + 1] = builtin.TextView{ text = " 3) the track at the far end of the train" }
			children[#children + 1] = builtin.TextView{ text = "Add extra clicks for a wye. The route between clicks is found for you." }
		end

		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
	end

	-- Shared panel body. vehicleEntity is nil in the button/entry-point
	-- variants (no vehicle context there) and set in the vehicle-window
	-- variant.
	local function LoopsPanel(vehicleEntity)
		local loopsState = react.useState({})
		react.onStep(function()
			loopsState:set(readLoops())
		end)
		local loops = loopsState:old() or {}

		local rows = {}
		for _, loop in ipairs(loops) do
			rows[#rows + 1] = LoopRow(loop, vehicleEntity)
		end

		if #rows == 0 then
			rows[1] = builtin.TextView{ text = "No run-around loops configured yet." }
		end

		local addButton = nil
		if vehicleEntity ~= nil then
			addButton = builtin.Button{
				meta = { tooltip = "Add a new loop using this vehicle's current line, stop and first vehicle part as loco" },
				content = builtin.TextView{ text = "Add loop from this vehicle" },
				onClick = function() sendGuiCmd("AddLoopFromVehicle", { vehicleEntity = vehicleEntity }) end,
			}
		end

		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Vertical,
			children = {
				builtin.TextView{ meta = { class = "font-scale-body" }, text = "Run Around Helper" },
				addButton,
				builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = rows },
			},
		}
	end

	-- Mount 1 (confirmed real extension point): a toggle button in the
	-- main mod button area, with no vehicle context - list/rename/tune/
	-- delete only.
	local RunAroundHelperButton = react.RegisterPluginRecipe(
		main_mod_button_area.MainModButtonAreaExtension,
		"RunAroundHelperButton",
		function()
			local openState = react.useState(false)
			return builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					builtin.Button{
						meta = { tooltip = "Run Around Helper - manage loops" },
						content = builtin.TextView{ text = "Run-Around" },
						onClick = function() openState:set(not openState:old()) end,
					},
					openState:old() and LoopsPanel(nil) or nil,
				},
			}
		end
	)

	-- Mount 2 (confirmed real extension point): the same panel via the
	-- main screen's floating layout, as an independent second shot at
	-- getting this visible.
	local RunAroundHelperEntry = react.RegisterPluginRecipe(
		mod_entry_point.ModEntryPointExtension,
		"RunAroundHelperEntry",
		function()
			local openState = react.useState(false)
			return builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = {
					builtin.Button{
						meta = { tooltip = "Run Around Helper - manage loops" },
						content = builtin.TextView{ text = "Run-Around" },
						onClick = function() openState:set(not openState:old()) end,
					},
					openState:old() and LoopsPanel(nil) or nil,
				},
			}
		end
	)

	-- Mount 3 (best-effort, NOT confirmed by a real example - see
	-- "REMAINING RISK" above): a panel inside the vehicle info window,
	-- which gets a real vehicleEntity for free and is the only mount that
	-- can actually create loops / capture edges.
	local RunAroundHelperVehiclePlugin = nil
	if vehicle_eow_ok and vehicle_eow ~= nil then
		local ok, recipe = pcall(function()
			return react.RegisterPluginRecipe(
				vehicle_eow.VehicleEowExtensionPoint,
				"RunAroundHelperVehiclePlugin",
				function(params)
					return LoopsPanel(params.entityId)
				end
			)
		end)
		if ok then
			RunAroundHelperVehiclePlugin = recipe
		else
			print("[RunAroundHelper] VehicleEowExtensionPoint plugin registration failed:", recipe)
		end
	end

	print("[RunAroundHelper] runaround_gui.script.lua GUI recipes registered")

	return {
		RunAroundHelperButton = RunAroundHelperButton,
		RunAroundHelperEntry = RunAroundHelperEntry,
		RunAroundHelperVehiclePlugin = RunAroundHelperVehiclePlugin,
	}
end
