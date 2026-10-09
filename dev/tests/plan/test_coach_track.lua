-- The track under each coach copy (coachStrips): the platform's curve read from
-- the vehicles around each coach (their facings change along a curve by the
-- distance between them over the radius), as a strip in the copy's own frame
-- from the line through its own reference points - for ghost_real to turn its
-- bogies. Coaches facing either way; one coach; a straight platform.
math.atan2 = math.atan2 or math.atan
api = { type = { Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } } }
local M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn { strips = coachStrips }", "c"))()
local R = 150
-- a vehicle at arc length s along a left-hand curve, facing along it (or back)
local function at(s, back, coach)
  local th = s / R
  return { x = R * math.sin(th), y = R * (1 - math.cos(th)), yaw = th + (back and math.pi or 0), coach = coach }
end
local c1, c2, c3 = { frame = { 7, -7 } }, { frame = { 7, -7 } }, { frame = { 7, -7 } }
-- the loco at 0, coaches every 20 m behind it (negative s), the middle one turned round
local poses = { at(-20, false, c1), at(-60, false, c3), at(0, false, nil), at(-40, true, c2) }
M.strips(poses, at(0))
assert(math.abs(c1.curvature - 1 / R) < 1e-3 / R, "a coach facing along: the curve to its left, 1/R: " .. tostring(c1.curvature))
assert(math.abs(c2.curvature + 1 / R) < 1e-3 / R, "a coach turned round: to its right")
assert(math.abs(c3.curvature - 1 / R) < 1e-3 / R, "the last coach, from its one neighbour")
-- the strip: on the curve, from the line through the bogies at +7 and -7
for i = 1, #c1.track.pts / 2 do
  local x, y = c1.track.pts[2 * i - 1], c1.track.pts[2 * i]
  assert(math.abs(y - (x - 7) * (x + 7) / (2 * R)) < 1e-3, "on the curve at " .. x)
end
assert(c1.track.s0 == -24 and c1.track.ds == 2 and #c1.track.pts == 50, "25 points from -24 m")
-- one coach behind the loco: from the two of them
local only = { frame = { 5, -5 } }
M.strips({ at(-18, false, only), at(0) }, at(0))
assert(math.abs(only.curvature - 1 / R) < 1e-3 / R, "one coach: from it and the loco")
-- a straight platform: no curve
local s1 = { frame = { 7, -7 } }
M.strips({ { x = 0, y = 0, yaw = 0 }, { x = -20, y = 0, yaw = 0, coach = s1 } }, { x = 0, y = 0 })
for i = 1, #s1.track.pts / 2 do assert(s1.track.pts[2 * i] == 0, "straight") end
-- no frame on the coach's model: from the track's direction at its origin
local nf = {}
M.strips({ at(0), at(-20, false, nf) }, at(0))
assert(math.abs(nf.track.pts[2] - (-24) * (-24) / (2 * R)) < 1e-3, "no frame: y = k x^2 / 2")
print("coach track ok")
