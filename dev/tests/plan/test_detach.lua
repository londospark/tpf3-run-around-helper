-- The detach consist must not contain the loco.
api = { res = { modelRep = { getAll = function() return { [900] = "m::/res/models/runaround_standin/standin_cm50.mdl", [901] = "m::/res/models/runaround_standin/standin_cm1225.mdl" } end,
  get = function() return { metadata = { transportVehicle = { compartments = { { loadConfigs = { {} } } } } } } end } },
  type = { TransportVehicleConfig = { new = function(t) local c = { vehicles = {} } for i, p in ipairs(t.vehicles) do c.vehicles[i] = p end return c end },
    TransportVehiclePart = { new = function() return { part = {} } end }, LoadConfig = { new = function() return {} end } } }
local M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {b=buildCreepConfig}", "s"))()
local tvc = { vehicles = { { part = { modelId = 4225 } }, { part = { modelId = 1 } }, { part = { modelId = 1 } } } }
local cfg = M.b(tvc, 12.75, 0, { loads = { {} }, autos = { false } }, 1)
local ids = {} for i, p in ipairs(cfg.vehicles) do ids[i] = p.part.modelId end
print(table.concat(ids, " "))
assert(#cfg.vehicles == 4 and ids[1] == 900 and ids[2] == 901 and ids[3] == 1 and ids[4] == 1, "stand-ins then coaches, no loco")
print("detach ok")
