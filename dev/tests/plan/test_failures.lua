math.atan2 = math.atan2 or math.atan
-- Failure handling (CODE_REVIEW.md H1-H4) on the ghost-rake path: every way a run
-- can fail ends with the real train back as it was (or the ghosts cleared, if the
-- train has gone), and never with a train released on the invisible stand-in.
-- Same 1-D train as test_start.lua: a replace keeps the middle, a flip mirrors.
local STAND = {}
local names = {}
local id = 5000
for cm = 25, 4400, 25 do names[id] = "m::/res/models/runaround_standin/standin_cm" .. cm .. ".mdl"; STAND[id] = cm / 100; id = id + 1 end
names[4225] = "vehicle/train/loco.mdl"; names[7] = "vehicle/waggon/coach.mdl"; names[8] = "vehicle/waggon/boxcar.mdl"
names[9000] = "m::/res/models/runaround_ghost_real/loco.mdl"
names[9001] = "m::/res/models/runaround_ghost_real/coach.mdl"
names[9002] = "m::/res/models/runaround_ghost_real/boxcar.mdl"
local MODEL_LEN = { [4225] = 12.8, [7] = 23.4, [8] = 20.0 }
local HIDE = 0.1234567
local function lenOf(mid) return STAND[mid] or MODEL_LEN[mid] end
local train = { mid = 0.0, dir = -1, parts = {}, gone = false }
-- the route's first piece: along the platform from under the coaches, out past the loco (the head is at -x)
TRACK = { x0 = -20, dx = -100 }
local function layout()
  local L = 0 for _, p in ipairs(train.parts) do L = L + lenOf(p.part.modelId) end
  local out, cur = {}, train.mid + train.dir * L / 2
  for i, p in ipairs(train.parts) do local l = lenOf(p.part.modelId); out[i] = { x = cur - train.dir * l / 2, m = p.part.modelId }; cur = cur - train.dir * l end
  return out
end

-- What the mock game does with each command; tests switch these.
local refuse = { replace = false, reverse = false, createModel = nil }
local stall = { reverse = false }
local sent, live = {}, {}  -- every command sent; free entities that exist now
local held = false
local nextEnt = 100

