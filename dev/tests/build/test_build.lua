-- ghost_build.script.lua: patches rail vehicles to the wrappers under the mod's own
-- ID, and touches nothing when the game has loaded the mod under another ID (M3).
local set, added = {}, {}
local function model(trf, snd)
  return { metadata = {
    transportVehicle = { carrier = "RAIL" }, landVehicle = {},
    transformatorConfig = { transformator = { name = trf } },
    soundConfig = { soundSet = { name = snd } } } }
end
local models = {
  [1] = { "vehicle/train/br_e94.mdl", model("vehicle/train/shared/default_train.trf", "/vehicle/train/shared/sound/train_electric_old.snd") },
  [2] = { "vehicle/waggon/coach.mdl", model("vehicle/train/shared/default_train.trf", "/vehicle/waggon/shared/sound/waggon_old.snd") },
  [3] = { "mcs_1::/vehicle/mcs/loco.mdl", model("mcs_1::/vehicle/mcs/scripts/train_all.trf", "mymod/own.snd") },
  [6] = { "devers_1::/vehicle/train/x/caboose.mdl", model("devers_1::/vehicle/train/devers/devers_any.trf", "/vehicle/waggon/shared/sound/waggon_old.snd") },
  [7] = { "gone_1::/vehicle/gone/tender.mdl", model("gone_1::/vehicle/gone/missing.trf", "/vehicle/waggon/shared/sound/waggon_old.snd") },
}
-- Other mods' transformator files, served the way ug_require runs them (a .trf
-- defines a global data()). devers-style: an update and a particle script only.
-- mcs-style (as installed in the owner's game): two more hooks.
local FILES = {
  ["devers_1::/vehicle/train/devers/devers_any.trf.lua"] = function()
    data = function() return { updateScript = { fileName = "devers_train.script@any.updateFn" },
      updateParticleSystemScript = { fileName = "devers_train.script@any.updateParticleSystemFn" } } end
  end,
  ["devers_1::/vehicle/train/devers/devers_train.script.lua"] = function()
    return { any = { updateFn = function() end, updateParticleSystemFn = function() end } }
  end,
  ["mcs_1::/vehicle/mcs/scripts/train_all.trf.lua"] = function()
    data = function() return { updateScript = { fileName = "train_all.script@train.updateFn" },
      updateParticleSystemScript = { fileName = "train_all.script@train.updateParticleSystemFn" },
      getEmittableModelsScript = { fileName = "train_all.script@train.getEmittableModelsFn" } } end
  end,
  ["mcs_1::/vehicle/mcs/scripts/train_all.script.tl"] = function()
    return { train = { updateFn = function() end } }
  end,
}
ug_require = function(p) local f = FILES[p] if f == nil then error("module not found: " .. p) end return f() end
api = { res = { modelRep = {
  getAll = function() local t = {} for id, m in pairs(models) do t[id] = m[1] end return t end,
  getAsTable = function(id) return models[id][2] end,
  setAsTable = function(id, t) set[id] = t return true end,
  find = function() return -1 end,
  addAsTable = function(name, t) added[name] = t return true end,
} } }
local function build(id)
  set, added = {}, {}
  getCurrentModId = function() return id end
  local lines = {}
  local op = print
  print = function(s) lines[#lines + 1] = s end
  local mod = assert(loadfile(arg[1]))()
  data().postRunFn({}, {})
  print = op
  return lines
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

build("runaround_helper_1")
assert(set[1] and set[1].metadata.transformatorConfig.transformator.name == "runaround_helper_1::/res/models/runaround_ghost/real.trf", "loco patched to the wrapped transformator")
assert(set[1].metadata.soundConfig.soundSet.name == "runaround_helper_1::/res/audio/ghostwrap/train_electric_old.snd", "and the wrapped sound set")
assert(set[2] ~= nil, "coach patched")
-- another mod's transformator with more hooks than chain.trf passes on: left alone
assert(set[3] == nil, "a transformator with getEmittableModelsScript is not chained")
-- one that can't be found: left alone
assert(set[7] == nil or set[7].metadata.transformatorConfig.transformator.name == "gone_1::/vehicle/gone/missing.trf", "a missing transformator is not chained")
-- devers-style (update and particles only, update found): chained, its params kept
local function chainedName(i) return set[i] and set[i].metadata.transformatorConfig.transformator.name end
models[6][2].metadata.transformatorConfig.params = { devers_trf = "x.trf", devers_carrier = "RAIL" }
local out = build("runaround_helper_1")
assert(chainedName(6) == "runaround_helper_1::/res/models/runaround_ghost/chain.trf", "a devers-style transformator is chained")
local p6 = set[6] and set[6].metadata.transformatorConfig.params
assert(p6 and p6.runaround_trf == "devers_1::/vehicle/train/devers/devers_any.trf" and p6.devers_trf == "x.trf" and p6.devers_carrier == "RAIL", "the other mod's own params are kept")
assert(added["runaround_ghost_real/caboose.mdl"] ~= nil, "a chained vehicle with a wrapped sound set is marked ready")
local whyMcs, whyGone = false, false
for _, l in ipairs(out) do
  if l:find("left alone: mcs_1::/vehicle/mcs/scripts/train_all.trf - its transformator also has getEmittableModelsScript", 1, true) then whyMcs = true end
  if l:find("left alone: gone_1::/vehicle/gone/missing.trf - its transformator could not be read", 1, true) then whyGone = true end
end
assert(whyMcs and whyGone, "the log says why each was left alone:\n" .. table.concat(out, "\n"))
-- no ug_require (the load scope might not have it): nothing is chained
local saved_req = ug_require
ug_require = nil
build("runaround_helper_1")
assert(chainedName(6) ~= "runaround_helper_1::/res/models/runaround_ghost/chain.trf", "without ug_require nothing is chained")
ug_require = saved_req
print("build: devers-style chained; more hooks, missing, or no ug_require -> left alone")
assert(added["runaround_ghost_real/br_e94.mdl"] and added["runaround_ghost_dyn/br_e94.mdl"], "marker and copy built")
print("build: own ID - vehicles patched, markers and copies built")

-- M1: locos sharing a file name (two mods' and the fixture's own loco.mdl) are left alone (a marker or copy
-- named "loco.mdl" could not say which one it is); the others are prepared as usual.
models[4] = { "mod_a_1::/res/models/model/vehicle/train/loco.mdl", model("vehicle/train/shared/default_train.trf", "/vehicle/train/shared/sound/train_diesel.snd") }
models[5] = { "mod_b_1::/res/models/model/vehicle/train/loco.mdl", model("vehicle/train/shared/default_train.trf", "/vehicle/train/shared/sound/train_steam_old.snd") }
local out = build("runaround_helper_1")
assert(set[4] == nil and set[5] == nil, "neither loco.mdl is patched")
assert(added["runaround_ghost_real/loco.mdl"] == nil and added["runaround_ghost_dyn/loco.mdl"] == nil, "no marker or copy named loco.mdl")
assert(set[1] ~= nil and added["runaround_ghost_real/br_e94.mdl"] ~= nil, "a unique one is still prepared")
assert(out[#out]:find("3 left alone (file name shared)", 1, true), "the summary says so: " .. out[#out])
models[4], models[5] = nil, nil
print("build: two mods' loco.mdl left alone, the rest prepared")

local lines = build("12345_1")
assert(count(set) == 0 and count(added) == 0, "another ID: nothing patched or added")
assert(lines[1] and lines[1]:find("SKIPPED", 1, true), "and it says so")
print("build: other ID - nothing touched: " .. lines[1])
print("build ok")
