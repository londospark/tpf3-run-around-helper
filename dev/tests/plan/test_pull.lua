-- The loco ghost during a ghost rake: stands while the hidden train is turned,
-- draws forward exactly the pull length (braking to a stop), stands for the
-- uncouple, then runs the route at its own speed.
math.atan2 = math.atan2 or math.atan
local log = {}
api = { engine = { util = { transport = { calcPosition = function(g, u) return { x = g.x0 + u * 100, y = 0, z = 0 } end } },
  getComponent = function(e, c) return { edges = { { geometry = { x0 = e * 1000 } } } } end },
  cmd = { makeCustomEntityUpdateTransformationCmd = function(e, t) log[#log + 1] = t return t end, sendCommand = function() end },
  type = { ComponentType = { TRANSPORT_NETWORK = 1 }, Vec3f = { distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end, new = function(x, y, z) return { x = x, y = y, z = z } end },
    Mat4f = { rotZTransl = function(yaw, p) return { yaw = yaw, x = p.x, y = p.y } end } } }
local M = assert(load(io.open(arg[1]):read("*a") .. "\nreturn {adv=advanceGhost,CONFIG=CONFIG}", "s"))()
local loop = { speed = 20, accel = 1, loopEdges = { { entity = 1, index = 0, forward = true }, { entity = 2, index = 0, forward = true } } }
local run = { loop = loop, edgeCursor = 1, speed = 0, ghost = 1, gdist = 0, rake = { stage = "flip" } }
for _ = 1, 10 do M.adv(run, 0.1) end
assert(run.gdist == 0 and #log == 0, "stands while the hidden train is turned")
run.rake = { stage = "pull", gdist0 = 0, pullLen = 12.8, pullTo = 12.8 }
local top, n = 0, 0
while run.gdist < 12.8 - 1e-9 do
  M.adv(run, 0.1); n = n + 1
  top = math.max(top, run.speed)
  assert(n < 2000, "pull never ends")
end
assert(math.abs(run.gdist - 12.8) < 1e-9, "drew forward exactly the pull length: " .. run.gdist)
assert(top <= M.CONFIG.rakePullSpeed + 1e-9, "pull speed capped: " .. top)
assert(run.speed <= 0.25, "braked to (nearly) a stop, speed " .. run.speed)
print(string.format("pull: %.2f m in %.1f s, top %.2f m/s", run.gdist, n * 0.1, top))
local x = log[#log].x
run.rake.stage = "uncouple"
for _ = 1, 20 do M.adv(run, 0.1) end
assert(log[#log].x == x and run.speed == 0, "stands while uncoupling")
run.rake.stage = "done"
for _ = 1, 100 do M.adv(run, 0.1) end
assert(run.speed > M.CONFIG.rakePullSpeed, "then runs the route at the loop speed: " .. run.speed)
print("pull ok")