api = {
  res = { modelRep = { getAll = function() return names end,
    get = function(m)
      local L = MODEL_LEN[m]
      return { metadata = { transportVehicle = { compartments = { { loadConfigs = { {} } } } },
        extent = L and { bbMin = { x = -L / 2 }, bbMax = { x = L / 2 } } or nil } }
    end } },
  engine = { getComponent = function(e, c)
      if c == "TV" then if train.gone then return nil end return { transportVehicleConfig = { vehicles = train.parts } } end
      if c == "CL" then local l = layout(); local cs = {} for i = 1, #l do cs[i] = i end; return { carriages = cs } end
      if c == "MIL" then local p = layout()[e]; return { fatInstances = { { modelId = p.m, transf = { cols = function(_, k) if k == 3 then return { x = p.x, y = 0, z = 0 } end return { x = 1, y = 0 } end } } } } end
      if c == "GT" then return { gameTime = 0 } end
      if c == "TN" then return { edges = { { geometry = TRACK } } } end end,
    util = { getWorld = function() return 1 end, transport = { calcPosition = function(g, u) return { x = g.x0 + u * g.dx, y = g.y0 or 0, z = 0 } end } } },
  type = { ComponentType = { CARRIAGE_LIST = "CL", MODEL_INSTANCE_LIST = "MIL", GAME_TIME = "GT", TRANSPORT_VEHICLE = "TV", TRANSPORT_NETWORK = "TN" },
    TransportVehicleConfig = { new = function(t) local c = { vehicles = {} } for i, p in ipairs(t.vehicles) do c.vehicles[i] = p end return c end },
    TransportVehiclePart = { new = function() return { part = {} } end }, LoadConfig = { new = function() return {} end },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end,
      distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end }, Mat4f = { rotZTransl = function() return {} end } },
  cmd = {
    makeVehicleReplaceCmd = function(_, cfg) return { kind = "replace", cfg = cfg } end,
    makeVehicleReverseCmd = function() return { kind = "reverse" } end,
    makeCustomEntityCreateCmd = function(m) return { kind = "create", model = m } end,
    makeCustomEntityDestroyCmd = function(e) return { kind = "destroy", e = e } end,
    makeCustomEntityUpdateStateCmd = function() return { kind = "state" } end,
    makeCustomEntityUpdateTransformationCmd = function() return { kind = "move" } end,
    makeVehicleSetManualDepartureCmd = function(_, on) return { kind = "hold", on = on } end,
    makeVehicleSetStoppedByUserCmd = function(_, on) return { kind = "hold", on = on } end,
    makeVehicleTryToDepartCmd = function() return { kind = "depart" } end,
    sendCommand = function(cmd, cb)
      sent[#sent + 1] = cmd
      if cmd.kind == "create" then
        if refuse.createModel == cmd.model then if cb then cb({}, false) end return end
        nextEnt = nextEnt + 1; live[nextEnt] = cmd.model
        if cb then cb({ resultEntity = nextEnt }, true) end
        return
      end
      if cmd.kind == "destroy" then assert(live[cmd.e] ~= nil, "destroyed an entity that is not there: " .. tostring(cmd.e)); live[cmd.e] = nil end
      if cmd.kind == "hold" then held = cmd.on end
      if cmd.kind == "replace" then
        if refuse.replace then if cb then cb({}, false) end return end
        train.parts = cmd.cfg.vehicles
      end
      if cmd.kind == "reverse" then
        if stall.reverse then return end -- the callback never comes
        train.dir = -train.dir
      end
      if cb then cb({}, true) end
    end },
}

local M
local saved
local state = { get = function() return saved end, set = function(_, d) saved = d end, subscribeToEvent = function() end }
local log = {}
local function load_script()
  M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {start=startRunAround, finishRun=finishRun, CONFIG=CONFIG, data=data}", "s"))()
  M.CONFIG.LOG_TRACES = false
