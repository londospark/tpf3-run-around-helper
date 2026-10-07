-- Generates ghost models (no metadata) from base-game vehicle models.
local srcRoot = "src/"
local outRoot = arg[1]
local function fix(dir, p)
  if p:sub(1,3) == "::/" then return p end
  if p:sub(1,1) == "/" then return "::" .. p end
  return "::/vehicle/train/" .. dir .. "/" .. p
end
local function isEmissive(node)
  for _, m in ipairs(node.materials or {}) do if m:find("emissive") or m:find("light") then return true end end
  return false
end
local function conv(dir, node)
  local o = {name = node.name, transf = node.transf}
  if node.mesh and not isEmissive(node) then
    o.mesh = fix(dir, node.mesh)
    o.materials = {}
    for i, m in ipairs(node.materials or {}) do o.materials[i] = fix(dir, m) end
  end
  o.children = {}
  for _, c in ipairs(node.children or {}) do
    if not (c.mesh and isEmissive(c)) then o.children[#o.children+1] = conv(dir, c) end
  end
  return o
end
local ser
ser = function(v, ind)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t ~= "table" then return tostring(v) end
  local keys, isArr = {}, #v > 0
  if isArr then
    local parts = {}
    local flat = type(v[1]) ~= "table"
    for _, x in ipairs(v) do parts[#parts+1] = ser(x, ind .. "\t") end
    if flat then return "{ " .. table.concat(parts, ", ") .. ", }" end
    return "{\n" .. ind .. "\t" .. table.concat(parts, ",\n" .. ind .. "\t") .. ",\n" .. ind .. "}"
  end
  for k in pairs(v) do keys[#keys+1] = k end
  table.sort(keys)
  if #keys == 0 then return "{ }" end
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts+1] = k .. " = " .. ser(v[k], ind .. "\t") end
  return "{\n" .. ind .. "\t" .. table.concat(parts, ",\n" .. ind .. "\t") .. ",\n" .. ind .. "}"
end
local n = 0
local p = io.popen("cd src && find . -name '*.mdl' | sort")
for line in p:lines() do
  local dir, file = line:match("^%./([^/]+)/([^/]+)$")
  local src = io.open(srcRoot .. dir .. "/" .. file):read("*a")
  local env = {_ = function(s) return s end, math = math, string = string, table = table}
  load(src, "x", "t", env)()
  local m = env.data()
  local isVeh = m.metadata and m.metadata.landVehicle and m.metadata.landVehicle.engines and #m.metadata.landVehicle.engines > 0
  if isVeh then
    local g = {boundingInfo = m.boundingInfo, collider = m.collider, lods = {}, metadata = {}, version = 2}
    for _, l in ipairs(m.lods) do
      g.lods[#g.lods+1] = {node = conv(dir, l.node), visibleFrom = l.visibleFrom, visibleTo = l.visibleTo}
    end
    local f = io.open(outRoot .. "/" .. file, "w")
    f:write("-- Generated ghost model: the geometry of the base-game vehicle model " .. dir .. "/" .. file .. "\n-- with no vehicle metadata, sound, particles or scripts, so it is safe as a free entity.\nfunction data()\nreturn " .. ser(g, "") .. "\nend\n")
    f:close(); n = n + 1
  end
end
print("generated", n)
