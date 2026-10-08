-- ghost_real: the copy's tender, body and pony truck are turned to follow the
-- track under their axles, centres kept; small axles turn as it rolls. The spec
-- is ghost_build's for the Black 5 (gr1m_LMSblack5, lms_stanier5_br1.mdl, full
-- detail): body 1 (driving wheels 0.83 .. -3.66), pony truck 12 in it (4.6 ..
-- 2.6), tender 29 (-6.92 .. -11.35); axles 14, 15 (pony), 32-34 (tender).
local SPEC = "41 3 5 1 0 0.0 0.0 0 0.0 0 0 0 0.0 0.0 0.0 0 0.0 0.8272 -3.6627 12 1 3.6000 0.0 0 0.0 3.6000 0 0 0.0 0.0 0.0 0 0.0 4.6000 2.6000 29 0 -9.1485 0.0 0 0.0 -9.1485 0 0 0.0 0.0 0.0 0 0.0 -6.9152 -11.3528 14 0.4611 1 15 0.4611 1 32 0.5738 1 33 0.5738 1 34 0.5738 1"
math.atan2 = math.atan2 or math.atan
local tu = setmetatable({ colorAttributePostition = 0, getEntityTime = function() return 0 end },
  { __index = function() return function() end end })
api = { type = {
  Mat4f = { scale = function(v) return { s = v } end,
    rotZTransl = function(yaw, p) return { yaw = yaw, x = p.x, y = p.y, z = p.z } end,
    new = function(a, b, c, d) return { cols = { a, b, c, d } } end,
    cols = function(m, j) return m.cols[j + 1] end },
  Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
  Vec4f = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end } } }
local env = setmetatable({ ug_require = function(p) if p:find("transformator_util") then return tu end return {} end }, { __index = _G })
assert(load(io.open(arg[1]):read("*a"), "g", "t", env))()
local fns = env.data()
local set = {}
local list = {} for i = 1, 41 do list[i] = { type = 1 } end
local out = setmetatable({
  getUserTransfs = function() return list end,
  setUserTransf = function(_, i, m, abs) set[i] = { m = m, abs = abs }; if list[i + 1] then list[i + 1].transf = m end end,
}, { __index = function() return function() end end })

-- a left-hand curve of radius 150 m, the copy's origin on it, facing along it
local R = 150
local pts = {}
for x = -16, 16, 2 do local th = x / R; pts[#pts + 1] = R * math.sin(th); pts[#pts + 1] = R * (1 - math.cos(th)) end
local function ghost(params, dist)
  return { entityId = 500, transformatorConfigParams = params,
    currentInfo = { world = { gameTime = 0 }, customState = { state = { dist = dist, dir = 1, track = { s0 = -16, ds = 2, pts = pts } } } } }
end
fns.train.updateFn(nil, ghost({ runaround_parts1 = SPEC }, 2.0), out)
assert(set[0] and list[1].transf == nil, "the index measurement puts back what it wrote")

local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-3) end
local function chord(a, b) -- the track's direction between model x = a and b
  local function at(x) local th = x / R; return R * math.sin(th), R * (1 - math.cos(th)) end
  local ax, ay = at(a); local bx, by = at(b)
  return math.atan2(ay - by, ax - bx)
end
-- the tender: turned about its own centre to the track under its wheels
local t = set[29]
assert(t and t.abs == false, "tender placed, relative to its parent")
print(string.format("tender turned %.2f degrees (track under its wheels: %.2f)", math.deg(t.m.yaw), math.deg(chord(-6.9152, -11.3528))))
assert(near(t.m.yaw, chord(-6.9152, -11.3528), 1e-3) and t.m.yaw < -0.04, "tender follows the curve")
assert(near(t.m.x, 0) and near(t.m.y, 0), "tender centre stays where it is on the loco")
-- the body by its driving wheels, and the pony truck inside it: its centre stays
-- at 3.6 m on the loco, turned to the track under its wheels
local b, p = set[1], set[12]
assert(near(b.m.yaw, chord(0.8272, -3.6627)), "body by its driving wheels")
local yb = b.m.yaw
local ux, uy = math.cos(yb) * (3.6 + p.m.x) - math.sin(yb) * p.m.y, math.sin(yb) * (3.6 + p.m.x) + math.cos(yb) * p.m.y
assert(near(ux, 3.6) and near(uy, 0), string.format("pony truck centre kept at 3.6, 0 (got %.4f, %.4f)", ux, uy))
assert(near(yb + p.m.yaw, chord(4.6, 2.6)), "pony truck follows the track under its wheels")
-- small axles turn by the distance rolled over their radius; the driving wheels are left to their animation
local a = set[14]
local phi = math.atan2(-a.m.cols[1].z, a.m.cols[1].x)
assert(near(phi, 2.0 / 0.4611 - 2 * math.pi, 1e-3) or near(phi, 2.0 / 0.4611, 1e-3), "pony axle turned by 2 m / 0.4611 m, got " .. phi)
assert(set[32] and set[33] and set[34] and not set[26] and not set[27] and not set[28], "tender axles turn, driving wheels don't")
-- other levels of detail, or no spec: nothing placed
set = {}
list = {} for i = 1, 33 do list[i] = { type = 1 } end
fns.train.updateFn(nil, ghost({ runaround_parts1 = SPEC }, 2.0), out)
assert(next(set) == nil, "a level of detail with another node count is left alone")
fns.train.updateFn(nil, ghost(nil, 2.0), out)
assert(next(set) == nil, "no spec: nothing placed")
print("parts ok")
