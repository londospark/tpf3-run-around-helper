-- Offline check of the loco copy's tender and bogies: how far each wheel ends
-- up from the rails on a curve. It runs the mod's own code: ghost_build's
-- load step (partsAtLoad: the parts spec and the animations), then
-- ghost_real's copy update on a curve (which animation frames it plays), then
-- draws the model's node tree with those frames as the engine does
-- (node = parent * rest * animation, keyframes interpolated) and measures each
-- axle's distance from the track's centre line.
--
-- As a module (dev/tests use it): local sim = dofile("parts_sim.lua")
--   sim.load(ghostBuildPath, ghostRealPath)
--   sim.check(model, R) -> { [lod] = { worst = metres, axle = name, sag = metres, ... } }
-- From the command line, on model files (the game's or a mod's):
--   lua dev/tools/parts_sim.lua ghost_build.script.lua res/scripts/ghost_real.script.lua R model.mdl...
local sim = {}

local function deepcopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local o = {}
  seen[t] = o
  for k, v in pairs(t) do o[deepcopy(k, seen)] = deepcopy(v, seen) end
  return o
end

-- 4x4 column-major matrices
local I = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
local function mul(a, b)
  local o = {}
  for c = 0, 3 do
    for r = 1, 4 do
      local s = 0
      for k = 0, 3 do s = s + a[k * 4 + r] * b[c * 4 + k + 1] end
      o[c * 4 + r] = s
    end
  end
  return o
end
local function frameOf(ani, t)
  local k = ani.params.keyframes
  if t <= k[1].time then return k[1].transf end
  for i = 2, #k do
    if t <= k[i].time then
      local f = (t - k[i - 1].time) / (k[i].time - k[i - 1].time)
      local o = {}
      for j = 1, 16 do o[j] = k[i - 1].transf[j] * (1 - f) + k[i].transf[j] * f end
      return o
    end
  end
  return k[#k].transf
end

local build, real
function sim.load(buildPath, realPath)
  _G.api = { res = { modelRep = {} }, type = {} }
  build = assert(load(io.open(buildPath):read("*a") .. "\nreturn { partsAtLoad = partsAtLoad }", "gb"))()
  local tu = setmetatable({ colorAttributePostition = 0, getEntityTime = function() return 0 end },
    { __index = function() return function() end end })
  _G.api = { type = {
    Mat4f = { scale = function(v) return { s = v } end },
    Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } } }
  local env = setmetatable({ print = function() end,
    ug_require = function(p) if p:find("transformator_util") then return tu end return {} end }, { __index = _G })
  assert(load(io.open(realPath):read("*a"), "gr", "t", env))()
  real = env.data()
end

-- Points every 2 m from -24 to +24 m, as the run-around sends them, on a
-- curve of radius R (left for R > 0) through the copy's origin along x.
-- The track: a curve of radius R (a number), or any shape given as a table
-- { at = function(s) -> x, y (arc length s from the copy's origin, along x
-- there), dist = function(x, y) -> distance from the centre line }.
local function circle(R)
  return { at = function(s) local th = s / R return R * math.sin(th), R * (1 - math.cos(th)) end,
    dist = function(x, y) return math.abs(math.sqrt(x * x + (y - R) ^ 2) - math.abs(R)) end, R = R }
end
-- a shape given by its curvature k(s): integrated finely; distance by the nearest point
function sim.track(k, R)
  local ds, pts = 0.01, {}
  local function run(dir)
    local x, y, th, s = 0, 0, 0, 0
    pts[0] = { 0, 0 }
    for i = 1, 3000 do
      local ks = k(s + dir * ds / 2)
      th = th + dir * ks * ds
      x, y = x + dir * math.cos(th) * ds, y + dir * math.sin(th) * ds
      s = s + dir * ds
      pts[dir * i] = { x, y }
    end
  end
  run(1) run(-1)
  return { R = R, at = function(s) local i = math.floor(s / ds + 0.5) return pts[i][1], pts[i][2] end,
    dist = function(x, y)
      local best = math.huge
      for i = -3000, 3000 do local p = pts[i] local d = (p[1] - x) ^ 2 + (p[2] - y) ^ 2 if d < best then best = d end end
      return math.sqrt(best)
    end }
