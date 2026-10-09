-- ghost_build's parts spec: which nodes the engine places (every node holding an
-- axle, every fake bogie group) and which axles it turns (those without an
-- animation), with their rest poses, in the game's node order.
api = { res = { modelRep = {} } }
local partsSpecs, partsAtLoad, plainParams = assert(load(io.open(arg[1]):read("*a") .. "\nreturn partsSpecs, partsAtLoad, plainParams", "gb"))()
local function T(x, y, z, s) s = s or 1 return { s, 0, 0, 0, 0, 1, 0, 0, 0, 0, s, 0, x, y, z, 1 } end
local ENGINES = { engines = { { power = 1000 } } }
local model = {
  metadata = { landVehicle = ENGINES, railVehicle = { config = {
    axles = { "pony_w", "drive_w", "tender_w1", "tender_w2" },
    fakeBogies = { {}, { { group = "far_tender", position = -9 } } } } } },
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
local function group(i) local k = 4 + (i - 1) * 6 return { idx = v[k], parent = v[k + 1], a = v[k + 2], b = v[k + 3], pivot = v[k + 4], range = v[k + 5] } end
local b, p, t = group(1), group(2), group(3)
assert(b.idx == 1 and b.parent == 0 and b.a == -1 and b.b == -1, "body: one driving wheel")
assert(p.idx == 2 and p.parent == 1 and p.a == 4.5, "pony truck inside the body, by its axle at 4.5")
assert(t.idx == 7 and t.parent == 0 and t.a == -7 and t.b == -11, "tender by its axles (scaled 7%)")
-- the copy is placed as the game places a vehicle, on its own reference
-- points: nothing on the root here, so the centres of its top parts, the body
-- (-1) and the tender (-9); the tender turns where its line meets that one:
-- ((-1)(-9) - (-7)(-11)) / (-1 - 9 + 7 + 11) = -8.5
local _, frame = partsSpecs(model)
assert(frame and frame[1] == -1 and frame[2] == -9, "the copy's frame: through the body's and the tender's centres")
assert(math.abs(t.pivot - (-8.5)) < 1e-6, "the tender turns about -8.5")
assert(math.abs(p.pivot - ((-1) * (-1) - 4.5 * 4.5) / (-2 - 9)) < 1e-3, "the pony truck where its axle's tangent meets the body's line")
local ax = 4 + 3 * 6
assert(v[ax] == 3 and v[ax + 3] == 8 and v[ax + 6] == 9, "pony and tender axles turn")
assert(math.abs(v[ax + 4] - 0.55) < 1e-6, "an axle's radius is its height")
-- the far level of detail: its fake bogie group, by its own position
local f = nums(specs[2])
assert(f[1] == 3 and f[2] == 1 and f[3] == 0 and f[4] == 2 and f[6] == -9 and f[7] == -9, "far tender: the fake bogie at its centre")
-- worked out as the model loads (the load step later gets no lods): the
-- parameters go on the model's own transformator config
local loaded = partsAtLoad("loco.mdl", { metadata = { railVehicle = model.metadata.railVehicle, landVehicle = ENGINES,
  transformatorConfig = { transformator = { name = "::/vehicle/train/shared/default_train.trf" }, params = { other = 1 } } }, lods = model.lods })
local p = loaded.metadata.transformatorConfig.params
assert(p.runaround_parts1 == specs[1] and p.runaround_parts2 == specs[2] and p.other == 1, "at load: specs added, other params kept")
assert(p.runaround_frame == "-1.0000 -9.0000", "and the copy's frame for the run-around")
-- the parts got their animations, named after the full-detail spec's order
-- (1 body, 2 pony, 3 tender; axles 1 pony, 2-3 tender), the far tender by place
local L1, L2 = model.lods[1].node, model.lods[2].node
local body, pony, tender = L1.children[1], L1.children[1].children[1], L1.children[2]
assert(body.animations.runaround_yaw1 and pony.animations.runaround_yaw2 and tender.animations.runaround_yaw3, "yaw animations on the parts")
local kf = tender.animations.runaround_yaw3.params.keyframes
-- the tender's range: on a 30 m curve its line turns ((-7 - 11) - (-1 - 9)) / 60
-- rad from the frame's (7.6 degrees), with a quarter more and 2 degrees spare
local range = math.deg(8 / 60) * 1.25 + 2
assert(math.abs(t.range - range) < 0.01, "the tender's range: " .. tostring(t.range))
local last = #kf
assert(tender.animations.runaround_yaw3.type == "KEYFRAME_MATRIX" and kf[1].time == 0 and kf[2].time == 1
  and math.abs(kf[last].time - (1 + 2 * t.range * 100)) < 1e-6 and last < 40, "frame 0 no turn, then -range..range at 100 ms a degree, in few keyframes: " .. last)
for j = 1, 16 do assert(kf[1].transf[j] == ({ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 })[j], "frame 0 is no turn at all") end
assert(math.abs(kf[last].transf[2] - math.sin(math.rad(t.range))) < 1e-9 and math.abs(kf[2].transf[2] + math.sin(math.rad(t.range))) < 1e-9, "a turn about z")
-- a turn leaves the pivot where it is (in the tender's node: from -9)
local px = t.pivot + 9
local k = kf[last].transf
assert(math.abs(k[1] * px + k[5] * 0 + k[13] - px) < 1e-9 and math.abs(k[2] * px + k[6] * 0 + k[14]) < 1e-9, "turned about its pivot")
assert(pony.children[1].animations.runaround_spin1 and tender.children[1].animations.runaround_spin2 and tender.children[2].animations.runaround_spin3, "spin on the small axles")
assert(not body.children[2].animations.runaround_spin1 and body.children[2].animations.wheels, "the driving wheel keeps only its own")
assert(L2.children[2].animations.runaround_yaw3 and not (L2.children[1].animations or {}).runaround_yaw1, "far tender matched by where its wheels are")
-- no transformator declared: the game's default one, as the game would add it
loaded = partsAtLoad("loco2.mdl", { metadata = { railVehicle = model.metadata.railVehicle, landVehicle = ENGINES, transportVehicle = { carrier = "RAIL" } }, lods = model.lods })
assert(loaded.metadata.transformatorConfig.transformator.name == "::/vehicle/train/shared/default_train.trf" and loaded.metadata.transformatorConfig.skipFromLod == 1, "default transformator")
-- one config per level of detail, as a model file can have it
local perLod = { metadata = { railVehicle = { configs = { { axles = model.metadata.railVehicle.config.axles }, { fakeBogies = { { group = "far_tender", position = -9 } } } } },
  transformatorConfig = { transformator = { name = "x" } } }, lods = model.lods }
loaded = partsAtLoad("loco3.mdl", perLod)
assert(loaded.metadata.transformatorConfig.params.runaround_parts1 == specs[1] and loaded.metadata.transformatorConfig.params.runaround_parts2 == specs[2], "per-level configs give the same specs")
-- not a rail vehicle, or broken data: left alone, no error
assert(partsAtLoad("tree.mdl", { metadata = {} }).metadata.transformatorConfig == nil)
assert(partsAtLoad("odd.mdl", 5) == 5)
-- the parameters, as the load step may get them back: a plain table, or an
-- engine object that can only be indexed; either way every one is kept
local plain = plainParams({ runaround_parts1 = "a", devers_rest1 = "r", custom = 3 })
assert(plain.runaround_parts1 == "a" and plain.devers_rest1 == "r" and plain.custom == 3, "a table: all kept")
local obj = setmetatable({}, { __index = function(_, k) return ({ runaround_parts1 = "a", runaround_parts2 = "b", runaround_frame = "1 -1", devers_rest1 = "r", devers_flip = -1 })[k] end })
plain = plainParams(obj)
assert(type(plain) == "table" and rawget(plain, "runaround_parts1") == "a" and plain.runaround_parts2 == "b" and plain.devers_rest1 == "r" and plain.devers_flip == -1, "an indexable object: the known ones kept")
assert(plain.runaround_frame == "1 -1", "the copy's frame kept too")
assert(plainParams(nil) == nil and plainParams({}) == nil, "none: nil")
-- a tender body on two bogies (as the Su's): turned by the bogies' centres;
-- a coach's root on its bogies is the vehicle itself, and so is a single node
-- wrapping everything (devers)
local function bogie(x) return { name = "b" .. x, transf = T(x, 0, 0), children = { { name = "ax" .. x, transf = T(0.9, 0, 0.5) }, { name = "ay" .. x, transf = T(-0.9, 0, 0.5) } } } end
local su = { metadata = { railVehicle = { config = { axles = { "ax1", "ay1", "ax-3", "ay-3" } } } },
  lods = { { node = { name = "Root", children = { { name = "tender", transf = T(-10, 0, 0), children = { bogie(1), bogie(-3) } } } } } } }
local sv = nums(partsSpecs(su)[1])
-- nodes: root 0, tender 1, bogie 2 (axles 3-4), bogie 5 (axles 6-7)
assert(sv[2] == 3 and sv[4] == 1 and sv[6] == -9 and sv[7] == -13, "tender body turned by its bogies at -9 and -13")
local coach = { metadata = { railVehicle = { config = { axles = { "ax5", "ay5", "ax-5", "ay-5" } } } },
  lods = { { node = { name = "Root", children = { bogie(5), bogie(-5) } } } } }
local cv = nums(partsSpecs(coach)[1])
assert(cv[2] == 2 and cv[4] == 1 and cv[4 + 6] == 4, "a coach: its two bogies, not its root")
local wrapped = { metadata = coach.metadata, lods = { { node = { name = "Root", children = { { name = "devers_roulis", children = { bogie(5), bogie(-5) } } } } } } }
local wv = nums(partsSpecs(wrapped)[1])
assert(wv[2] == 2 and wv[4] == 2, "under devers' wrapper: still just the bogies")
-- an axle name on several nodes (the 8F's four driving axles share one): every one is an axle
local eight = { metadata = { railVehicle = { config = { axles = { "drv" } } } },
  lods = { { node = { name = "Root", children = { { name = "frame", transf = T(1, 0, 0), children = {
    { name = "drv", transf = T(-2, 0, 0.8), animations = { wheels = {} } }, { name = "drv", transf = T(0, 0, 0.8), animations = { wheels = {} } },
    { name = "drv", transf = T(2, 0, 0.8), animations = { wheels = {} } } } } } } } } }
local ev = nums(partsSpecs(eight)[1])
assert(ev[2] == 1 and ev[4] == 1 and ev[6] == 3 and ev[7] == -1, "the frame by all three driving axles, -1 .. 3")
local _, ef = partsSpecs(eight)
assert(ef[1] == 3 and ef[2] == -1, "one top part: the copy is placed on its line")
-- a body that is the root, on two bogies (a diesel): on the line through the bogies' centres
local _, cf = partsSpecs(coach)
assert(cf[1] == 5 and cf[2] == -5, "a body on two bogies: on the bogies' centres")
-- fake bogie points on the root itself (an articulated car's shared bogie): those
local jac = { metadata = { railVehicle = { config = { axles = { "ax5", "ay5" }, fakeBogies = { { group = "Root", position = -9 } } } } },
  lods = { { node = { name = "Root", children = { bogie(5) } } } } }
local _, jf = partsSpecs(jac)
assert(jf and jf[1] == 5 and jf[2] == -9, "an articulated car: on the line through its own bogie and the shared one")
-- the parent field: the nearest placed part above (a bogie under an unplaced group under the tender)
local deep = { metadata = { railVehicle = { config = { axles = { "t1", "t2", "q1", "q2" } } } },
  lods = { { node = { name = "Root", children = { { name = "tender", transf = T(-9, 0, 0), children = {
    { name = "t1", transf = T(2, 0, 0.5) }, { name = "t2", transf = T(-2, 0, 0.5) },
    { name = "holder", transf = T(-1, 0, 0), children = { { name = "truck", transf = T(-3, 0, 0), children = {
      { name = "q1", transf = T(0.5, 0, 0.4) }, { name = "q2", transf = T(-0.5, 0, 0.4) } } } } } } } } } } } }
local dv = nums(partsSpecs(deep)[1])
-- nodes: root 0, tender 1, t1 2, t2 3, holder 4, truck 5
assert(dv[2] == 2 and dv[4 + 6] == 5 and dv[4 + 6 + 1] == 1, "the truck's turn is measured from the tender, past the group between")
-- a vehicle without an engine (a coach, a wagon): its axles spin, nothing turns
local function fresh() local m = { metadata = { railVehicle = model.metadata.railVehicle, transformatorConfig = { transformator = { name = "x" } } }, lods = {
  { node = { name = "Root", children = { { name = "b1", transf = T(5, 0, 0), children = { { name = "pony_w", transf = T(0.5, 0, 0.45) }, { name = "tender_w1", transf = T(-0.5, 0, 0.45) } } } } } } } } return m end
local wag = partsAtLoad("wagon.mdl", fresh())
local b1 = wag.lods[1].node.children[1]
assert(b1.children[1].animations and b1.children[1].animations.runaround_spin1 and not (b1.animations and b1.animations.runaround_yaw1), "unpowered: spins, no turns")
assert(wag.metadata.transformatorConfig.params.runaround_parts1 ~= nil, "and its spec")
-- a far level whose parts don't match by name or place: the node of the same name
local farOnly = { metadata = { landVehicle = ENGINES, railVehicle = { config = { axles = { "tw1", "tw2" }, fakeBogies = { {}, { { group = "lod2_coal", position = 0 } } } } },
  transformatorConfig = { transformator = { name = "x" } } }, lods = {
  { node = { name = "Root", children = { { name = "loco" }, { name = "group_29", transf = T(-9, 0, 0), children = { { name = "tw1", transf = T(2, 0, 0.5) }, { name = "tw2", transf = T(-2, 0, 0.5) } } } } } },
  { node = { name = "Root", children = { { name = "group_29", transf = T(-9, 0, 0), children = { { name = "lod2_coal" } } } } } } } }
local fo = partsAtLoad("black5.mdl", farOnly)
assert(fo.lods[2].node.children[1].animations and fo.lods[2].node.children[1].animations.runaround_yaw1, "the far tender: its node of the same name")
print("parts spec ok")
