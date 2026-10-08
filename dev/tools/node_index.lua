-- Prints a model's nodes (first level of detail) numbered as the game numbers
-- user transforms: the root 0, then depth first. Also the rail vehicle's axles
-- and fake bogies. For reading the PROBE lines in stdout.txt.
-- Usage: lua dev/tools/node_index.lua path/to/model.mdl [lod]
local path, lod = arg[1], tonumber(arg[2] or "1")
local env = setmetatable({}, { __index = function(_, k)
  if _G[k] ~= nil then return _G[k] end
  return setmetatable({}, { __index = function() return function() return {} end end, __call = function() return {} end })
end })
local chunk = assert(loadfile(path, "t", env))
chunk()
local d = env.data()
local function walk(node, depth, idx)
  local t = node.transf
  local x = (type(t) == "table" and t[13]) and string.format(" at x=%.2f y=%.2f z=%.2f", t[13], t[14], t[15]) or ""
  print(string.format("%3d %s%s%s", idx, string.rep("  ", depth), tostring(node.name or node.mesh or "?"), x))
  idx = idx + 1
  for _, c in ipairs(node.children or {}) do idx = walk(c, depth + 1, idx) end
  return idx
end
walk(d.lods[lod].node, 0, 0)
local rv = d.metadata and d.metadata.railVehicle
local cfg = rv and (rv.config or (rv.configs and rv.configs[lod]))
if cfg then
  print("axles: " .. table.concat(cfg.axles or {}, ", "))
  for l, fb in ipairs(cfg.fakeBogies or {}) do
    for _, b in ipairs(fb) do print(string.format("fake bogie (lod %d): %s position %s offset %s", l, tostring(b.group), tostring(b.position), tostring(b.offset))) end
  end
end
