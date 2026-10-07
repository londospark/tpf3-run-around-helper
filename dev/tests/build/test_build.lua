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
  [3] = { "mymod/loco.mdl", model("mymod/own.trf", "mymod/own.snd") },
}
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
assert(set[3] == nil, "a loco with its own transformator and sound set is left alone")
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
