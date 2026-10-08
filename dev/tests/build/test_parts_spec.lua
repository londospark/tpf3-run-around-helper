-- ghost_build's parts spec: which nodes the engine places (every node holding an
-- axle, every fake bogie group) and which axles it turns (those without an
-- animation), with their rest poses, in the game's node order.
api = { res = { modelRep = {} } }
local partsSpecs, partsAtLoad = assert(load(io.open(arg[1]):read("*a") .. "\nreturn partsSpecs, partsAtLoad", "gb"))()
local function T(x, y, z, s) s = s or 1 return { s, 0, 0, 0, 0, 1, 0, 0, 0, 0, s, 0, x, y, z, 1 } end
local model = {
  metadata = { railVehicle = { config = {
    axles = { "pony_w", "drive_w", "tender_w1", "tender_w2" },
    fakeBogies = { {}, { { group = "far_tender", position = 0 } } } } } },
  lods = {
    { node = { name = "Root", children = {
      { name = "body", children = {
        { name = "pony", transf = T(4, 0, 0), children = { { name = "pony_w", transf = T(0.5, 0, 0.45) }, { name = "pony_w2", transf = T(-0.5, 0, 0.45) } } },
        { name = "drive_w", transf = T(-1, 0, 0.9), animations = { wheels = {} } },
        { name = "drive_w2", transf = T(1, 0, 0.9), animations = { wheels = {} } } } },
      { name = "tender", transf = T(-9, 0, 0), children = {
        { name = "tender_w1", transf = T(2, 0, 0.55, 1.07) },
        { name = "tender_w2", transf = T(-2, 0, 0.55, 1.07) } } } } } },
    { node = { name = "Root", children = { { name = "far_body" }, { name = "far_tender", transf = T(-9, 0, 0) } } } },
  } }
local specs = partsSpecs(model)
print(specs[1]) print(specs[2])
local function nums(s) local v = {} for w in s:gmatch("%S+") do v[#v + 1] = tonumber(w) end return v end
local v = nums(specs[1])
-- 10 nodes (root 0, body 1, pony 2 and its wheels 3-4, driving wheels 5-6, tender 7 and its axles 8-9); placed: body by its driving wheel at -1, pony by its axle at 4.5, tender by its axles -7 .. -11
assert(v[1] == 10 and v[2] == 3 and v[3] == 3, "10 nodes, 3 placed, 3 axles turned (not the driving wheel)")
local function group(i) local k = 4 + (i - 1) * 16 return { idx = v[k], parent = v[k + 1], x = v[k + 2], a = v[k + 14], b = v[k + 15] } end
local b, p, t = group(1), group(2), group(3)
assert(b.idx == 1 and b.parent == 0 and b.a == -1 and b.b == -1, "body: one driving wheel")
assert(p.idx == 2 and p.parent == 1 and p.x == 4 and p.a == 4.5, "pony truck inside the body, at 4")
assert(t.idx == 7 and t.x == -9 and t.a == -7 and t.b == -11, "tender by its axles (scaled 7%)")
local ax = 4 + 3 * 16
assert(v[ax] == 3 and v[ax + 3] == 8 and v[ax + 6] == 9, "pony and tender axles turn")
assert(math.abs(v[ax + 4] - 0.55) < 1e-6, "an axle's radius is its height")
-- the far level of detail: its fake bogie group, by its own position
local f = nums(specs[2])
assert(f[1] == 3 and f[2] == 1 and f[3] == 0 and f[4] == 2 and f[18] == -9 and f[19] == -9, "far tender: the fake bogie at its centre")
-- worked out as the model loads (the load step later gets no lods): the
-- parameters go on the model's own transformator config
local loaded = partsAtLoad("loco.mdl", { metadata = { railVehicle = model.metadata.railVehicle,
  transformatorConfig = { transformator = { name = "::/vehicle/train/shared/default_train.trf" }, params = { other = 1 } } }, lods = model.lods })
local p = loaded.metadata.transformatorConfig.params
assert(p.runaround_parts1 == specs[1] and p.runaround_parts2 == specs[2] and p.other == 1, "at load: specs added, other params kept")
-- no transformator declared: the game's default one, as the game would add it
loaded = partsAtLoad("loco2.mdl", { metadata = { railVehicle = model.metadata.railVehicle, transportVehicle = { carrier = "RAIL" } }, lods = model.lods })
assert(loaded.metadata.transformatorConfig.transformator.name == "::/vehicle/train/shared/default_train.trf" and loaded.metadata.transformatorConfig.skipFromLod == 1, "default transformator")
-- one config per level of detail, as a model file can have it
local perLod = { metadata = { railVehicle = { configs = { { axles = model.metadata.railVehicle.config.axles }, { fakeBogies = { { group = "far_tender", position = 0 } } } } },
  transformatorConfig = { transformator = { name = "x" } } }, lods = model.lods }
loaded = partsAtLoad("loco3.mdl", perLod)
assert(loaded.metadata.transformatorConfig.params.runaround_parts1 == specs[1] and loaded.metadata.transformatorConfig.params.runaround_parts2 == specs[2], "per-level configs give the same specs")
-- not a rail vehicle, or broken data: left alone, no error
assert(partsAtLoad("tree.mdl", { metadata = {} }).metadata.transformatorConfig == nil)
assert(partsAtLoad("odd.mdl", 5) == 5)
print("parts spec ok")
