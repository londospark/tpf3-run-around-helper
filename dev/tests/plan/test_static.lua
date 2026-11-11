math.atan2 = math.atan2 or math.atan
-- Static coaches: the coach copies never move. The loco copy uncouples where the
-- train stopped, runs around and couples on; then the HIDDEN real train (which
-- the game put a loco length nearer the buffers when it was turned) is let go,
-- leaves when its line says, creeps up under its copies, is stopped there,
-- shown again and sent on its way.
--
-- The mock train is the 1-D one of test_failures.lua (a replace keeps the
-- middle, a flip mirrors about it) and can also DRIVE: once neither held nor
-- stopped it waits `dwell` seconds (loading), then accelerates in its head's
-- direction up to its top speed times its speed scale, and brakes when
-- stopped by the user or when the scale drops below its speed.
local names = {}
names[4225] = "vehicle/train/loco.mdl"; names[7] = "vehicle/waggon/coach.mdl"; names[8] = "vehicle/waggon/boxcar.mdl"
names[9000] = "m::/res/models/runaround_ghost_real/loco.mdl"
names[9001] = "m::/res/models/runaround_ghost_real/coach.mdl"
names[9002] = "m::/res/models/runaround_ghost_real/boxcar.mdl"
names[9010] = "m::/res/models/runaround_ghost_hide/loco.mdl"
names[9011] = "m::/res/models/runaround_ghost_hide/coach.mdl"
names[9012] = "m::/res/models/runaround_ghost_hide/boxcar.mdl"
local MODEL_LEN = { [4225] = 12.8, [7] = 23.4, [8] = 20.0 }
local TOP, BRAKE, ACCEL = 30.0, 1.0, 0.6
local function lenOf(mid) return MODEL_LEN[mid] end
local train
TRACK = { x0 = -20, dx = -100 }
local function layout()
  local L = 0 for _, p in ipairs(train.parts) do L = L + lenOf(p.part.modelId) end
  local out, cur = {}, train.mid + train.dir * L / 2
  for i, p in ipairs(train.parts) do local l = lenOf(p.part.modelId); out[i] = { x = cur - train.dir * l / 2, m = p.part.modelId }; cur = cur - train.dir * l end
  return out
end

local opt -- what this mock game can do; tests switch these
local sent, live, moves = {}, {}, {}
local nextEnt = 100

-- the train drives itself
local function physics(dt)
  if train.gone then return end
  local free = not train.manual and not train.stopped
  if free and not train.left then
    train.waited = train.waited + dt
    if train.waited >= opt.dwell then train.left = true end
  end
  local cap = TOP * (opt.capWorks and train.scale or 1.0)
  if train.stopped or not train.left then
    train.v = math.max(train.v - BRAKE * dt, 0)
  elseif train.v > cap then
    train.v = math.max(train.v - BRAKE * dt, cap)
  else
    train.v = math.min(train.v + ACCEL * dt, cap)
  end
  train.mid = train.mid + (opt.wrongWay and -1 or 1) * train.dir * train.v * dt
  train.maxV = math.max(train.maxV, train.v)
end

