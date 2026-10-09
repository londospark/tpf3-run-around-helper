-- ghost_real: the copy's tender, body and pony truck are turned to the line
-- through the track under their axles, each measured from the part it's turned
-- with (the pivots are in the keyframes: see test_parts_spec and
-- test_parts_geometry); small axles turn as it rolls. The spec
-- is ghost_build's for the Black 5 (gr1m_LMSblack5, lms_stanier5_br1.mdl, full
-- detail): body 1 (driving wheels 0.83 .. -3.66), pony truck 12 in it (4.6 ..
-- 2.6), tender 29 (-6.92 .. -11.35), each with its pivot; axles 14, 15
-- (pony), 32-34 (tender).
local SPEC = "41 3 5 1 0 0.8272 -3.6627 1.0685 12 1 4.6 2.6 1.4937 29 0 -6.9152 -11.3528 -4.2975 14 0.4611 1 15 0.4611 1 32 0.5738 1 33 0.5738 1 34 0.5738 1"
math.atan2 = math.atan2 or math.atan
local tu = setmetatable({ colorAttributePostition = 0, getEntityTime = function() return 0 end },
  { __index = function() return function() end end })
api = { type = {
  Mat4f = { scale = function(v) return { s = v } end },
  Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } } }
local env = setmetatable({ ug_require = function(p) if p:find("transformator_util") then return tu end return {} end }, { __index = _G })
assert(load(io.open(arg[1]):read("*a"), "g", "t", env))()
local fns = env.data()
-- a free entity: no user transforms; its animations are what can be played
local played, wrote = {}, 0
local out = setmetatable({
  getUserTransfs = function() return {} end,
  setUserTransf = function() wrote = wrote + 1 end,
  addAnimationState = function(_, name, start, param, loop, rev) played[name] = { start = start, param = param, loop = loop, rev = rev } end,
}, { __index = function() return function() end end })

-- a left-hand curve of radius 150 m, the copy's origin on it, facing along it
local R = 150
local pts = {}
for x = -16, 16, 2 do local th = x / R; pts[#pts + 1] = R * math.sin(th); pts[#pts + 1] = R * (1 - math.cos(th)) end
local function ghost(params, dist, withTrack)
  return { entityId = 500, transformatorConfigParams = params,
    currentInfo = { world = { gameTime = 0 }, customState = { state = { dist = dist, dir = 1, track = withTrack ~= false and { s0 = -16, ds = 2, pts = pts } or nil } } } }
end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-3) end
local function chord(a, b) -- the track's direction between model x = a and b
  local function at(x) local th = x / R; return R * math.sin(th), R * (1 - math.cos(th)) end
  local ax, ay = at(a); local bx, by = at(b)
  return math.atan2(ay - by, ax - bx)
end
local function yawOf(name) return (played[name].param - 1) / 100 - 30 end -- degrees (frame 0 is no turn)

fns.train.updateFn(nil, ghost({ runaround_parts1 = SPEC }, 2.0), out)
assert(wrote == 0, "no user transforms written on a copy")
-- parts in the spec's order: 1 the body, 2 the pony truck in it, 3 the tender
local tender = yawOf("runaround_yaw3")
print(string.format("tender turned %.2f degrees (track under its wheels: %.2f)", tender, math.deg(chord(-6.9152, -11.3528))))
assert(near(tender, math.deg(chord(-6.9152, -11.3528)), 0.02) and tender < -2, "tender follows the curve")
assert(played["runaround_yaw3"].start == -1 and played["runaround_yaw3"].loop == false, "a set frame, not looped")
local body = yawOf("runaround_yaw1")
print(string.format("body %.3f (track %.3f), pony %.3f (track %.3f)", body, math.deg(chord(0.8272, -3.6627)), body + yawOf("runaround_yaw2"), math.deg(chord(4.6, 2.6))))
assert(near(body, math.deg(chord(0.8272, -3.6627)), 0.02), "body by its driving wheels")
assert(near(body + yawOf("runaround_yaw2"), math.deg(chord(4.6, 2.6)), 0.02), "pony truck follows the track, measured from the body")
-- axles: a turn over 3600 ms, by the distance rolled over the radius
local spin = played["runaround_spin1"]
assert(spin.loop == true and near(spin.param, (math.deg(2.0 / 0.4611) + 360000) * 10, 0.01), "pony axle turned by 2 m / 0.4611 m")
assert(played["runaround_spin5"] and not played["runaround_spin6"], "5 small axles (pony 2, tender 3), not the driving wheels")
-- going backwards: the axles turn back (the frame goes down)
played = {}
local back = ghost({ runaround_parts1 = SPEC }, 2.0)
back.currentInfo.customState.state.dir = -1
fns.train.updateFn(nil, back, out)
assert(played["runaround_spin1"].param < 360000 * 10, "backwards: turned back")
-- a sharp curve: the turn is held at 30 degrees
-- no track yet: the axles turn, the parts are left as they are
played = {}
fns.train.updateFn(nil, ghost({ runaround_parts1 = SPEC }, 2.0, false), out)
assert(played["runaround_spin1"] and not played["runaround_yaw1"], "no track: only the axles")
-- no spec: nothing
played = {}
fns.train.updateFn(nil, ghost(nil, 2.0), out)
for name in pairs(played) do assert(not name:find("^runaround_"), "no spec: nothing played") end
print("parts ok")
