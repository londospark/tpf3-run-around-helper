-- End to end: the loco copy's wheels on a curve. For a model of each kind of
-- tender loco found in the base game, the DLC and the owner's mods, run the
-- mod's own load step and copy update (dev/tools/parts_sim.lua), draw the node
-- tree with the frames played, and check every wheel is on the track, beyond
-- what its rigid part can't help (a long rigid wheelbase can't touch a curve
-- at every axle; real trains are the same). On the previous version the
-- tenders were 0.8 m (Su) to 1.2 m (A4) off a 150 m curve.
-- Usage: lua test_parts_geometry.lua ghost_build.script.lua ghost_real.script.lua parts_sim.lua
local sim = dofile(arg[3])
sim.load(arg[1], arg[2])

local function T(x, y, z, yaw)
  local c, s = math.cos(yaw or 0), math.sin(yaw or 0)
  return { c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, x, y, z, 1 }
end
local function wheel(name, x, own) return { name = name, transf = T(x, 0, 0.5), animations = own and { wheels = {} } or nil } end
local function bogie(name, x, w1, w2, h) return { name = name, transf = T(x, 0, 0), children = { wheel(w1, h), wheel(w2, -h) } } end
local function model(lods, axles, fakeBogies)
  return { metadata = { railVehicle = { config = { axles = axles, fakeBogies = fakeBogies } },
    transformatorConfig = { transformator = { name = "::/vehicle/train/shared/default_train.trf" } } }, lods = lods }
end

local cases = {}
-- Su: the loco body under the root on its own axles; the tender's node at its
-- front (-10), holding two bogies, no axles of its own; a far level with fake
-- bogies on the same groups
cases.su = model({
  { node = { name = "RootNode", children = {
    { name = "front_grp", children = { wheel("fw1", 5.36), wheel("fw2", 2.4, true), wheel("fw3", 0.41, true), wheel("fw4", -1.6, true), wheel("fw5", -4.97) } },
    { name = "back_grp", transf = T(-10.01, 0, 0), children = { { name = "back_body" },
      bogie("back_b1_grp", 0.87, "bw1", "bw2", 0.98), bogie("back_b2_grp", -3.85, "bw3", "bw4", 0.98) } } } } },
  { node = { name = "RootNode", children = { { name = "front_grp" }, { name = "back_grp", transf = T(-10.01, 0, 0) } } } },
}, { "fw1", "fw2", "fw3", "fw4", "fw5", "bw1", "bw2", "bw3", "bw4" },
  { {}, { { group = "front_grp", position = 5.35 }, { group = "front_grp", position = -4.97 },
    { group = "back_grp", position = -9.14 }, { group = "back_grp", position = -13.86 } } })