api = {
  res = { modelRep = { getAll = function() return names end,
    get = function(m)
      local L = MODEL_LEN[m]
      return { metadata = { transportVehicle = { compartments = { { loadConfigs = { {} } } } },
        landVehicle = { engines = (m == 4225) and { { power = 700 } } or {}, topSpeed = L and TOP or nil, brakeDeceleration = L and BRAKE or nil },
        extent = L and { bbMin = { x = -L / 2 }, bbMax = { x = L / 2 } } or nil } }
    end } },
  engine = { getComponent = function(e, c)
      if c == "TV" then if train.gone then return nil end return { transportVehicleConfig = { vehicles = train.parts }, modifiers = { topSpeedScale = train.scale, noiseScale = 7 } } end
      if c == "CL" then local l = layout(); local cs = {} for i = 1, #l do cs[i] = i end; return { carriages = cs } end
      if c == "MIL" then local p = layout()[e]; return { fatInstances = { { modelId = p.m, transf = { cols = function(_, k) if k == 3 then return { x = p.x, y = 0, z = 0 } end return { x = 1, y = 0 } end } } } } end
      if c == "GT" then return { gameTime = 0 } end
      if c == "MP" then if not opt.movePath then return nil end return { dyn = { speed = train.v } } end
      if c == "TN" then return { edges = { { geometry = TRACK } } } end end,
    util = { getWorld = function() return 1 end, transport = { calcPosition = function(g, u) return { x = g.x0 + u * g.dx, y = g.y0 or 0, z = 0 } end } } },
  type = { ComponentType = { CARRIAGE_LIST = "CL", MODEL_INSTANCE_LIST = "MIL", GAME_TIME = "GT", TRANSPORT_VEHICLE = "TV", TRANSPORT_NETWORK = "TN", MOVE_PATH = "MP" },
    TransportVehicleConfig = { new = function(t) local c = { vehicles = {} } for i, p in ipairs(t.vehicles) do c.vehicles[i] = p end return c end },
    TransportVehiclePart = { new = function() return { part = {} } end }, LoadConfig = { new = function() return {} end },
    TransportVehicle = { Modifiers = { new = function(m) local c = {} for k, v in pairs(m or {}) do c[k] = v end return c end } },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end,
      distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end },
    Mat4f = { rotZTransl = function(yaw, v) return { yaw = yaw, x = v.x, y = v.y } end } },
  cmd = {
    makeVehicleReplaceCmd = function(_, cfg) return { kind = "replace", cfg = cfg } end,
    makeVehicleReverseCmd = function() return { kind = "reverse" } end,
    makeCustomEntityCreateCmd = function(m) return { kind = "create", model = m } end,
    makeCustomEntityDestroyCmd = function(e) return { kind = "destroy", e = e } end,
    makeCustomEntityUpdateStateCmd = function() return { kind = "state" } end,
    makeCustomEntityUpdateTransformationCmd = function(e, t) return { kind = "move", e = e, t = t } end,
    makeVehicleSetManualDepartureCmd = function(_, on) return { kind = "manual", on = on } end,
    makeVehicleSetStoppedByUserCmd = function(_, on) return { kind = "stopped", on = on } end,
    makeVehicleSetModifiersCmd = function(_, m) if not opt.modifiers then error("no such command") end return { kind = "mod", m = m } end,
    makeVehicleTryToDepartCmd = function() return { kind = "depart" } end,
    sendCommand = function(cmd, cb)
      sent[#sent + 1] = cmd
      if cmd.kind == "create" then
        nextEnt = nextEnt + 1; live[nextEnt] = cmd.model
        if cb then cb({ resultEntity = nextEnt }, true) end
        return
      end
      if cmd.kind == "destroy" then assert(live[cmd.e] ~= nil, "destroyed an entity that is not there"); live[cmd.e] = nil end
      if cmd.kind == "move" and type(cmd.t) == "table" and cmd.t.x then
        moves[cmd.e] = moves[cmd.e] or {}
        table.insert(moves[cmd.e], { x = cmd.t.x, t = train.clock })
      end
      if cmd.kind == "manual" then train.manual = cmd.on end
      if cmd.kind == "stopped" then train.stopped = cmd.on end
      if cmd.kind == "mod" then
        assert(cmd.m.noiseScale == 7, "the train's other modifiers are kept")
        train.scale = cmd.m.topSpeedScale
      end
      if cmd.kind == "replace" then
        assert(train.v == 0, "a replace only while the train stands")
        train.parts = cmd.cfg.vehicles
      end
      if cmd.kind == "reverse" then train.dir = -train.dir end
      if cb then cb({}, true) end
    end },
}

