-- The detach keeps every part on the train - the loco is hidden in its place, not
-- swapped out - so a vehicle replace has nothing to sell or buy (seen live: taking
-- the loco off sold it and bought it back, with the money shown in the world).
api = { res = { modelRep = { getAll = function() return {} end,
  get = function() return { metadata = { transportVehicle = { compartments = { { loadConfigs = { {} } } } } } } end } },
  type = { TransportVehicleConfig = { new = function(t) local c = { vehicles = {} } for i, p in ipairs(t.vehicles) do c.vehicles[i] = p end return c end },
    TransportVehiclePart = { new = function() return { part = {} } end }, LoadConfig = { new = function() return {} end },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } } }
local M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {plain=buildConfigWithHiddenLoco, rake=buildHiddenRakeConfig}", "s"))()
local function train()
  return { vehicles = {
    { part = { modelId = 4225, reversed = false, color = { x = 1, y = 0, z = 0 } }, purchaseTime = 11 },
    { part = { modelId = 1, reversed = false, color = { x = 0, y = 1, z = 0 } }, purchaseTime = 12 },
    { part = { modelId = 1, reversed = true, color = { x = 0, y = 0, z = 1 } }, purchaseTime = 13 },
  } }
end
local function hidden(p) return math.abs(p.part.color.x - 0.1234567) < 1e-6 end
local function sameParts(before, after)
  if #before ~= #after then return false end
  local seen = {}
  for _, p in ipairs(before) do seen[p] = true end
  for _, p in ipairs(after) do if not seen[p] then return false end end
  return true
end

-- the simple sequence: the loco hidden in place, the coaches as they are
local t = train()
local before = { t.vehicles[1], t.vehicles[2], t.vehicles[3] }
local cfg = M.plain(t, 1)
assert(sameParts(before, cfg.vehicles), "the same parts, none added or removed")
assert(cfg.vehicles[1] == before[1] and hidden(cfg.vehicles[1]), "the loco stays first, hidden")
assert(not hidden(cfg.vehicles[2]) and not hidden(cfg.vehicles[3]), "the coaches stay in view")
print("detach (simple): loco hidden in place, nothing added or removed")

-- the ghost rake: loco hidden first, coaches hidden in reverse order, turned
t = train()
before = { t.vehicles[1], t.vehicles[2], t.vehicles[3] }
cfg = M.rake(t)
assert(sameParts(before, cfg.vehicles), "the same parts, none added or removed")
assert(cfg.vehicles[1] == before[1] and hidden(cfg.vehicles[1]), "the loco first, hidden")
assert(cfg.vehicles[2] == before[3] and cfg.vehicles[3] == before[2], "coaches in reverse order")
assert(hidden(cfg.vehicles[2]) and hidden(cfg.vehicles[3]), "coaches hidden")
assert(before[2].part.reversed == true and before[3].part.reversed == false, "coaches turned")
print("detach (ghost rake): loco and coaches hidden, nothing added or removed")
print("detach ok")
