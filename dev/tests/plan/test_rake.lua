math.atan2 = math.atan2 or math.atan
-- A 1-D train on the x axis with the rules seen live: a replace keeps the middle, a flip mirrors about it.
local names = {}
local MODEL_LEN = { [4225] = 12.8, [7] = 23.4, [8] = 20.0 }
local function lenOf(mid) return MODEL_LEN[mid] end
local train = { mid = 0.0, dir = -1, parts = {} } -- dir: head points to -x
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
      if c == "GT" then return { gameTime = 0 } end end,
    util = { getWorld = function() return 1 end } },
  type = { ComponentType = { CARRIAGE_LIST = "CL", MODEL_INSTANCE_LIST = "MIL", GAME_TIME = "GT" },
    TransportVehicleConfig = { new = function(t) local c = { vehicles = {} } for i, p in ipairs(t.vehicles) do c.vehicles[i] = p end return c end },
    TransportVehiclePart = { new = function() return { part = {} } end }, LoadConfig = { new = function() return {} end },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }, Mat4f = { rotZTransl = function() return {} end } },
  cmd = { sendCommand = function() end, makeCustomEntityUpdateStateCmd = function() return {} end, makeCustomEntityUpdateTransformationCmd = function() return {} end },
}
local M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {frames=carriageFrames, invisible=buildHiddenRakeConfig, real=buildRealRakeConfig, adv=advanceRake}", "s"))()
-- the train: loco + a mixed rake
local pt = 0
local function part(mid, rev) pt = pt + 1; return { part = { modelId = mid, reversed = rev or false, compartment2loadConfig = { {} }, color = { x = 0.1 * pt, y = 0.2, z = 0.3 } }, autoLoadConfig = { false }, purchaseTime = 1000 + pt, tag = "coach" .. pt } end
setParts({ part(4225), part(7), part(7), part(8), part(7) })
local originals = {} for i, p in ipairs(train.parts) do originals[i] = p end
local start = layout()
-- detach: the loco hidden in place and the coaches hidden and turned (nothing
-- taken out or added), then the flip
local snap = { modelId = 4225, reversed = false, loads = { {} }, autos = { false }, purchaseTime = originals[1].purchaseTime, color = { x = 0.1, y = 0.2, z = 0.3 } }
setParts(M.invisible({ vehicles = train.parts }).vehicles)
local after = layout()
print(string.format("invisible train: head moved %.2f m", after[1].x - start[1].x))
assert(math.abs(after[1].x - start[1].x) < 1e-9, "the loco itself stays: the head does not move")
train.dir = -train.dir -- flip: the head is the other end; parts order kept; positions mirror about the middle
-- settle: targets
local coaches = {}
for i = 2, 5 do local o = originals[i]; coaches[#coaches + 1] = { snap = { modelId = o.part.modelId, reversed = false, loads = { {} }, autos = { false }, purchaseTime = o.purchaseTime, color = { x = 0.1 * i, y = 0.2, z = 0.3 } }, start = { x = start[i].x, y = 0, z = 0, yaw = 0 } } end
-- while hidden: the coaches are the SAME parts, flagged with the hide colour
local hiddenCount = 0
for _, p in ipairs(train.parts) do if p.tag and p.part.color and math.abs(p.part.color.x - 0.1234567) < 1e-6 then hiddenCount = hiddenCount + 1 end end
assert(hiddenCount == 5, "the loco and all four coaches hidden, none removed")
-- M5: a ghost whose model is not the hidden coach's at its place: no pull, the
-- run is put back (rather than a wagon's load shown on the wrong copy)
local wrong = {}
for i, c in ipairs(coaches) do wrong[i] = { snap = { modelId = c.snap.modelId }, start = c.start } end
wrong[2].snap.modelId = 999
local bad = { vehicleEntity = 1, locoPart = snap, locoPos = { x = start[1].x, y = 0 }, rake = { stage = "settle", ticks = 3, coaches = wrong }, gdist = 0 }
M.adv(bad, 0.1)
assert(bad.rake.stage == "failed", "a mismatched coach fails the rake: " .. bad.rake.stage)
print("M5: a ghost on the wrong hidden coach -> failed, train put back")
local run = { vehicleEntity = 1, locoPart = snap, locoPos = { x = start[1].x, y = 0 }, rake = { stage = "settle", ticks = 3, coaches = coaches }, gdist = 0 }
M.adv(run, 0.1)
assert(run.rake.stage == "pull", run.rake.stage)
-- the pull: the loco ghost draws forward; coach ghosts follow it exactly, never ahead of it
local placed = {}
api.cmd.makeCustomEntityUpdateTransformationCmd = function(e, t) return { e = e, t = t } end
api.type.Mat4f.rotZTransl = function(_, v) return v end
api.cmd.sendCommand = function(c) if type(c) == "table" and c.e and c.t then placed[c.e] = c.t end end
for i, c in ipairs(coaches) do c.ghost = 100 + i end
local steps = 0
while run.rake.stage == "pull" do
  run.gdist = math.min(run.gdist + 0.3, run.rake.pullTo)
  M.adv(run, 0.1)
  steps = steps + 1
  local f = run.gdist / run.rake.pullLen
  local p1 = placed[101]
  assert(math.abs(p1.x - (coaches[1].start.x + (coaches[1].target.x - coaches[1].start.x) * math.min(f, 1))) < 1e-6, "front coach moves with the loco")
  assert(steps < 1000)
end
assert(run.rake.stage == "uncouple", run.rake.stage)
for i, c in ipairs(coaches) do assert(math.abs(placed[100 + i].x - c.target.x) < 1e-6, "coach " .. i .. " drawn up onto its real coach") end
print(string.format("pull: %.1f m in %d steps, every coach ghost on its hidden coach", run.rake.pullLen, steps))
local waited = 0
while run.rake.stage == "uncouple" do M.adv(run, 0.1); waited = waited + 0.1 end
assert(run.rake.stage == "done" and waited >= 2.4, "uncouple pause, then done")
print(string.format("uncouple: %.1f s pause", waited))
-- recouple: the real train
setParts(M.real({ vehicles = train.parts }, snap, true, coaches, true).vehicles)
local final = layout()
local worst = 0
for i, c in ipairs(coaches) do
  -- final coaches from the head: last ... first, so coach k is at final[#final - k + 1]
  local f = final[#final - i + 1]
  worst = math.max(worst, math.abs(f.x - c.target.x))
end
local locoErr = math.abs(final[1].x - run.target.x)
print(string.format("final swap: coaches within %.2f m of where the ghosts slid to, loco within %.2f m", worst, locoErr))
print(string.format("coaches moved %.2f m in all (a loco length: %.1f)", coaches[1].target.x - start[2].x, 12.8))
assert(worst < 0.3 and locoErr < 0.3)
-- loco couples against the last coach: gap between loco and the neighbouring coach = half lengths
local gap = math.abs(final[1].x - final[2].x) - (12.8 + 23.4) / 2
print(string.format("loco to last coach: %.2f m apart (0 = coupled)", gap))
assert(math.abs(gap) < 0.3)
-- the same coach objects are back, in their original order along the track, with their own paint and facing
local byPos = {}
for i = 2, #final do byPos[#byPos + 1] = { x = final[i].x, p = train.parts[i] } end
table.sort(byPos, function(a, b) return math.abs(a.x - start[1].x) < math.abs(b.x - start[1].x) end)
for k, e in ipairs(byPos) do
  local o = originals[k + 1]
  assert(e.p == o, "coach " .. k .. " is the same part object (passengers and goods stay)")
  assert(math.abs(e.p.part.color.x - 0.1 * (k + 1)) < 1e-9, "paint restored on coach " .. k)
  assert(e.p.part.reversed == true, "coach " .. k .. " turned relative to the new head (so it faces as it did)")
end
-- nothing was bought or sold: the train is the very same five parts, the loco
-- with its own paint back
assert(#train.parts == 5, "five parts")
for _, p in ipairs(train.parts) do
  local found = false
  for _, o in ipairs(originals) do if o == p then found = true end end
  assert(found, "every part is one of the original parts")
end
assert(train.parts[1] == originals[1] and math.abs(train.parts[1].part.color.x - 0.1) < 1e-9, "the loco is the same part, own paint back")
print("no part added or removed in the whole run-around")
print("rake ok")
