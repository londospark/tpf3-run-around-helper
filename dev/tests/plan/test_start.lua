math.atan2 = math.atan2 or math.atan
-- A 1-D train on the x axis with the rules seen live: a replace keeps the middle, a flip mirrors about it.
local names = {}
local MODEL_LEN = { [4225] = 12.8, [7] = 23.4, [8] = 20.0 }
local function lenOf(mid) return MODEL_LEN[mid] end
local train = { mid = 0.0, dir = -1, parts = {} } -- dir: head points to -x
-- the route's first piece: along the platform from under the coaches, out past the loco (-x)
TRACK = { x0 = -20, dx = -100 }
local function layout()
  local L = 0 for _, p in ipairs(train.parts) do L = L + lenOf(p.part.modelId) end
  local out, cur = {}, train.mid + train.dir * L / 2 -- head end
  for i, p in ipairs(train.parts) do local l = lenOf(p.part.modelId); out[i] = { x = cur - train.dir * l / 2, m = p.part.modelId }; cur = cur - train.dir * l end
  return out
end
local function setParts(parts) train.parts = parts end
api = {
  res = { modelRep = { getAll = function() return names end,
    get = function() return { metadata = { transportVehicle = { compartments = { { loadConfigs = { {} } } } } } } end } },
  engine = { getComponent = function(e, c)
      if c == "CL" then local l = layout(); local cs = {} for i = 1, #l do cs[i] = i end; return { carriages = cs } end
      if c == "MIL" then local p = layout()[e]; return { fatInstances = { { modelId = p.m, transf = { cols = function(_, k) if k == 3 then return { x = p.x, y = 0, z = 0 } end return { x = 1, y = 0 } end } } } } end
      if c == "GT" then return { gameTime = 0 } end
      if c == "TN" then return { edges = { { geometry = TRACK } } } end end,
    util = { getWorld = function() return 1 end,
      transport = { calcPosition = function(g, u) return { x = g.x0 + u * g.dx, y = g.y0 or 0, z = 0 } end } } },
  type = { ComponentType = { CARRIAGE_LIST = "CL", MODEL_INSTANCE_LIST = "MIL", GAME_TIME = "GT", TRANSPORT_NETWORK = "TN" },
    TransportVehicleConfig = { new = function(t) local c = { vehicles = {} } for i, p in ipairs(t.vehicles) do c.vehicles[i] = p end return c end },
    TransportVehiclePart = { new = function() return { part = {} } end }, LoadConfig = { new = function() return {} end },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end,
      distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end }, Mat4f = { rotZTransl = function() return {} end } },
  cmd = { sendCommand = function() end, makeCustomEntityUpdateStateCmd = function() return {} end, makeCustomEntityUpdateTransformationCmd = function() return {} end },
}
-- Drives startRunAround through the ghost-rake path with the mock above.
-- markers: vehicles wrapped as their own ghost; hide: vehicles that can be hidden
-- (transformator wrapped or chained; defaults to the same).
local function run(markers, hide)
  for k in pairs(names) do if string.find(names[k], "runaround_ghost_real/", 1, true) or string.find(names[k], "runaround_ghost_hide/", 1, true) then names[k] = nil end end
  names[4225] = "vehicle/train/loco.mdl"; names[7] = "vehicle/waggon/coach.mdl"; names[8] = "vehicle/waggon/boxcar.mdl"
  local mid = 9000
  for _, f in ipairs(markers) do names[mid] = "m::/res/models/runaround_ghost_real/" .. f .. ".mdl"; mid = mid + 1 end
  for _, f in ipairs(hide or markers) do names[mid] = "m::/res/models/runaround_ghost_hide/" .. f .. ".mdl"; mid = mid + 1 end
  local pt = 0
  local function part(m) pt = pt + 1; return { part = { modelId = m, reversed = false, compartment2loadConfig = { {} }, color = { x = 0.1 * pt, y = 0.2, z = 0.3 } }, autoLoadConfig = { false }, purchaseTime = 1000 + pt } end
  train.mid, train.dir = 0.0, -1
  setParts({ part(4225), part(7), part(8), part(7) })
  local log, created, order = {}, {}, {}
  local nextEnt = 100
  local gc = api.engine.getComponent
  api.engine.getComponent = function(e, c)
    if c == "TV" then return { transportVehicleConfig = { vehicles = train.parts } } end
    return gc(e, c)
  end
  api.type.ComponentType.TRANSPORT_VEHICLE = "TV"
  api.type.Mat4f.rotZTransl = function() return {} end
  api.cmd.makeVehicleReplaceCmd = function(_, cfg) return { kind = "replace", cfg = cfg } end
  api.cmd.makeCustomEntityCreateCmd = function(m) return { kind = "create", model = m } end
  api.cmd.makeCustomEntityDestroyCmd = function(e) return { kind = "destroy", e = e } end
  api.cmd.makeVehicleSetManualDepartureCmd = function() return { kind = "hold" } end
  api.cmd.makeVehicleSetStoppedByUserCmd = function() return { kind = "hold" } end
  api.cmd.sendCommand = function(cmd, cb)
    if type(cmd) == "table" and cmd.kind then order[#order + 1] = cmd.kind end
    if type(cmd) == "table" and cmd.kind == "create" then created[#created + 1] = cmd.model; nextEnt = nextEnt + 1; if cb then cb({ resultEntity = nextEnt }, true) end return end
    if type(cmd) == "table" and cmd.kind == "replace" then setParts(cmd.cfg.vehicles) end
    if cb then cb({}, true) end
  end
  local saved = { runs = {}, loops = {} }
  local state = { get = function() return saved end, set = function(_, d) saved = d end }
  local op = print
  print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end log[#log + 1] = table.concat(t, " ") end
  M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {start=startRunAround}", "s"))() -- fresh: the marker set is cached
  local ok, err = pcall(M.start, state, 1, { id = 1, loopEdges = { { entity = 1, index = 0, forward = true } }, waypoints = {}, name = "Test" })
  print = op
  if not ok then print(table.concat(log, "\n")); error(err) end
  return saved, created, order, log
end
api.res.modelRep.get = function(m)
  local L = MODEL_LEN[m]
  return { metadata = { transportVehicle = { compartments = { { loadConfigs = { {} } } } },
    landVehicle = { engines = (m == 4225) and { { power = 700 } } or {} },
    extent = L and { bbMin = { x = -L / 2 }, bbMax = { x = L / 2 } } or nil } }
end
M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {start=startRunAround}", "s"))()

-- every vehicle wrapped: a ghost rake, a ghost per coach from the coach's own model, the replace after them
local saved, created, order, lg = run({ "loco", "coach", "boxcar" })
local r = saved.runs[1]
assert(r ~= nil, "run started")
assert(r.rake ~= nil, "ghost rake")
assert(#r.rake.coaches == 3)
assert(created[1] == 7 and created[2] == 8 and created[3] == 7 and created[4] == 4225, "coach ghosts (own models) then the loco: " .. table.concat(created, ","))
local firstReplace
for i, k in ipairs(order) do if k == "replace" then firstReplace = i break end end
local creates = 0 for i = 1, firstReplace do if order[i] == "create" then creates = creates + 1 end end
assert(creates == 3, "all coach ghosts shown before the replace")
local hidden = 0
for _, p in ipairs(train.parts) do if p.part.color and math.abs(p.part.color.x - 0.1234567) < 1e-6 then hidden = hidden + 1 end end
assert(#train.parts == 4 and hidden == 4, "the loco and three coaches are still in the train, hidden")
assert(train.parts[1].part.modelId == 4225, "the real loco stays first (nothing swapped in)")
print("start (all wrapped): ghost rake, loco and coaches hidden in the train, ghosts from their own models")

-- a coach whose model was not wrapped: no rake (it could not be hidden) - the
-- simple sequence, the loco still hidden in place, the coaches in view
saved = run({ "loco", "coach" })
r = saved.runs[1]
assert(r ~= nil and r.rake == nil, "the simple sequence")
hidden = 0
for _, p in ipairs(train.parts) do if p.part.color and math.abs(p.part.color.x - 0.1234567) < 1e-6 then hidden = hidden + 1 end end
assert(#train.parts == 4 and hidden == 1 and train.parts[1].part.modelId == 4225, "only the loco hidden, in place")
print("start (a wagon not wrapped): simple sequence, loco hidden in place")

-- a loco that can't be hidden: no run-around (taking it off would sell it)
saved, created, order = run({ "coach", "boxcar" }, { "coach", "boxcar" })
assert(#saved.runs == 0 and #created == 0, "not started")
print("start (loco can't be hidden): no run-around")
print("start ok")
