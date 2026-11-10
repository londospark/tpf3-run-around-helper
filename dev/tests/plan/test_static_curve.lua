math.atan2 = math.atan2 or math.atan
-- Static coaches on a curved platform: where the loco copy couples on. The
-- hidden train stands a loco length short of its copies; the loco will be that
-- far further on ALONG THE CURVE, not along a straight line from the coaches.
local R = 150
local function at(s, turned) return { x = R * math.sin(s / R), y = R * (1 - math.cos(s / R)), yaw = s / R + (turned and math.pi or 0) } end
local frames = {}
api = {
  engine = { getComponent = function(e, c)
      if c == "CL" then local cs = {} for i = 1, #frames do cs[i] = i end return { carriages = cs } end
      if c == "MIL" then local f = frames[e]
        return { fatInstances = { { modelId = f.m, transf = { cols = function(_, k) if k == 3 then return { x = f.x, y = f.y, z = 0 } end return { x = math.cos(f.yaw), y = math.sin(f.yaw) } end } } } } end
      if c == "GT" then return { gameTime = 0 } end end,
    util = { getWorld = function() return 1 end } },
  type = { ComponentType = { CARRIAGE_LIST = "CL", MODEL_INSTANCE_LIST = "MIL", GAME_TIME = "GT" },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }, Mat4f = { rotZTransl = function() return {} end } },
  cmd = { sendCommand = function() end, makeCustomEntityUpdateStateCmd = function() return {} end, makeCustomEntityUpdateTransformationCmd = function() return {} end },
}
local log = {}
local M = assert(load("local print = function(...) end\n" .. io.open(arg[1]):read("*a") .. "\nreturn {adv=advanceRake, place=placeTarget}", "s"))()
local L, C = 12.8, 20.0
for _, turned in ipairs({ false, true }) do
  -- arrival: the loco at the buffer end, three coaches behind it
  local start = { at(L + C / 2), at(L + C * 1.5), at(L + C * 2.5) }
  -- hidden and turned: the coaches a loco length nearer the buffers, the loco beyond them
  frames = { at(3 * C + L / 2), at(C * 2.5, turned), at(C * 1.5, turned), at(C / 2, turned) }
  frames[1].m = 1; for i = 2, 4 do frames[i].m = 7 end
  local coaches = {}
  for i = 1, 3 do coaches[i] = { snap = { modelId = 7 }, start = { x = start[i].x, y = start[i].y, z = 0, yaw = start[i].yaw + (turned and math.pi or 0) }, ghost = 100 + i } end
  local run = { vehicleEntity = 1, locoPart = { modelId = 1 }, locoPos = at(L / 2), gyaw = frames[1].yaw, gdist = 0,
    rake = { stage = "settle", ticks = 3, static = true, coaches = coaches } }
  M.adv(run, 0.1)
  assert(run.rake.stage == "uncouple", "no pull: straight to the uncouple, got " .. run.rake.stage)
  assert(math.abs(run.rake.pullLen - 2 * R * math.sin(L / (2 * R))) < 1e-6, "a loco length (its chord) short")
  M.place(run)
  local want = at(3 * C + L / 2 + L)
  local off = math.sqrt((run.target.x - want.x) ^ 2 + (run.target.y - want.y) ^ 2)
  -- a straight shift by the last coach's move would miss by this much
  local dx, dy = coaches[3].start.x - coaches[3].hidden.x, coaches[3].start.y - coaches[3].hidden.y
  local naive = math.sqrt((frames[1].x + dx - want.x) ^ 2 + (frames[1].y + dy - want.y) ^ 2)
  io.write(string.format("150 m curve, coaches %s: coupling place %.3f m from the loco's true place (a straight shift: %.2f m)\n", turned and "turned" or "as they came", off, naive))
  assert(off < 0.02, "on the curve")
  assert(naive > 1.0, "(the test would not tell the difference)")
end
io.write("static curve ok\n")
