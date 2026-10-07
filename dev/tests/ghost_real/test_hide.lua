-- ghost_real: a flagged real wagon is drawn as nothing; its ghost shows the wagon's load nodes.
local calls = {}
local tu = setmetatable({ colorAttributePostition = 0,
  scaleUserTransfIndicesLoadConfig = function(ind, out) calls[#calls + 1] = { "loads", ind } end,
  getEntityTime = function() return 0 end }, { __index = function() return function() end end })
api = { type = { Mat4f = { scale = function(v) return { s = v } end }, Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } } }
local env = setmetatable({ ug_require = function(p) if p:find("transformator_util") then return tu end return {} end }, { __index = _G })
assert(load(io.open(arg[1]):read("*a"), "g", "t", env))()
local fns = env.data()
local out = setmetatable({ getUserTransfs = function() return { {}, {}, {}, {}, {} } end }, { __index = function(_, k) return function(_, ...) calls[#calls + 1] = { k, ... } end end })
local function real(color, loads) return { entityId = 5, vehicleStaticInfo = { carriageEntity = 77 }, currentInfo = { world = { gameTime = 0 }, vehicle = { color = color, indicesLoadConfig = loads, doorAnimationInfo = {} },
  landVehicle = { side = 0, reversed = false, wheelAnimationInfo = { totalDist = 0 }, brakingTimer = 0 } } } end
-- normal paint: the stock update, not hidden
calls = {}
fns.train.updateFn(nil, real({ x = 0.5, y = 0.5, z = 0.5 }, { 1, 0, 1 }), out)
for _, c in ipairs(calls) do assert(c[1] ~= "setUserTransf", "a normal train must not be hidden") end
-- the flag colour: scaled to nothing, stock update skipped, loads remembered
calls = {}
fns.train.updateFn(nil, real({ x = 0.1234567, y = 0.7654321, z = 0.3141593 }, { 1, 0, 1 }), out)
assert(#calls == 5, "hidden: every node (bogies too) and nothing else, got " .. #calls)
for i, c in ipairs(calls) do assert(c[1] == "setUserTransf" and c[2] == i - 1 and c[3].s.x == 0) end
-- node count unreadable: every index until one is refused
local refused = setmetatable({ setUserTransf = function(_, i) if i > 7 then error("out of range") end calls[#calls + 1] = { "setUserTransf", i } end }, { __index = function() return function() end end })
calls = {}
fns.train.updateFn(nil, real({ x = 0.1234567, y = 0.7654321, z = 0.3141593 }, {}), refused)
assert(#calls == 8, "fallback hides indices 0..7, got " .. #calls)
fns.tiltingTrain.updateFn(nil, real({ x = 0.1234567, y = 0.7654321, z = 0.3141593 }, { 0, 1 }), out)
-- the ghost mirroring entity 77 shows its loads
fns.train.updateFn(nil, real({ x = 0.1234567, y = 0.7654321, z = 0.3141593 }, { 1, 0, 1 }), out)
calls = {}
fns.train.updateFn(nil, { entityId = 500, currentInfo = { world = { gameTime = 0 }, customState = { state = { color = { 1, 0, 0 }, mirror = 77, dir = 1 } } } }, out)
local sawLoads = false
for _, c in ipairs(calls) do if c[1] == "loads" then sawLoads = c[2][1] == 1 and c[2][2] == 0 and c[2][3] == 1 end end
assert(sawLoads, "ghost copies the hidden wagon's load nodes")
-- smoke off for a hidden real vehicle
local freq = {}
fns.train.updateParticleSystemFn(nil, real({ x = 0.1234567, y = 0.7654321, z = 0.3141593 }, {}), { getSize = function() return 2 end, setFrequencyScale = function(_, i, f) freq[i] = f end })
assert(freq[0] == 0 and freq[1] == 0)
print("hide ok")