end
-- Where the run-around puts the copy (runaround.script.lua, framePlacement):
-- on the line through the track under runaround_frame's two points, else
-- along the track at its origin. As { c, s, x, y }: model -> world.
local function placement(tk, params)
  local a, b = nil, nil
  if params and type(params.runaround_frame) == "string" then a, b = params.runaround_frame:match("^(%S+) (%S+)$") end
  a, b = tonumber(a), tonumber(b)
  if a == nil or b == nil or a - b < 0.5 then return { 1, 0, 0, 0 } end
  local x1, y1 = tk.at(a)
  local x2, y2 = tk.at(b)
  local yaw = (math.atan2 or math.atan)(y1 - y2, x1 - x2)
  local f = -b / (a - b)
  return { math.cos(yaw), math.sin(yaw), x2 + (x1 - x2) * f, y2 + (y1 - y2) * f }
end
local function strip(tk, q)
  local pts = {}
  for x = -24, 24, 2 do
    local px, py = tk.at(x)
    local dx, dy = px - q[3], py - q[4]
    pts[#pts + 1] = q[1] * dx + q[2] * dy
    pts[#pts + 1] = -q[2] * dx + q[1] * dy
  end
  return { s0 = -24, ds = 2, pts = pts }
end

-- The animation frames the copy plays on a curve of radius R.
local function framesOn(model, tk, q)
  local tc = model.metadata.transformatorConfig
  local played = {}
  local out = setmetatable({
    getUserTransfs = function() return {} end,
    addAnimationState = function(_, name, _, param) played[name] = param end,
  }, { __index = function() return function() end end })
  real.train.updateFn(nil, { entityId = 1, transformatorConfigParams = tc.params,
    currentInfo = { world = { gameTime = 0 }, customState = { state = { dist = 0, dir = 1, track = strip(tk, q) } } } }, out)
  return played
end

-- model: a model table as a .mdl's data() gives it. Returns per level of
-- detail the worst wheel's distance from the track's centre line beyond what
-- its rigid part can't help: a part's own wheels can't all touch a curve (a
-- wheel at x between the part's outermost a and b lies (x - a)(b - x) / 2R
-- inside the line through them; a wheel on the copy's own frame, x^2 / 2R off
-- the track, as the frame lies along the track at its origin). Wheels are the
-- axles named in the config; on a far level of detail, the fake bogie points.
function sim.check(model, R)
  local tk = type(R) == "table" and R or circle(R)
  R = tk.R or 1e9
  local m = deepcopy(model)
  build.partsAtLoad("model.mdl", m)
  local q = placement(tk, m.metadata.transformatorConfig.params)
  local played = framesOn(m, tk, q)
  local rv = m.metadata.railVehicle
  local results = {}
  for li, lod in ipairs(m.lods or {}) do
    local cfg = rv.configs and rv.configs[li] or rv.config or {}
    local axleNames = {}
    for _, n in ipairs(cfg.axles or {}) do axleNames[n] = true end
    local fakes = cfg.fakeBogies
    if type(fakes) == "table" and type(fakes[1]) == "table" and fakes[1].group == nil then fakes = fakes[li] end
    local fakeAt = {}
    for _, fb in ipairs(type(fakes) == "table" and fakes or {}) do
      if type(fb) == "table" and fb.group then fakeAt[fb.group] = fakeAt[fb.group] or {} table.insert(fakeAt[fb.group], fb.position) end
    end
    local res = { worst = 0, axle = nil, count = 0, turned = 0 }
    local wheels = {} -- { name, x (rest, model), wx, wy (drawn), part }
    local function walk(node, parentM, parentRest, part)
      local t = node.transf or I
      local M, Rm = mul(parentM, t), mul(parentRest, t)
      for name, ani in pairs(node.animations or {}) do
        if type(name) == "string" and name:find("^runaround_yaw") and played[name] then
          M = mul(M, frameOf(ani, played[name]))
          res.turned = res.turned + 1
          part = node
        end
      end
      if type(node.name) == "string" and axleNames[node.name] then
        wheels[#wheels + 1] = { name = node.name, x = Rm[13], wx = M[13], wy = M[14], part = part }
      end
      for _, pos in ipairs(type(node.name) == "string" and fakeAt[node.name] or {}) do
        -- the fake bogie point is in model coordinates: back into the node's, then drawn
        local c, s_ = Rm[1], Rm[2]
        local dx, dy = pos - Rm[13], -Rm[14]
        local lx, ly = c * dx + s_ * dy, -s_ * dx + c * dy
        wheels[#wheels + 1] = { name = node.name .. "@" .. pos, x = pos,
          wx = M[1] * lx + M[5] * ly + M[13], wy = M[2] * lx + M[6] * ly + M[14], part = node, fake = true }
      end
      for _, c in ipairs(node.children or {}) do walk(c, M, Rm, part) end
    end
    walk(lod.node, I, I, "frame")
    local span = {}
    for _, w in ipairs(wheels) do
      local sp = span[w.part] or { a = -math.huge, b = math.huge }
      sp.a, sp.b = math.max(sp.a, w.x), math.min(sp.b, w.x)
      span[w.part] = sp
    end
    for _, w in ipairs(wheels) do
      local err = tk.dist(q[1] * w.wx - q[2] * w.wy + q[3], q[2] * w.wx + q[1] * w.wy + q[4])
      local sp = span[w.part]
      local sag = math.abs((w.x - sp.a) * (sp.b - w.x)) / (2 * math.abs(R))
      if w.part == "frame" then sag = math.max(sag, w.x * w.x / (2 * math.abs(R))) end
      local excess = math.max(0, err - sag)
      w.err, w.sag, w.excess = err, sag, excess
      res.count = res.count + 1
      if excess > res.worst then res.worst, res.axle, res.at, res.err = excess, w.name, w.x, err end
    end
    res.wheels = wheels
    results[li] = res
  end
  return results, played
end

-- a model file's environment: the game's helpers it may call stand in as
-- harmless stubs (strings when concatenated, tables when indexed)
local function stub()
  return setmetatable({}, { __index = function() return stub() end, __call = function() return stub() end,
    __concat = function(a, b) return tostring(type(a) == "table" and "" or a) .. tostring(type(b) == "table" and "" or b) end })
end
function sim.loadModel(path)
  local env = setmetatable({}, { __index = function(_, k) if _G[k] ~= nil then return _G[k] end return stub() end })
  local f = loadfile(path, "t", env)
  if not f or not pcall(f) or type(env.data) ~= "function" then return nil end
  local ok, d = pcall(env.data)
  if ok and type(d) == "table" and type(d.metadata) == "table" and type(d.metadata.railVehicle) == "table" and type(d.lods) == "table" then return d end
  return nil
end

if arg and arg[0] and arg[0]:find("parts_sim") then
  sim.load(arg[1], arg[2])
  local R = tonumber(arg[3])
  local skipped = 0
  for i = 4, #arg do
    local d = sim.loadModel(arg[i])
    local ok, res = false, nil
    if d then ok, res = pcall(sim.check, d, R) end
    if ok then
      local parts = {}
      for li, r in ipairs(res) do
        parts[#parts + 1] = string.format("lod%d %.3f m%s (%d wheels, %d turned)", li, r.worst,
          r.axle and string.format(" at %s x=%.1f", r.axle, r.at) or "", r.count, r.turned)
      end
      print(arg[i]:match("[^/]+$") .. ": " .. table.concat(parts, "; "))
    else
      skipped = skipped + 1
      if d then print(arg[i]:match("[^/]+$") .. ": ERROR " .. tostring(res)) end
    end
  end
  if skipped > 0 then print(skipped .. " file(s) not a readable rail vehicle, or failed") end
end
return sim
