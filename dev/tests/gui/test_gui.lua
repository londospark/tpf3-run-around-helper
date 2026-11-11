local sent, spawned = {}, 0
local function node(kind) return function(p) return { kind = kind, p = p } end end
local builtin = setmetatable({ type = { Orientation = { Vertical = "V", Horizontal = "H" } } }, { __index = function(t, k) local f = node(k); rawset(t, k, f); return f end })
local actionFn
local toolDef
local react = {
  useState = function(v) local s = { v = v }; return { old = function() return s.v end, set = function(_, x) s.v = x end } end,
  useRef = function(v) local s = { v = v }; return { get = function() return s.v end, set = function(_, x) s.v = x end } end,
  onStep = function(f) lastStep = f; f() f() end,
  -- the game requires every recipe's own child to be a layout
  RegisterRecipe = function(name, fn) return function(p) local r = fn(p); assert(r == nil or r.kind == "BoxLayout", name .. " must return a layout, got " .. tostring(r and r.kind)); return { kind = "Recipe:" .. name, child = r } end end,
  RegisterPluginRecipe = function(ext, name, fn) return function(p) local r = fn(p); assert(r ~= nil and r.kind == "BoxLayout", name .. " must return a layout, got " .. tostring(r and r.kind)); return r end end,
  RegisterTool = function(def) toolDef = def; return def end,
}
-- fix useState/useRef method-call style (the GUI uses st:old(), st:set())
react.useState = function(v) local s = { v = v }; local o = {}; function o:old() return s.v end; function o:set(x) s.v = x end; return o end
react.useRef = function(v) local s = { v = v }; local o = {}; function o:get() return s.v end; function o:set(x) s.v = x end; return o end
local content_card = { ContentCard = node("ContentCard"), makeRecipeAndParam = function(r, p) return { r = r, p = p } end }
local toolStack = { active = nil }
function toolStack.getActiveTool() return nil, toolStack.active end
function toolStack.push(tool, key, param) toolStack.active = key; tool.push({ setActionFn = function(f) actionFn = f end, popSelf = function() toolStack.active = nil; tool.pop({}, param) end }, param) end
function toolStack.pop() toolStack.active = nil end
local modules = {
  ["::/gui/main/react.lua"] = react, ["::/gui/main/builtin.lua"] = builtin,
  ["::/gui/main/gui_react_util.tl"] = { FocusTextInputField = node("Focus") },
  ["::/gui/main/main_mod_button_area.tl"] = { MainModButtonAreaExtension = {} },
  ["::/gui/main/mod_entry_point.tl"] = { ModEntryPointExtension = {} },
  ["::/gui/main/content_card.tl"] = content_card,
  ["::/gui/entity_window/vehicle/vehicle_eow.script.tl"] = { VehicleEowExtensionPoint = {} },
  ["::/gui/main/game_react_globals.tl"] = { getDefaultToolStackApi = function() return toolStack end },
  ["::/gui/main/color_util.tl"] = { toVec4 = function() return {} end, withTransparency = function() return {} end },
}
local loops = { { id = 7, name = "Loop 1", lineEntity = 100, stopIndex = 0, speed = 8, accel = 2, waypoints = { { entity = 5, index = 0 }, { entity = 6, index = 1 } },
  loopEdges = { { entity = 5, index = 0, forward = true }, { entity = 6, index = 1, forward = false }, { entity = 6, index = 1, forward = true, reversal = true } },
  routeLength = 312.4, routePieces = 3, routeReversals = 1, pathStatus = "ok" } }
