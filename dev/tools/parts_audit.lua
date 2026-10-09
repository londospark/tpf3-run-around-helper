-- Audit of what ghost_build's load step (partsAtLoad) does to models, on model
-- files (the game's or mods'). For each: the model after the step must be the
-- model before plus only our animations (runaround_*) and parameters - no node
-- added, removed, renamed or moved, no animation of its own changed, at most
-- one turn and one spin per node - so real trains are drawn as before. Also:
-- which levels of detail got which parts' turns, and how many keyframes were
-- added in all (memory).
-- Usage: lua dev/tools/parts_audit.lua ghost_build.script.lua model.mdl...
local sim = dofile((arg[0]:gsub("parts_audit%.lua$", "parts_sim.lua")))
_G.api = { res = { modelRep = {} }, type = {} }
local build = assert(load(io.open(arg[1]):read("*a") .. "\nreturn { partsAtLoad = partsAtLoad }", "gb"))()

local function deepcopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local o = {}
  seen[t] = o
  for k, v in pairs(t) do o[deepcopy(k, seen)] = deepcopy(v, seen) end
  return o
end
-- differences between a and b, ignoring our animations and params
local function diff(a, b, path, out, ours)
  if type(a) ~= type(b) then out[#out + 1] = path .. ": " .. type(a) .. " -> " .. type(b) return end
  if type(a) ~= "table" then
    if a ~= b then out[#out + 1] = path .. ": " .. tostring(a) .. " -> " .. tostring(b) end
    return
  end
  for k, v in pairs(b) do
    local p = path .. "." .. tostring(k)
    local isOurs = type(k) == "string" and k:find("^runaround_")
    if a[k] == nil then
      if not isOurs and not (k == "animations" and ours(v)) and not (k == "params" and ours(v)) then out[#out + 1] = p .. ": added" end
    else
      diff(a[k], v, p, out, ours)
    end
  end
  for k in pairs(a) do if b[k] == nil then out[#out + 1] = path .. "." .. tostring(k) .. ": removed" end end
end
local function onlyOurs(t)
  if type(t) ~= "table" then return false end
  for k in pairs(t) do if not (type(k) == "string" and k:find("^runaround_")) then return false end end
  return true
end

local totals = { models = 0, changed = 0, keyframes = 0, anims = 0, bad = 0, lodGaps = 0 }
for i = 2, #arg do
  local d = sim.loadModel(arg[i])
  if d then
    totals.models = totals.models + 1
    local before = deepcopy(d)
    local after = deepcopy(d)
    local okL, err = pcall(build.partsAtLoad, "m.mdl", after)
    local problems = {}
    if not okL then problems[#problems + 1] = "load step error: " .. tostring(err) end
    -- the default transformator the step adds for a rail vehicle without one is the game's own behaviour
    if before.metadata.transformatorConfig == nil and after.metadata.transformatorConfig ~= nil then
      before.metadata.transformatorConfig = deepcopy(after.metadata.transformatorConfig)
      before.metadata.transformatorConfig.params = nil
    end
    diff(before, after, "model", problems, onlyOurs)
    -- per node: at most one turn and one spin; count keyframes; parts per level
    local yawsByLod = {}
    for li, lod in ipairs(after.lods or {}) do
      local names = {}
      local function walk(n)
        local yaws, spins = 0, 0
        for name, ani in pairs(n.animations or {}) do
          if type(name) == "string" and name:find("^runaround_yaw") then yaws = yaws + 1 names[name] = true end
          if type(name) == "string" and name:find("^runaround_spin") then spins = spins + 1 end
          if type(name) == "string" and name:find("^runaround_") then
            totals.anims = totals.anims + 1
            totals.keyframes = totals.keyframes + #ani.params.keyframes
          end
        end
        if yaws > 1 or spins > 1 then problems[#problems + 1] = "node " .. tostring(n.name) .. " has " .. yaws .. " turns and " .. spins .. " spins" end
        for _, c in ipairs(n.children or {}) do walk(c) end
      end
      if lod.node then walk(lod.node) end
      yawsByLod[li] = names
    end
    -- levels missing a part's turn that the full detail has (only where that level has the part's node at all)
    local gaps = {}
    for li = 2, #yawsByLod do
      for name in pairs(yawsByLod[1] or {}) do
        if not yawsByLod[li][name] then gaps[#gaps + 1] = "lod" .. li .. ":" .. name end
      end
    end
    if #gaps > 0 then totals.lodGaps = totals.lodGaps + 1 end
    if #problems > 0 then
      totals.bad = totals.bad + 1
      print(arg[i]:match("[^/]+$") .. ": " .. table.concat(problems, "; "):sub(1, 400))
    end
    if os.getenv("GAPS") and #gaps > 0 then print(arg[i]:match("[^/]+$") .. " gaps: " .. table.concat(gaps, " ")) end
  end
end
print(string.format("%d models; %d with problems; %d with a level missing a turn; %d animations added, %d keyframes (%.1f MB as floats)",
  totals.models, totals.bad, totals.lodGaps, totals.anims, totals.keyframes, totals.keyframes * 16 * 4 / 1e6))
