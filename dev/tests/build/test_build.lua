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

local lines = build("12345_1")
assert(count(set) == 0 and count(added) == 0, "another ID: nothing patched or added")
assert(lines[1] and lines[1]:find("SKIPPED", 1, true), "and it says so")
print("build: other ID - nothing touched: " .. lines[1])
print("build ok")
