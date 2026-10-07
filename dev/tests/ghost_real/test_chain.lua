-- ghost_real chain: a vehicle with another mod's transformator (devers, say). A real
-- train gets the original, found from the params; a hidden one is drawn as nothing;
-- a ghost gets ours; an original that can't be found falls back to the stock one.
local calls = {}
local tu = setmetatable({ colorAttributePostition = 0,
  getEntityTime = function() return 0 end,
  addDriveAnimationState = function() calls[#calls + 1] = { "stock" } end,
  updateParticleSystemFn = function() calls[#calls + 1] = { "stockParticles" } end },
  { __index = function() return function() end end })
api = { type = { Mat4f = { scale = function(v) return { s = v } end }, Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } } }
local env, printed, required = nil, {}, {}
-- the other mod's files, as ug_require would run them: a .trf defines a global data()
local files = {
  ["devers_1::/vehicle/train/devers/devers_train.trf.lua"] = function()
    env.data = function() return {
      updateScript = { fileName = "devers_train.script@train.updateFn", params = { roll = 1 } },
      updateParticleSystemScript = { fileName = "devers_train.script@train.updateParticleSystemFn", params = {} },
    } end
  end,
  ["devers_1::/vehicle/train/devers/devers_train.script.lua"] = function()
    return { train = {
      updateFn = function(capture, params, _out) calls[#calls + 1] = { "origin", capture.roll, params.transformatorConfigParams.devers_trf } end,
      updateParticleSystemFn = function() calls[#calls + 1] = { "originParticles" } end,
    } }
  end,
}
env = setmetatable({
  ug_require = function(p)
    if p:find("transformator_util") then return tu end
    required[p] = (required[p] or 0) + 1
    local f = files[p]
    if f == nil then error("module not found: " .. p) end
    return f()
  end,
  print = function(m) printed[#printed + 1] = m end,
}, { __index = _G })
assert(load(io.open(arg[1]):read("*a"), "g", "t", env))()
local fns = env.data()
local out = setmetatable({ getUserTransfs = function() return { {}, {}, {} } end },
  { __index = function(_, k) return function(_, ...) calls[#calls + 1] = { k, ... } end end })
local function real(trf, color)
  return { entityId = 5, vehicleStaticInfo = { carriageEntity = 77 },
    transformatorConfigParams = { runaround_trf = trf, runaround_mdl = "::/vehicle/train/br89/br89.mdl", devers_trf = "kept" },
    currentInfo = { world = { gameTime = 0 }, vehicle = { color = color or { x = 0.5, y = 0.5, z = 0.5 }, indicesLoadConfig = {}, doorAnimationInfo = {} },
      landVehicle = { side = 0, reversed = false, wheelAnimationInfo = { totalDist = 0 }, brakingTimer = 0 } } }
end
local DEVERS = "devers_1::/vehicle/train/devers/devers_train.trf"

-- a real train: the original, with its own capture params and the vehicle's params
calls = {}
fns.chain.updateFn(nil, real(DEVERS), out)
assert(#calls == 1 and calls[1][1] == "origin" and calls[1][2] == 1 and calls[1][3] == "kept", "the original transformator is called")
assert(type(env.data) == "function" and env.data().chain ~= nil, "our own data() is put back after loading the .trf")
-- found once, then cached
fns.chain.updateFn(nil, real(DEVERS), out)
assert(required["devers_1::/vehicle/train/devers/devers_train.trf.lua"] == 1, "the .trf is loaded once")
print("chain: real train -> the other mod's transformator, its params kept")

-- hidden: nothing drawn, the original not called
calls = {}
fns.chain.updateFn(nil, real(DEVERS, { x = 0.1234567, y = 0.7654321, z = 0.3141593 }), out)
for _, c in ipairs(calls) do assert(c[1] == "setUserTransf", "hidden: only scaled to nothing, got " .. c[1]) end
assert(#calls == 3, "every node hidden")
print("chain: hidden coach -> drawn as nothing")

-- a ghost (free entity): ours, not the original
calls = {}
fns.chain.updateFn(nil, { entityId = 500, currentInfo = { world = { gameTime = 0 }, customState = { state = { color = { 1, 0, 0 }, dir = 1 } } } }, out)
for _, c in ipairs(calls) do assert(c[1] ~= "origin", "a ghost does not call the original") end
print("chain: ghost -> ours")

-- particles: the original's
calls = {}
fns.chain.updateParticleSystemFn(nil, real(DEVERS), { getSize = function() return 0 end })
assert(calls[1] and calls[1][1] == "originParticles", "the original's smoke")

-- an original that can't be found: the stock animation, said once
calls, printed = {}, {}
fns.chain.updateFn(nil, real("gone_1::/vehicle/x/missing.trf"), out)
fns.chain.updateFn(nil, real("gone_1::/vehicle/x/missing.trf"), out)
local stock = 0 for _, c in ipairs(calls) do if c[1] == "stock" then stock = stock + 1 end end
assert(stock == 2, "falls back to the stock animation")
assert(#printed == 1 and printed[1]:find("chained transformator not found", 1, true), "said once")
print("chain: missing original -> stock animation, logged once")
print("chain ok")
