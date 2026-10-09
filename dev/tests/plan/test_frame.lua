-- The loco copy is placed as the game places a vehicle: on the line through
-- the track under its main part's reference points (runaround_frame, made by
-- ghost_build), not along the track at its origin; facing back, the points
-- are looked up the other way along the route. No frame, or one far off the
-- way the copy faces: left as it is.
math.atan2 = math.atan2 or math.atan
local R, LEN = 150, 300 -- one piece: a left-hand curve of radius 150 m, 300 m long, from (0, 0) along x
local function onCurve(s) local th = s / R return { x = R * math.sin(th), y = R * (1 - math.cos(th)), z = 0 } end
api = { engine = { util = { transport = { calcPosition = function(_, u) return onCurve(u * LEN) end } },
  getComponent = function() return { edges = { { geometry = {} } } } end },
  type = { ComponentType = { TRANSPORT_NETWORK = "TN" },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end,
      distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end } },
  res = { modelRep = { get = function(id) return { metadata = { transformatorConfig = { params = { runaround_frame = id == 1 and "5.3600 -4.9700" or nil } } } } end } } }
local M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn { place = framePlacement, read = readFrame, len = pieceLength }", "f"))()
local loop = { loopEdges = { { entity = 1, index = 0, forward = true } } }
-- a point d metres along the route, as the run-around finds it (by its measured length)
local k = LEN / M.len(loop.loopEdges[1])
local function at(d) return onCurve(d * k) end

assert(M.read(2) == nil, "no runaround_frame: nil")
local F = M.read(1)
assert(F and F[1] == 5.36 and F[2] == -4.97, "read from the model's parameters")

-- 100 m along the curve, facing the way of travel
local run = { edgeCursor = 1, edgeProgress = 100, frameRefs = F }
local here = at(100)
local tangent = 100 * k / R
local pos, yaw = M.place(run, loop, 1, here, tangent)
local p1, p2 = at(100 + 5.36), at(100 - 4.97)
local want = math.atan2(p1.y - p2.y, p1.x - p2.x)
assert(math.abs(yaw - want) < 1e-9, "faces along the line through the track at 5.36 and -4.97")
local f = 4.97 / (5.36 + 4.97)
assert(math.abs(pos.x - (p2.x + (p1.x - p2.x) * f)) < 1e-9 and math.abs(pos.y - (p2.y + (p1.y - p2.y) * f)) < 1e-9, "its origin on that line")
-- a few centimetres inside the curve from the track at its origin
local off = math.sqrt((pos.x - here.x) ^ 2 + (pos.y - here.y) ^ 2)
assert(off > 0.05 and off < 0.12, string.format("off the track at its origin by the chord's sag: %.3f m", off))
print(string.format("frame: on the line through its wheels, %.3f m inside the curve at its origin", off))

-- facing back (driving backwards): model +x points back along the route
local _, yawB = M.place(run, loop, -1, here, tangent + math.pi)
local q1, q2 = at(100 - 5.36), at(100 + 4.97)
assert(math.abs(math.atan2(math.sin(yawB - math.atan2(q1.y - q2.y, q1.x - q2.x)), math.cos(yawB - math.atan2(q1.y - q2.y, q1.x - q2.x)))) < 1e-9, "facing back: the points looked up the other way")

-- no frame: nothing to change
assert(M.place({ edgeCursor = 1, edgeProgress = 100 }, loop, 1, here, tangent) == nil, "no frame: left as it is")
-- a yaw far from the line's (wrong facing sign): left as it is
assert(M.place(run, loop, 1, here, tangent + math.pi) == nil, "the line the other way round: left as it is")
print("frame ok")
