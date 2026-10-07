-- M4: a coach ghost drawn forward on a curved platform follows the curve and turns
-- with it (pullFrame), keeping its own facing; on straight track it is the plain line.
math.atan2 = math.atan2 or math.atan
api = { type = {} }
local M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {pullFrame=pullFrame}", "s"))()
local function wrap(a) return math.atan2(math.sin(a), math.cos(a)) end
local function frame(x, y, yaw) return { x = x, y = y, z = 0, yaw = yaw } end

-- A coach on a 150 m radius curve, drawn 20 m along it (forwards = anticlockwise).
local R, L = 150.0, 20.0
for _, case in ipairs({ { name = "facing the travel", turnBy = 0 }, { name = "facing backwards", turnBy = math.pi } }) do
  for _, targetTurn in ipairs({ 0, math.pi }) do -- the hidden coach under the target may face either way
    local a0, a1 = 0.3, 0.3 + L / R
    local c = {
      start = frame(R * math.cos(a0), R * math.sin(a0), a0 + math.pi / 2 + case.turnBy),
      target = frame(R * math.cos(a1), R * math.sin(a1), a1 + math.pi / 2 + targetTurn),
    }
    local worst, worstYaw = 0, 0
    for i = 0, 50 do
      local x, y, _, yaw = M.pullFrame(c, i / 50)
      local r = math.sqrt(x * x + y * y)
      worst = math.max(worst, math.abs(r - R))
      local tangent = math.atan2(y, x) + math.pi / 2 + case.turnBy
      worstYaw = math.max(worstYaw, math.abs(wrap(yaw - tangent)))
    end
    assert(worst < 0.005, case.name .. ": off the curve by " .. worst .. " m")
    assert(worstYaw < math.rad(0.2), case.name .. ": not along the track, by " .. math.deg(worstYaw) .. " degrees")
    local x0, y0, _, yaw0 = M.pullFrame(c, 0)
    local x1, y1, _, yaw1 = M.pullFrame(c, 1)
    assert(math.abs(x0 - c.start.x) < 1e-9 and math.abs(y0 - c.start.y) < 1e-9 and math.abs(wrap(yaw0 - c.start.yaw)) < 1e-9, "starts exactly on its coach")
    assert(math.abs(x1 - c.target.x) < 1e-9 and math.abs(y1 - c.target.y) < 1e-9, "ends exactly over the hidden coach")
    assert(math.abs(wrap(yaw1 - (a1 + math.pi / 2 + case.turnBy))) < 1e-9, "ends turned with the track, own facing kept")
  end
  print(string.format("curve (%s): on the curve and along the track throughout", case.name))
end

-- Straight track: exactly the straight line, the yaw unchanged.
local c = { start = frame(0, 0, math.pi), target = frame(-12.8, 0, 0) } -- target coach faces the other way
for i = 0, 10 do
  local x, y, _, yaw = M.pullFrame(c, i / 10)
  assert(math.abs(x + 12.8 * i / 10) < 1e-9 and math.abs(y) < 1e-9, "straight line")
  assert(math.abs(wrap(yaw - math.pi)) < 1e-9, "no turn on straight track")
end
print("straight: the plain line, no turn")

-- A target axis that makes no sense (across the track) is not trusted: no bulge.
c = { start = frame(0, 0, 0), target = frame(15, 0, math.pi / 2) }
for i = 0, 10 do
  local _, y = M.pullFrame(c, i / 10)
  assert(math.abs(y) < 1e-9, "a target axis across the track is ignored")
end
-- No distance to go: stays put.
c = { start = frame(5, 5, 1.0), target = frame(5, 5, 1.0) }
local x, y, _, yaw = M.pullFrame(c, 0.5)
assert(x == 5 and y == 5 and yaw == 1.0)
print("curve ok")