local runs = { { vehicleEntity = 42, loop = loops[1], gdist = 100 } }
api = {
  engine = {
    system = { gameScriptSystem = { getEntityForGameScript = function(n) return 9 end } },
    getComponent = function(e, c)
      if c == "GS" then return { state = { loops = loops, runs = runs } } end
      if c == "TV" then return { line = 100, stopIndex = 0 } end
      if c == "LINE" then return { stops = { { stationGroup = 55 } } } end
      if c == "TN" then return { edges = { { geometry = { x0 = e * 1000 } }, { geometry = { x0 = e * 1000 + 500 } } } } end
    end,
    util = { getEntityName = function(e) return "Name" .. e end, transport = { calcPosition = function(g, u) return { x = g.x0 + u * 100, y = 0, z = 0 } end } },
  },
  type = { ComponentType = { GAME_SCRIPT = "GS", TRANSPORT_VEHICLE = "TV", LINE = "LINE", TRANSPORT_NETWORK = "TN", BASE_EDGE = "BE" },
    Vec4f = { new = function(...) return { ... } end }, Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
    NodeViewerData = { new = function() return {} end } },
  gui = { spawnEphemeralHudImage = function() spawned = spawned + 1 end, byId = { setVisible = function() end },
    genericRep = { find = function() return 1 end, get = function() return { data = { default = {} } } end },
    SelectionDetails = { Type = { TransportNetworkEdge = "TNE" } } },
  cmd = { makeScriptingSendEventCmd = function(_, id, name, p) return { id = id, p = p } end, sendCommand = function(c) sent[#sent + 1] = c end },
}
local env = setmetatable({ ug_require = function(p) return assert(modules[p], p) end, print = function() end }, { __index = _G })
assert(load(io.open(arg[1]):read("*a"), "gui", "t", env))()
local exports = env.data()
-- render the train-window card and every nested recipe
local tree = exports.RunAroundHelperVehiclePlugin({ entityId = 42, gameCtx = {}, setCollapsibleExpanded = function() end, getCollapsibleExpanded = function() return false end })
local function count(n, k) k = k or {} if type(n) ~= "table" then return k end if n.kind then k[n.kind] = (k[n.kind] or 0) + 1 end for _, v in pairs(n) do if type(v) == "table" then count(v, k) end end return k end
local kinds = count(tree)
print("train window:", kinds.ContentCard, "cards,", kinds.Button, "buttons,", kinds.ProgressBar or 0, "progress bar")
-- the options: not the content card's collapsible part (its arrow overflows
-- the window's scroll area unclipped), but a button in the layout tree that
-- shows and hides them; which card is open is the window's state
local function findCard(n) if type(n)~="table" then return nil end if n.kind=="ContentCard" then return n end for _,v in pairs(n) do local r=findCard(v) if r then return r end end end
local function findButton(n, text) if type(n) ~= "table" then return nil end
  if n.kind == "Button" then local s = tostring(n.p.content and n.p.content.p and n.p.content.p.children and n.p.content.p.children[2] and n.p.content.p.children[2].p.text) if s == text then return n end end
  for _, v in pairs(n) do local r = findButton(v, text) if r then return r end end end
do
  local card = findCard(tree).p
  assert(card.recipeAndParamCollapsible == nil and card.setCollapsibleExpanded == nil and card.collapsibleExpanded == nil
    and card.initialCalloutTextCollapsible == nil, "the card has no collapsible part, so no arrow")
  assert(#card.extraChildrenPermanent == 2, "summary and options are the card's permanent content")
  assert((kinds.Slider or 0) == 0, "options hidden to start with")
  local open = {}
  local function win() return exports.RunAroundHelperVehiclePlugin({ entityId = 42, gameCtx = {},
    setCollapsibleExpanded = function(k, v) open = { [k] = v } end, getCollapsibleExpanded = function(k) return open[k] == true end }) end
  local b = findButton(findCard(win()).p.extraChildrenPermanent, "Options"); assert(b, "Options button inside the card")
  b.p.onClick(); assert(open.runaround_settings_7 == true, "opens through the window's state")
  local sk = count(findCard(win()).p.extraChildrenPermanent)
  print("options:", sk.Slider, "sliders,", sk.Button, "buttons"); assert(sk.Slider == 2, "options shown inside the card")
  local h = findButton(win(), "Hide options"); assert(h, "Hide options"); h.p.onClick()
  assert(open.runaround_settings_7 == false and not count(win()).Slider, "hidden again")
  -- a window that gives no state: the options keep their own
  assert(findButton(exports.RunAroundHelperVehiclePlugin({ entityId = 42, gameCtx = {} }), "Options"), "Options without window state")
end
-- press "Draw the route": find the button and click it
local edit = findButton(tree, "Draw the route"); assert(edit, "edit button"); edit.p.onClick()
assert(toolStack.active == "RunAroundRoute:edit:7", toolStack.active)
-- render the tool action: NodeViewer + Selector
local desc = actionFn()
for i = 1, 60 do lastStep() end
local dk = count(desc)
print("route tool:", dk.NodeViewer, "node viewer,", dk.Selector, "selector; markers spawned:", spawned); assert(spawned == 0, "no blinking markers")
local cfg = desc.p.children[1].p.nodeConfig
local n5, n6 = #cfg[5], #cfg[6]
print("drawn pieces: entity5", n5, "entity6", n6)
-- a click on track adds a point
desc.p.children[2].p.onSelect(77, {}, { data = { kind = "TNE", snap = { edgeId = { entity = 77, index = 2 } } } })
assert(sent[#sent].id == "AddLoopEdgeFromWorldClick" and sent[#sent].p.index == 2)
-- Show turns into Hide and back
local function render() return exports.RunAroundHelperVehiclePlugin({ entityId = 42, gameCtx = {} }) end
toolStack.active = nil
local t1 = render(); local show = findButton(t1, "Show the route"); assert(show, "show"); show.p.onClick()
assert(findButton(render(), "Hide the route"), "becomes Hide")
findButton(render(), "Hide the route").p.onClick(); assert(findButton(render(), "Show the route"), "back to Show")
-- default loop name shows the station
loops[1].name = "Loop 1"
local function findText(n, t) if type(n) ~= "table" then return false end if n.kind == "TextView" and n.p.text == t then return true end for _, v in pairs(n) do if findText(v, t) then return true end end return false end
local function findCardTitle(n) if type(n)~="table" then return nil end if n.kind=="ContentCard" then return n.p.title end for _,v in pairs(n) do local r=findCardTitle(v) if r then return r end end end
assert(findCardTitle(render()) == "Run-around at Name55", tostring(findCardTitle(render())))
-- leaving the route tool with Esc resets the button
local t3 = render(); findButton(t3, "Draw the route").p.onClick()
assert(findButton(render(), "Done drawing"), "Done while editing")
actionFn().p.onBack()
assert(findButton(render(), "Draw the route"), "Esc resets Done back to Edit")
-- no-loop case: the set-up card
loops[1].stopIndex = 3
local tree2 = exports.RunAroundHelperVehiclePlugin({ entityId = 42, gameCtx = {} })
local add = findButton(tree2, "Name55  (this train's stop)"); assert(add, "add-at-this-stop button")
add.p.onClick(); assert(sent[#sent].id == "AddLoopAtStop" and sent[#sent].p.name == "Name55" and sent[#sent].p.stopIndex == 0)
loops[1].stopIndex = 0
-- run status: the ghost rake's stages before the loco sets off, and a stuck recouple
assert(findText(render(), "Running around"), "running around")
runs[1].rake = { stage = "pull" }
assert(findText(render(), "Drawing forward"), "drawing forward")
runs[1].rake.stage = "uncouple"
assert(findText(render(), "Uncoupling"), "uncoupling")
runs[1].phase = "depart"
assert(findText(render(), "Coupled on. Ready to leave"), "waiting to leave")
runs[1].depart = { stage = "creep" }
assert(findText(render(), "Leaving"), "leaving")
runs[1].depart = nil
runs[1].rake, runs[1].phase = nil, "stuck"
assert(findText(render(), "Stuck: the loco could not be coupled back on. The train is held while it keeps trying."), "stuck")
runs[1].phase = nil
-- why the last arrival didn't run around
loops[1].lastProblem = "The train stopped at a different platform from the one this route starts at."
assert(findText(render(), "Last time, the loco didn't run around. The train stopped at a different platform from the one this route starts at."), "last problem shown")
loops[1].lastProblem = nil
-- the route in a sentence: ready with its length and time; a warning; a hint when there is none
loops[1].routeDrive, loops[1].routeReversals = 280, 2
assert(findText(render(), "Ready. The loco's way round is 280 m, about 55 s."), "ready line")
loops[1].routeWarning = "This route brings the loco back to the same end of the train it left from, so it doesn't run around."
assert(findText(render(), loops[1].routeWarning), "warning shown")
loops[1].routeWarning = nil
local keepLen = loops[1].routeLength
loops[1].routeLength, loops[1].routeHint = nil, "Couldn't find a way round automatically."
assert(findText(render(), "Couldn't find a way round automatically."), "hint shown")
loops[1].routeLength, loops[1].routeHint = keepLen, nil
-- "Find the route for me": offered when there is no route (or a wrong one), and sends the command
assert(not findButton(render(), "Find the route for me"), "not offered for a good route")
loops[1].routeLength = nil
local find = findButton(render(), "Find the route for me"); assert(find, "offered with no route")
find.p.onClick(); assert(sent[#sent].id == "AutoRoute" and sent[#sent].p.loopId == 7)
assert(not findButton(render(), "Show the route"), "nothing to show yet")
loops[1].routeLength = keepLen
-- mod button panel
assert(exports.RunAroundHelperButton == nil)
print("gui ok")
