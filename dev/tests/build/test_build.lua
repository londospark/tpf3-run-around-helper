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
local function key(n) return (n:gsub("[^%w]", function(ch) return string.format("_%02x", ch:byte()) end)) end
assert(added["runaround_ghost_real/" .. key("vehicle/train/br_e94.mdl") .. ".mdl"] and added["runaround_ghost_dyn/" .. key("vehicle/train/br_e94.mdl") .. ".mdl"], "marker and copy built, by full name")
print("build: own ID - vehicles patched, markers and copies built")

-- M1: two mods' locos with the same file name each get their own marker and copy.
models[4] = { "mod_a_1::/res/models/model/vehicle/train/loco.mdl", model("vehicle/train/shared/default_train.trf", "/vehicle/train/shared/sound/train_diesel.snd") }
models[5] = { "mod_b_1::/res/models/model/vehicle/train/loco.mdl", model("vehicle/train/shared/default_train.trf", "/vehicle/train/shared/sound/train_steam_old.snd") }
build("runaround_helper_1")
local markers = 0
for name in pairs(added) do if name:find("runaround_ghost_real/", 1, true) and name:find(key("loco.mdl"), 1, true) then markers = markers + 1 end end
assert(markers == 2, "both mods' loco.mdl marked, got " .. markers)
for name in pairs(added) do assert(name:match("^runaround_ghost_%a+/[%w_]+%.mdl$"), "a plain file name: " .. name) end
models[4], models[5] = nil, nil
print("build: two mods' loco.mdl kept apart")

-- The game script finds them by the same key.
local G = assert(load(io.open(arg[2]):read("*a") .. "\nreturn {modelKey=modelKey}", "g"))()
local B = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {modelKey=modelKey}", "b"))()
for _, n in ipairs({ "vehicle/train/br_e94.mdl", "mod_a_1::/res/models/model/vehicle/train/loco.mdl", "a/b_c.mdl", "a_b/c.mdl" }) do
  assert(G.modelKey(n) == B.modelKey(n), "both scripts file " .. n .. " under the same name")
end
assert(B.modelKey("a/b_c.mdl") ~= B.modelKey("a_b/c.mdl"), "keys are unique")
print("build: game script and load script agree on keys")

local lines = build("12345_1")
assert(count(set) == 0 and count(added) == 0, "another ID: nothing patched or added")
assert(lines[1] and lines[1]:find("SKIPPED", 1, true), "and it says so")
print("build: other ID - nothing touched: " .. lines[1])
print("build ok")