-- A4: the loco body and the tender both have their node at x = 0 (their meshes
-- are placed in the model); a leading bogie inside the body; the far level
-- likewise, by fake bogies (matching by node origin gave the loco the tender's turn)
cases.a4 = model({
  { node = { name = "RootNode", children = {
    { name = "front_grp", children = { wheel("dw1", 6.36, true), wheel("dw2", 4.16, true), wheel("dw3", 1.96, true), wheel("tw", -0.94),
      bogie("front_b1_grp", 8.98, "lw1", "lw2", 0.95) } },
    { name = "back_grp", children = { wheel("tw1", -3.74), wheel("tw2", -5.4), wheel("tw3", -7.0), wheel("tw4", -8.61) } } } } },
  { node = { name = "RootNode", children = { { name = "front_grp" }, { name = "back_grp" } } } },
}, { "dw1", "dw2", "dw3", "tw", "lw1", "lw2", "tw1", "tw2", "tw3", "tw4" },
  { {}, { { group = "front_grp", position = 6.36 }, { group = "front_grp", position = -0.94 },
    { group = "back_grp", position = -3.74 }, { group = "back_grp", position = -8.61 } } })
-- 8F (gr1m): the body holds no axles; its four driving axles share one name,
-- in a frame group whose node is a metre from them; pony and rear trucks are
-- single axles in groups placed metres from their wheels
cases.f8 = model({
  { node = { name = "RootNode", children = {
    { name = "group_1", transf = T(1, 0, 0), children = { { name = "boiler" },
      { name = "group_25", transf = T(-0.25, 0, 0), children = { wheel("drv", -0.26, true), wheel("drv", -2.0, true), wheel("drv", 1.45, true), wheel("drv", 3.2, true) } },
      { name = "group_31", transf = T(-3.1, 0, 0), children = { wheel("rear", -2.07) } },
      { name = "group_34", transf = T(3.55, 0, 0), children = { wheel("pony", 2.1) } } } },
    { name = "group_37", transf = T(-8.8, 0, 0.07), children = { wheel("t1", 0), wheel("t2", 2.15), wheel("t3", -2.15) } } } } },
}, { "drv", "rear", "pony", "t1", "t2", "t3" })
-- Big Boy: articulated - two engine units in a boiler group with no axles,
-- each with a truck of its own; a tender with its own axles and a bogie
cases.bigboy = model({
  { node = { name = "RootNode", children = {
    { name = "front_grp", transf = T(5.05, 0, 0), children = { { name = "boiler" },
      { name = "front_b1_grp", transf = T(7.38, 0, 0), children = { wheel("u1", -3.6, true), wheel("u2", -1.8, true), wheel("u3", 0, true), wheel("u4", 1.8, true),
        { name = "front_b1_c1_grp", transf = T(4.36, 0, 0), children = { wheel("c1", 1.1), wheel("c2", -1.1) } } } },
      { name = "front_b2_grp", transf = T(-1.4, 0, 0), children = { wheel("v1", -3.6, true), wheel("v2", -1.8, true), wheel("v3", 0, true), wheel("v4", 1.8, true),
        { name = "front_b2_c1_grp", transf = T(-6.79, 0, 0), children = { wheel("d1", 0.8), wheel("d2", -0.8) } } } } } },
    { name = "back_grp", transf = T(-12.81, 0, 0), children = { wheel("e1", 1.08), wheel("e2", -0.6), wheel("e3", -2.3), wheel("e4", -4.97),
      bogie("back_b1_grp", 3.87, "f1", "f2", 1.1) } } } } },
}, { "u1", "u2", "u3", "u4", "c1", "c2", "v1", "v2", "v3", "v4", "d1", "d2", "e1", "e2", "e3", "e4", "f1", "f2" })
-- Atlantic: a single-axle trailing truck in the body; a tender on two bogies
cases.atlantic = model({
  { node = { name = "RootNode", children = {
    { name = "front_grp", transf = T(5.6, 0, 0), children = { wheel("a1", -0.84, true), wheel("a2", 1.34, true),
      bogie("front_b1_grp", 4.65, "l1", "l2", 1.14), { name = "front_b2_grp", transf = T(-2.31, 0, 0), children = { wheel("trail", -1.52) } } } },
    { name = "back_grp", transf = T(-5.72, 0, 0), children = { bogie("back_b1_grp", 3.26, "g1", "g2", 0.89), bogie("back_b2_grp", -2.83, "g3", "g4", 0.89) } } } } },
}, { "a1", "a2", "l1", "l2", "trail", "g1", "g2", "g3", "g4" })
-- A tender modelled facing backwards (its node turned half round)
cases.backwards = model({
  { node = { name = "RootNode", children = {
    { name = "loco", children = { wheel("k1", 2), wheel("k2", -2) } },
    { name = "tender", transf = T(-8, 0, 0, math.pi), children = { wheel("m1", 2.5), wheel("m2", -2.5) } } } } },
}, { "k1", "k2", "m1", "m2" })

local TOL = 0.01
local order = { "su", "a4", "f8", "bigboy", "atlantic", "backwards" }
for _, name in ipairs(order) do
  for _, R in ipairs({ 150, -150, 80 }) do
    local res = sim.check(cases[name], R)
    for li, r in ipairs(res) do
      assert(r.count > 0, name .. " lod " .. li .. ": wheels measured")
      assert(r.worst < TOL, string.format("%s, lod %d, R = %d: wheel %s at x = %.2f is %.3f m off the track", name, li, R, tostring(r.axle), r.at or 0, r.worst))
    end
  end
  print(string.format("geometry: %-9s every wheel on 150 m (both ways) and 80 m curves", name))
end
print("parts geometry ok")