end
print = (function(op) return function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end log[#log + 1] = table.concat(t, " ") end end)(print)
local say = io.write

local loop = { id = 1, name = "Test", speed = 10, accel = 2, routeLength = 100,
  loopEdges = { { entity = 1, index = 0, forward = true } }, waypoints = {} }

-- The original train: loco, coach, boxcar (turned), coach; each with its own paint.
local function fresh()
  local pt = 0
  local function part(m, rev) pt = pt + 1; return { part = { modelId = m, reversed = rev, compartment2loadConfig = { {} }, color = { x = 0.1 * pt, y = 0.2, z = 0.3 } }, autoLoadConfig = { false }, purchaseTime = 1000 + pt } end
  train.mid, train.dir, train.gone = 0.0, -1, false
  TRACK.x0, TRACK.dx, TRACK.y0 = -20, -100, nil
  loop.lastProblem = nil
  train.parts = { part(4225, false), part(7, false), part(8, true), part(7, false) }
  refuse.replace, refuse.reverse, refuse.createModel, stall.reverse = false, false, nil, false
  sent, live, held, log = {}, {}, false, {}
  saved = { runs = {}, loops = { loop }, pending = {} }
  load_script()
end

local function liveCount() local n = 0 for _ in pairs(live) do n = n + 1 end return n end
local function sentKind(k) local n = 0 for _, c in ipairs(sent) do if c.kind == k then n = n + 1 end end return n end
local function lastHold() for i = #sent, 1, -1 do if sent[i].kind == "hold" then return sent[i].on end end end

-- The train is exactly as it was before the run: same parts in the same order,
-- facing and paint as they were, nothing hidden, the loco at the head.
local function assertTrainAsOriginal(what)
  local p = train.parts
  assert(#p == 4, what .. ": 4 parts, got " .. #p)
  local want = { { 4225, false, 1001 }, { 7, false, 1002 }, { 8, true, 1003 }, { 7, false, 1004 } }
  for i, w in ipairs(want) do
    assert(p[i].part.modelId == w[1], what .. ": part " .. i .. " model " .. tostring(p[i].part.modelId))
    assert(p[i].part.reversed == w[2], what .. ": part " .. i .. " reversed " .. tostring(p[i].part.reversed))
    assert(p[i].purchaseTime == w[3], what .. ": part " .. i .. " purchase time")
    assert(math.abs(p[i].part.color.x - 0.1 * i) < 1e-6, what .. ": part " .. i .. " paint " .. tostring(p[i].part.color.x))
  end
end

-- Runs the game script as the game does: update, then postUpdate, dt seconds a tick.
local script
local function tick(dt)
  local res = script.update(nil, state, dt)
  script.postUpdate(nil, state, dt, res)
end

local function start()
  script = M.data()
  local ok, err = pcall(M.start, state, 1, loop)
  if not ok then for _, l in ipairs(log) do say(l, "\n") end error(err) end
end

-- H1: the detach is refused after the coach ghosts are up: they all go again.
fresh()
refuse.replace = true
start()
assert(#saved.runs == 0, "H1: no run")
assert(sentKind("create") == 3, "H1: three coach ghosts were shown")
assert(liveCount() == 0, "H1: every coach ghost destroyed, " .. liveCount() .. " left")
assert(lastHold() == false, "H1: train released")
say("H1 detach refused: coach ghosts cleared, train released\n")

-- H1: the train is sold mid-run: the watchdog sees it, every ghost goes.
fresh()
start()
assert(#saved.runs == 1 and liveCount() == 4, "H1b: run started with 4 ghosts")
for _ = 1, 20 do tick(0.1) end
train.gone = true
for _ = 1, 3 do tick(0.1) end
assert(#saved.runs == 0, "H1b: run ended")
assert(liveCount() == 0, "H1b: every ghost destroyed, " .. liveCount() .. " left")
say("H1 train gone mid-run: loco and coach ghosts cleared\n")

-- H2: the loco ghost cannot be shown after the (ghost-rake) detach: the coaches
-- are hidden, turned and in reverse order then; they all come back as they were.
fresh()
refuse.createModel = 4225
start()
assert(#saved.runs == 1 and saved.runs[1].restore, "H2: a restore is queued")
local hidden = 0
for _, p in ipairs(train.parts) do if p.part.color and math.abs(p.part.color.x - HIDE) < 1e-6 then hidden = hidden + 1 end end
assert(hidden == 3, "H2: (setup) the coaches are hidden after the detach")
for _ = 1, 3 do tick(0.1) end
assertTrainAsOriginal("H2")
assert(liveCount() == 0, "H2: coach ghosts destroyed, " .. liveCount() .. " left")
assert(#saved.runs == 0, "H2: run over")
assert(lastHold() == false and sentKind("depart") == 1, "H2: released and sent on its way")
say("H2 loco ghost failed: coaches back in order, facing and paint; ghosts cleared\n")

-- H3: the recouple is refused: the train stays held with its ghosts up and it is
-- tried again; after recoupleRetries it is stuck (still held), and once the game
-- accepts the replace the run completes.
fresh()
refuse.createModel = 4225
start()
refuse.replace = true
local phases, last = {}, nil
for _ = 1, 400 do -- 40 s
  tick(0.1)
  local r = saved.runs[1]
  local ph = r and r.phase or "none"
  if ph ~= last then phases[#phases + 1] = ph; last = ph end
  assert(lastHold() ~= false, "H3: never released while the loco is off the train")
end
assert(saved.runs[1] and saved.runs[1].phase == "stuck", "H3: stuck, got " .. table.concat(phases, " > "))
assert(saved.runs[1].recoupleTries >= 4, "H3: kept trying while stuck: " .. tostring(saved.runs[1].recoupleTries))
assert(liveCount() == 3, "H3: coach ghosts still up over the hidden coaches")
refuse.replace = false
for _ = 1, 400 do tick(0.1) if #saved.runs == 0 then break end end
assert(#saved.runs == 0, "H3: run completed once the replace was accepted")
assertTrainAsOriginal("H3")
assert(liveCount() == 0 and lastHold() == false, "H3: ghosts cleared and train released")
say("H3 recouple refused: " .. table.concat(phases, " > ") .. ", held throughout, then recoupled\n")

-- H4: the hidden train's flip never reports back: the watchdog puts the real
-- train back after watchdogFactor x route / speed + watchdogExtraSeconds (90 s).
fresh()
stall.reverse = true
start()
local t = 0
while #saved.runs > 0 and t < 200 do tick(0.5); t = t + 0.5 end
assert(#saved.runs == 0, "H4: watchdog ended the run")
assert(t > 89 and t < 92, "H4: after the limit (90 s), took " .. t)
assertTrainAsOriginal("H4")
assert(liveCount() == 0, "H4: every ghost destroyed, " .. liveCount() .. " left")
assert(lastHold() == false, "H4: train released")
local sawLine = false
for _, l in ipairs(log) do if l:find("watchdog: the run-around for vehicle 1 has stalled", 1, true) then sawLine = true end end
assert(sawLine, "H4: watchdog log line")
say(string.format("H4 stalled flip: watchdog at %.1f s, train put back, ghosts cleared\n", t))

-- H4: the stall comes back late (after the watchdog): it must not hold the train again.
fresh()
stall.reverse = true
start()
local pending
local sc = api.cmd.sendCommand
api.cmd.sendCommand = function(cmd, cb) if cmd.kind == "reverse" then pending = cb return end return sc(cmd, cb) end
t = 0
while #saved.runs > 0 and t < 200 do tick(0.5); t = t + 0.5 end
assert(pending ~= nil and lastHold() == false, "H4b: (setup) released with the flip outstanding")
pending({}, true)
assert(lastHold() == false, "H4b: a late flip callback does not hold the released train")
api.cmd.sendCommand = sc
say("H4 late callback after the watchdog: train stays released\n")

-- A light engine (no coaches): nothing to run around, nothing sent.
fresh()
train.parts = { train.parts[1] }
start()
assert(#saved.runs == 0 and #sent == 0, "light engine: left alone")
say("light engine: left alone\n")

-- N1: the train is at another platform (the next track, 5 m away): nothing is
-- touched, the train leaves the normal way, and the card says why.
fresh()
TRACK.y0 = 5
start()
assert(#saved.runs == 0 and #sent == 0, "N1: not started, nothing sent")
assert(loop.lastProblem and loop.lastProblem:find("not at the platform the route starts from", 1, true), "N1: the card says why: " .. tostring(loop.lastProblem))
say("N1 other platform: " .. loop.lastProblem .. "\n")
-- ... but a loco a little off the track's centre line (2 m) is still on it.
fresh()
TRACK.y0 = 2
start()
assert(#saved.runs == 1, "N1: 2 m off the centre line still runs")
say("N1 2 m off the centre line: runs\n")

-- N2: the route sets off along the platform towards the coaches: not started.
fresh()
TRACK.x0, TRACK.dx = -60, 100 -- under the loco, but heading +x, into the train
start()
assert(#saved.runs == 0 and #sent == 0, "N2: not started, nothing sent")
assert(loop.lastProblem and loop.lastProblem:find("towards the coaches", 1, true), "N2: the card says why: " .. tostring(loop.lastProblem))
say("N2 route into the train: " .. loop.lastProblem .. "\n")
-- the next run that does start clears the note
TRACK.x0, TRACK.dx = -20, -100
sent, saved.runs = {}, {}
start()
assert(#saved.runs == 1 and loop.lastProblem == nil, "a started run clears the note")
say("N2 then a good start: note cleared\n")

say("failures ok\n")
