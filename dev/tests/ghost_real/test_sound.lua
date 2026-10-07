-- ghost_real sound: a hidden real loco is silent, but still gives the game one
-- track per track of its sound set every frame (live crash: returning without
-- any tracks failed AudioEmitterBackend's "trackSrcs.size() == tracks.size()").
local stock = function(_capture, _params, out)
  out:addEvent("chuffs", 0.8, 1.0)
  out:addTrack(0.7, 1.0)   -- idle
  out:addTrack(0.3, 1.2)   -- fast
  out:addTrack(0.5, 0.9)   -- squeal
  out:triggerEvent("horn", 1.0, 1.0)
end
local tu = setmetatable({}, { __index = function() return function() end end })
api = { type = { Mat4f = { scale = function() return {} end }, Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end } } }
local env = setmetatable({ ug_require = function(p)
    if p:find("transformator_util") then return tu end
    if p:find("soundset_default") then return { updateSoundSet = stock } end
    return {}
  end }, { __index = _G })
assert(load(io.open(arg[1]):read("*a"), "g", "t", env))()
local snd = env.data().sound.updateSoundSet
local function output()
  local o = { tracks = {}, events = {}, triggered = {} }
  function o:addTrack(g, p) self.tracks[#self.tracks + 1] = { g, p } end
  function o:addEvent(k, g, p) self.events[#self.events + 1] = { k, g, p } end
  function o:triggerEvent(k) self.triggered[#self.triggered + 1] = k end
  return o
end
local HIDE = { x = 0.1234567, y = 0.7654321, z = 0.3141593 }

-- a normal train: the game's own sound
local out = output()
snd(nil, { currentInfo = { vehicle = { speed = 5, color = { x = 0.5, y = 0.5, z = 0.5 } } } }, out)
assert(#out.tracks == 3 and out.tracks[1][1] == 0.7 and #out.triggered == 1, "a normal train sounds as the game's own")

-- a hidden real loco: the same tracks, all at zero gain; no horn
out = output()
snd(nil, { currentInfo = { vehicle = { speed = 0, color = HIDE } } }, out)
assert(#out.tracks == 3, "one track per track of the sound set, got " .. #out.tracks)
for i, t in ipairs(out.tracks) do assert(t[1] == 0.0, "track " .. i .. " silent") end
assert(out.tracks[2][2] == 1.2, "pitch passed on")
assert(#out.events == 1 and out.events[1][2] == 0.0, "continuous events silent")
assert(#out.triggered == 0, "no one-off events (horn)")
print("sound: hidden loco silent, track count kept")
print("sound ok")
