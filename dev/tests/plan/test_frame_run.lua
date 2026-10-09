-- A whole run on a curve, the copy placed on its reference points' line
-- (runaround_frame): no tick may move it more than its speed allows, or turn
-- it more than the curve does - not where it sets off, not at the reversal
-- (where the points are looked up the other way along the route), not into
-- the final glide. And it ends where the run without the placement ends.
math.atan2 = math.atan2 or math.atan
local R = 150
local function onCurve(s) local th = s / R return { x = 1000 + R * math.sin(th), y = R * (1 - math.cos(th)), z = 0 } end
local sent = {}
api = { engine = { util = { transport = { calcPosition = function(_, u) return onCurve(u * 100) end } },
  getComponent = function(_, c) if c == "TN" then return { edges = { { geometry = {} } } } end end },
  cmd = { makeCustomEntityUpdateTransformationCmd = function(_, t) sent[#sent + 1] = t return t end, sendCommand = function() end,
    makeCustomEntityUpdateStateCmd = function() return {} end },
  type = { ComponentType = { TRANSPORT_NETWORK = "TN" },
    Vec3f = { distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end, new = function(x, y, z) return { x = x, y = y, z = z } end },
    Mat4f = { rotZTransl = function(yaw, p) return { yaw = yaw, x = p.x, y = p.y } end } } }
local src = io.open(arg[1]):read("*a"):gsub("local function logInfo%(", "local function logInfo_unused(", 1)
local M = assert(load("local logInfo = function() end\n" .. src .. "\nreturn {adv=advanceGhost}", "s"))()

-- the route drives 60 m along the curve, reverses and sets back to the coaches, 6 m in
local function newRun(frame)
  local loop = { speed = 10, accel = 1, backFrom = 2, loopEdges = { { entity = 1, index = 0, forward = true }, { entity = 1, index = 0, forward = false, reversal = true } } }
  return { loop = loop, edgeCursor = 1, speed = 0, ghost = 1, locoYaw = 0, vehicleEntity = 5, effects = true,
    rake = { stage = "done" }, target = onCurve(6), frameRefs = frame }
end
local function angle(a) return math.atan2(math.sin(a), math.cos(a)) end
local function drive(run, label)
  sent = {}
  for _ = 1, 20000 do if M.adv(run, 0.05) then break end end
  assert(#sent > 100, label .. ": moved")
  local maxStep, maxTurn = 0, 0
  for i = 2, #sent do
    local a, b = sent[i - 1], sent[i]
    maxStep = math.max(maxStep, math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2))
    maxTurn = math.max(maxTurn, math.abs(angle(b.yaw - a.yaw)))
  end
  -- at 10 m/s and 0.05 s a tick: 0.5 m; the curve turns 0.5 / 150 rad over that
  assert(maxStep < 0.55, string.format("%s: a jump of %.3f m in one tick", label, maxStep))
  assert(maxTurn < 0.5 / R * 1.5 + 1e-6, string.format("%s: a turn of %.4f rad in one tick", label, maxTurn))
  -- how far inside the curve it ran, on each leg (before and after the reversal)
  local inside = { 0, 0 }
  local leg = 1
  for i = 2, #sent do
    if sent[i].x < sent[i - 1].x - 1e-6 then leg = 2 end -- (setting back after the reversal)
    local d = R - math.sqrt((sent[i].x - 1000) ^ 2 + (sent[i].y - R) ^ 2)
    inside[leg] = math.max(inside[leg], d)
  end
  return sent[#sent], maxStep, maxTurn, inside
end
local plain, _, _, inPlain = drive(newRun(nil), "along the track")
local framed, step, turn, inFramed = drive(newRun({ 5.36, -4.97 }), "on its wheels' line")
-- on its wheels' line, the origin is that line's sag inside the curve: (5.36 x 4.97) / 2R
local sag = 5.36 * 4.97 / (2 * R)
assert(inPlain[1] < 0.005, "without it: on the track")
assert(math.abs(inFramed[1] - sag) < 0.01 and math.abs(inFramed[2] - sag) < 0.01,
  string.format("on its wheels' line both ways: %.3f and %.3f m inside the curve (%.3f)", inFramed[1], inFramed[2], sag))
print(string.format("frame run: largest step %.3f m, turn %.5f rad a tick; ends %.3f m from the run without it", step, turn,
  math.sqrt((plain.x - framed.x) ^ 2 + (plain.y - framed.y) ^ 2)))
-- both glide onto the same coupling place at the end
assert(math.sqrt((plain.x - framed.x) ^ 2 + (plain.y - framed.y) ^ 2) < 1e-6, "ends at the coupling place either way")
assert(math.abs(angle(plain.yaw - framed.yaw)) < 0.01, "facing the same way at the end")
print("frame run ok")