local M, script
local saved
local state = { get = function() return saved end, set = function(_, d) saved = d end, subscribeToEvent = function() end }
local log = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end log[#log + 1] = table.concat(t, " ") end
local say = io.write
local loop = { id = 1, name = "Test", lineEntity = 7, stopIndex = 0, speed = 10, accel = 2, routeLength = 100,
  loopEdges = { { entity = 1, index = 0, forward = true } }, waypoints = {} }

local ORIGINAL, START
local function fresh(o)
  opt = { dwell = 5, capWorks = true, modifiers = true, movePath = true }
  for k, v in pairs(o or {}) do opt[k] = v end
  local pt = 0
  local function part(m, rev) pt = pt + 1; return { part = { modelId = m, reversed = rev, compartment2loadConfig = { {} }, color = { x = 0.1 * pt, y = 0.2, z = 0.3 } }, autoLoadConfig = { false }, purchaseTime = 1000 + pt } end
  train = { mid = 0.0, dir = -1, gone = false, v = 0, maxV = 0, scale = 1.0, manual = false, stopped = false, left = false, waited = 0, clock = 0,
    parts = { part(4225, false), part(7, false), part(8, true), part(7, false) } }
  ORIGINAL = { train.parts[1], train.parts[2], train.parts[3], train.parts[4] }
  START = layout()
  sent, live, moves, log = {}, {}, {}, {}
  saved = { runs = {}, loops = { loop }, pending = {} }
  M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {start=startRunAround, CONFIG=CONFIG, data=data}", "s"))()
  M.CONFIG.LOG_TRACES = false
  assert(M.CONFIG.staticCoaches == true, "static coaches are the default")
  script = M.data()
  local ok, err = pcall(M.start, state, 1, loop)
  if not ok then for _, l in ipairs(log) do say(l, "\n") end error(err) end
end
local function tick(dt)
  train.clock = train.clock + dt
  physics(dt)
  local res = script.update(nil, state, dt)
  script.postUpdate(nil, state, dt, res)
end
local function liveCount() local n = 0 for _ in pairs(live) do n = n + 1 end return n end
local function logged(text) for _, l in ipairs(log) do if l:find(text, 1, true) then return l end end end
local function dump() for _, l in ipairs(log) do say("    ", l, "\n") end end
-- runs until the run is over; returns the phases it went through
local function runOut(dt, limit)
  local phases, last, t = {}, nil, 0
  while #saved.runs > 0 and t < limit do
    tick(dt); t = t + dt
    local r = saved.runs[1]
    local ph = r and ((r.phase or "route") .. ((r.phase == "depart" and r.depart) and (":" .. r.depart.stage) or "")) or "over"
    if ph ~= last then phases[#phases + 1] = ph; last = ph end
  end
  return phases, t
end
-- the copies: entity -> where it was put (the last move), and every coach
-- copy's moves after it first appeared
local function coachCopies(run) local out = {} for i, c in ipairs(run.rake.coaches) do out[i] = c end return out end

-- 1. The whole run. --------------------------------------------------------
fresh()
local run = saved.runs[1]
assert(run and run.rake and run.rake.static, "a static-coaches run")
local copies = coachCopies(run)
local ghostOf = {}
for i, c in ipairs(copies) do ghostOf[i] = c.ghost; assert(math.abs(c.start.x - START[i + 1].x) < 1e-9, "copy " .. i .. " appears on its coach") end
local phases, took = runOut(0.1, 600)
if #saved.runs ~= 0 then dump() error("the run did not finish: " .. table.concat(phases, " > ")) end
say("phases: ", table.concat(phases, " > "), "\n")
local want = "depart:await > depart:creep > depart:stopping"
assert(table.concat(phases, " > "):find(want, 1, true), "let go, crept and stopped")
-- the coach copies were never moved until the real train stood under them, and then by centimetres at most
for i, e in ipairs(ghostOf) do
  local first = moves[e][1]
  assert(math.abs(first.x - START[i + 1].x) < 1e-9, "copy " .. i .. " placed on its coach")
  for k = 2, #moves[e] do
    assert(math.abs(moves[e][k].x - first.x) < 0.2, string.format("copy %d moved %.2f m: the coaches must stay", i, moves[e][k].x - first.x))
  end
end
-- the real train stands exactly where its copies stood: every coach back at
-- its arrival place, the loco at the far end
local final = layout()
local worst = 0
for i = 2, 4 do
  -- after the run the coaches are, from the head, last ... first
  local f = final[#final - i + 2]
  worst = math.max(worst, math.abs(f.x - START[i].x))
end
say(string.format("coaches: the real train stands %.3f m from where it arrived (it moved up %.1f m, hidden, at up to %.2f m/s)\n", worst, MODEL_LEN[4225], train.maxV))
assert(worst < 0.15, "the coaches are where they arrived")
assert(final[1].x > START[4].x, "the loco is at the far end")
assert(math.abs(math.abs(final[1].x - final[2].x) - (12.8 + 23.4) / 2) < 1e-6, "coupled to the last coach")
-- shown again only while standing; top speed back; released and not sent off twice
assert(train.scale == 1.0, "top speed scale back to 1, got " .. tostring(train.scale))
assert(train.stopped == false and train.manual == false, "un-stopped and on its way")
assert(train.maxV <= 2.5 + 1e-6, "it crept: " .. train.maxV)
assert(liveCount() == 0, "every copy gone")
local hidden = 0
for i, p in ipairs(train.parts) do
  if math.abs(p.part.color.x - 0.1234567) < 1e-6 then hidden = hidden + 1 end
  local found = false
  for _, o in ipairs(ORIGINAL) do if o == p then found = true end end
  assert(found, "the same parts: nothing bought or sold")
end
assert(hidden == 0, "nothing left hidden")
assert(logged("moves up 12.8 m"), "says how far")
local departs = 0
for _, c in ipairs(sent) do if c.kind == "depart" then departs = departs + 1 end end
assert(departs == 1, "sent on its way once (at the release), not again from where it was stopped: " .. departs)
-- the train carries on from there
for _ = 1, 50 do tick(0.1) end
assert(train.v > 1.0 and train.mid > 12.8, "it drives on")
say("whole run: coaches never moved, real train shown under them, speed restored, drives on\n")

-- 2. A long wait for departure (wait for full load) is not a stall. ---------------
fresh({ dwell = 400 })
local ph2, t2 = runOut(0.5, 900)
if #saved.runs ~= 0 then dump() error("did not finish after a long dwell: " .. table.concat(ph2, " > ")) end
assert(t2 > 400, "it waited for the train")
assert(not logged("watchdog"), "no watchdog during the wait")
assert(train.scale == 1.0 and not train.stopped, "restored")
say(string.format("long dwell: waited %.0f s for the departure, no watchdog\n", t2))

-- 3. Coarse ticks, and no MOVE_PATH to read the speed from. ----------------------
fresh({ movePath = false })
local ph3 = runOut(0.2, 600)
if #saved.runs ~= 0 then dump() error("did not finish: " .. table.concat(ph3, " > ")) end
final = layout()
worst = 0
for i = 2, 4 do worst = math.max(worst, math.abs(final[#final - i + 2].x - START[i].x)) end
assert(worst < 0.15, string.format("coarse ticks: %.3f m off", worst))
say(string.format("0.2 s ticks, speed from positions: %.3f m off\n", worst))

-- 4. The game will not limit the speed: stopped as near as can be, then the
--    copies ease onto the real train, and it still ends cleanly. ----------------
for _, o in ipairs({ { modifiers = false }, { capWorks = false } }) do
  fresh(o)
  local ph4 = runOut(0.1, 600)
  if #saved.runs ~= 0 then dump() error("did not finish: " .. table.concat(ph4, " > ")) end
  assert(liveCount() == 0 and train.stopped == false and train.scale == 1.0, "ends cleanly")
  local hid = 0
  for _, p in ipairs(train.parts) do if math.abs(p.part.color.x - 0.1234567) < 1e-6 then hid = hid + 1 end end
  assert(hid == 0, "shown again")
  local line = logged("moving up: the hidden train stands")
  say("no speed limit (", o.modifiers == false and "command refused" or "scale ignored", "): ", line and line:gsub("^%[RunAroundHelper%] ", "") or "?", "\n")
end

-- 5. The train is sold while it waits to leave: the copies go. ----------------------
fresh({ dwell = 1000 })
for _ = 1, 800 do tick(0.1) if saved.runs[1] and saved.runs[1].phase == "depart" then break end end
assert(saved.runs[1] and saved.runs[1].phase == "depart", "(setup) waiting to leave")
train.gone = true
for _ = 1, 5 do tick(0.1) end
assert(#saved.runs == 0 and liveCount() == 0, "run over, copies cleared")
say("sold while waiting to leave: copies cleared\n")

-- 6. The watchdog still catches a stall BEFORE the departure (the flip never
--    comes back), and gives the train its speed back if it was limited. ---------
fresh()
saved.runs[1].speedScale0 = 0.5 -- as if limited
train.scale = 0.01
saved.runs[1].phase = "finish"; saved.runs[1].aborted = true
for _ = 1, 20 do tick(0.1) end
assert(#saved.runs == 0 and train.scale == 0.5, "an aborted run restores the speed scale: " .. tostring(train.scale))
say("aborted run: speed scale restored\n")
-- 7. The hidden train sets off the WRONG way: it is stopped within metres, never
--    left to drive away unseen, and the copies go to it. ---------------------------
fresh({ wrongWay = true })
local ph7 = runOut(0.1, 600)
if #saved.runs ~= 0 then dump() error("did not finish: " .. table.concat(ph7, " > ")) end
assert(logged("further than its copies"), "noticed")
assert(math.abs(train.mid) < 25, string.format("stopped near the station, not %.0f m away", train.mid))
assert(liveCount() == 0 and train.scale == 1.0 and not train.stopped, "ends cleanly")
local hid7 = 0
for _, p in ipairs(train.parts) do if math.abs(p.part.color.x - 0.1234567) < 1e-6 then hid7 = hid7 + 1 end end
assert(hid7 == 0, "shown again")
say(string.format("wrong way: stopped %.1f m from the stop, shown again there\n", math.abs(train.mid)))
print = nil
say("static ok\n")
