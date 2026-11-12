math.atan2 = math.atan2 or math.atan
-- The automatic route and the one-click route on track as the game really has
-- it (what the first live try showed the simple mock in test_auto_route.lua
-- got wrong):
--   * a station's terminal has a stop node and NO vehicleEdges (the game's own
--     modular station builds its terminals that way);
--   * the platform is many short pieces (2 m, 16 m, 2 m per half module) and
--     the stop node sits in the middle of it, under the train;
--   * the nodes near a station are mostly not track (streets, footpaths), so
--     "the first hundred nodes nearby" holds no place to reverse.
--
-- Trains come in from the east (heading -x) and stop at x = 120.
--
--   y=5         /--------- loop ----------\
--   y=0   HS --P2-------- platform --------P3--P1------ main ------ (previous stop, x=600)
--   y=-5       (dead end) ---- siding ----/
--        -60   0   40                200  220 240
local nodes, nodeAt, edges = {}, {}, {} -- nodes[id] = {x,y}; edges[entity] = {n1, n2, name}
local nextNode, nextEdge = 5000, 1000
local function nodeId(x, y)
  local k = x .. ":" .. y
  if nodeAt[k] == nil then nextNode = nextNode + 1; nodeAt[k] = nextNode; nodes[nextNode] = { x, y } end
  return nodeAt[k]
end
local function piece(x1, y1, x2, y2, name)
  nextEdge = nextEdge + 1
  edges[nextEdge] = { nodeId(x1, y1), nodeId(x2, y2), name }
  return nextEdge
end
-- a station track: 40 m modules of 2, 16, 2, 2, 16, 2 m pieces
local function stationTrack(y, x1, x2, name)
  local first
  for x = x1, x2 - 40, 40 do
    local at = x
    for _, len in ipairs({ 2, 16, 2, 2, 16, 2 }) do
      local e = piece(at, y, at + len, y, name)
      first = first or e
      at = at + len
    end
  end
  return first
end
local function plainTrack(y, x1, x2, step, name)
  local first
  for x = x1, x2 - step, step do local e = piece(x, y, x + step, y, name); first = first or e end
  return first
end
plainTrack(0, -60, 0, 5, "HS")             -- headshunt, in small pieces
plainTrack(0, 0, 40, 20, "PW")             -- from the west points to the platform
stationTrack(0, 40, 200, "PL")             -- the platform track
plainTrack(0, 200, 240, 20, "PE")          -- on to the east points (P3 at 220, P1 at 240)
plainTrack(0, 240, 600, 20, "ML")          -- the line in
piece(0, 0, 40, 5, "LW")                   -- west points to the loop
local LOOP = stationTrack(5, 40, 200, "LP") -- the loop, a second station track
piece(200, 5, 240, 0, "LE")                -- loop to the east points
stationTrack(-5, 40, 200, "SD")            -- a dead-end siding the other side
piece(200, -5, 220, 0, "SE")
local STREETS = {}
for i = 1, 40 do STREETS[#STREETS + 1] = 9000 + i end

local STOP, PREV = nodeId(120, 0), nodeId(600, 0)
local function nid(id) return { entity = id, index = 0 } end
local function pos(id) return nodes[id] end
local function geomPos(g, t)
  if g.street then return { x = 100 + t * 10, y = 40, z = 0 } end
  local a, b = pos(edges[g.e][1]), pos(edges[g.e][2])
  return { x = a[1] + (b[1] - a[1]) * t, y = a[2] + (b[2] - a[2]) * t, z = 0 }
end
-- the way a piece runs when left from node n
local function dirFrom(e, n)
  local d = edges[e]
  local a, b = pos(n), pos(d[1] == n and d[2] or d[1])
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local l = math.sqrt(dx * dx + dy * dy)
  return dx / l, dy / l
end
local byNode = {}
for e, d in pairs(edges) do
  for _, n in ipairs({ d[1], d[2] }) do byNode[n] = byNode[n] or {}; table.insert(byNode[n], e) end
end
for _, list in pairs(byNode) do table.sort(list) end
-- a train passes from piece a to piece b at node n only straight on (no doubling back at points)
local function canPass(n, a, b)
  if a == b then return false end
  local ax, ay = dirFrom(a, n)
  local bx, by = dirFrom(b, n)
  return ax * bx + ay * by < -0.5
end
local pathfinds = 0
local function findPath(starts, dests)
  pathfinds = pathfinds + 1
  local s, d = starts[1].entity, dests[1].entity
  if nodes[s] == nil or nodes[d] == nil then return {} end
  -- shortest by length over states (node, piece arrived on)
  local dist, prev, open = { [s .. ":0"] = 0 }, {}, { { node = s, arr = 0 } }
  local done = {}
  while true do
    local bi, bd = nil, math.huge
    for i, st in ipairs(open) do
      local dd = dist[st.node .. ":" .. st.arr]
      if dd < bd then bi, bd = i, dd end
    end
    if bi == nil then return {} end
    local cur = table.remove(open, bi)
    local ck = cur.node .. ":" .. cur.arr
    if not done[ck] then
      done[ck] = true
      if cur.node == d then
        local path, k = {}, ck
        while prev[k] do table.insert(path, 1, { { entity = prev[k].e, index = 0 }, prev[k].fwd }); k = prev[k].from end
        return path
      end
      for _, e in ipairs(byNode[cur.node] or {}) do
        if cur.arr == 0 or canPass(cur.node, cur.arr, e) then
          local def = edges[e]
          local nxt = (def[1] == cur.node) and def[2] or def[1]
          local a, b = pos(cur.node), pos(nxt)
          local nd = bd + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
          local nk = nxt .. ":" .. e
          if dist[nk] == nil or nd < dist[nk] then
            dist[nk] = nd
            prev[nk] = { e = e, fwd = def[1] == cur.node, from = ck }
            open[#open + 1] = { node = nxt, arr = e }
          end
        end
      end
    end
  end
end

local stops = { { stationGroup = 100, station = 0, terminal = 0 }, { stationGroup = 101, station = 0, terminal = 0 } }
local listEdges, netData = true, false
api = {
  type = { ComponentType = { TRANSPORT_NETWORK = "TN", LINE = "LINE", STATION_GROUP = "SG", STATION = "ST", BASE_EDGE = "BE", BASE_EDGE_STREET = "BES", BASE_NODE = "BN" },
    Vec3f = { distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end },
    Vec2f = { new = function(x, y) return { x = x, y = y } end },
    enum = { TransportMode = { TRAIN = "TRAIN" } }, Mat4f = { rotZTransl = function() end } },
  engine = {
    getComponent = function(entity, ct)
      if ct == "TN" then
        if entity >= 9000 then return { edges = { { conns = { nid(entity + 1000), nid(entity + 2000) }, geometry = { street = true } } } } end
        local d = edges[entity]
        return d and { edges = { { conns = { nid(d[1]), nid(d[2]) }, geometry = { e = entity } } } } or nil -- (a node's entity has no pieces of its own)
      end
      if ct == "BES" then return entity >= 9000 and {} or nil end
      -- a junction knows where it is (the decoys, streets and footpaths, are not asked for)
      if ct == "BN" then local p = nodes[entity]; return p and { position = { x = p[1], y = p[2], z = 0 } } or nil end
      if ct == "LINE" then return { stops = stops } end
      if ct == "SG" then return { stations = { entity + 100 } } end
      -- as the game's stations are: a stop node, a waiting area, and an EMPTY list of stopping places
      if ct == "ST" then return { terminals = { { vehicleNodeId = nid(entity == 200 and STOP or PREV), vehicleEdges = {}, personNodes = {}, personEdges = {} } } } end
    end,
    util = {
      transport = { calcPosition = geomPos },
      octree = {
        -- every network node nearby: streets and footpaths first, hundreds of them
        findTransportNetworkNodesInCircle = function(c, r)
          local out = {}
          for i = 1, 600 do out[#out + 1] = nid(20000 + i) end
          local ids = {}
          for id, p in pairs(nodes) do if (p[1] - c.x) ^ 2 + (p[2] - c.y) ^ 2 <= r * r then ids[#ids + 1] = id end end
          table.sort(ids)
          for _, id in ipairs(ids) do out[#out + 1] = nid(id) end
          return out
        end,
        findEntitiesInCircle = function(c, r, ct)
          assert(ct == "BE")
          if not listEdges then error("no such search") end
          local out = {}
          for _, s in ipairs(STREETS) do out[#out + 1] = s end
          local ids = {}
          for e in pairs(edges) do
            local m = geomPos({ e = e }, 0.5)
            if (m.x - c.x) ^ 2 + (m.y - c.y) ^ 2 <= r * r then ids[#ids + 1] = e end
          end
          table.sort(ids)
          for _, e in ipairs(ids) do out[#out + 1] = e end
          return out
        end,
      },
      pathfinding = { findPathNodeToNode = findPath },
    },
    system = { transportNetworkSystem = { getTpNetData = function()
      if not netData then error("no network data") end
      return { getNodeData = function(_, node)
        local ports = {}
        for _, e in ipairs(byNode[node.entity] or {}) do ports[#ports + 1] = { edgeId = { entity = e, index = 0 } } end
        return { ports = ports }
      end }
    end } },
  },
}
local log = {}
local M = assert(load("local print = function(...) local t = {} for i = 1, select('#', ...) do t[i] = tostring(select(i, ...)) end LOG[#LOG + 1] = table.concat(t, ' ') end\n"
  .. io.open(arg[1]):read("*a") .. "\nreturn {auto=autoRoute, replan=replanLoop, platform=stopPlatform, stopNode=getStopNode}", "s"))
LOG = log
M = M()
local function logged(text)
  for _, l in ipairs(log) do if l:find(text, 1, true) then return l end end
  return nil
end
local function showLog() return "\n" .. table.concat(log, "\n") end
-- the route as runs of track: "PL- PW- HS- HS+(rev) LW+ ..."
local function fmt(loop)
  local parts, last = {}, nil
  for _, e in ipairs(loop.loopEdges) do
    local s = edges[e.entity][3] .. (e.forward and "+" or "-")
    if e.reversal then parts[#parts + 1] = s .. "(rev)" elseif s ~= last then parts[#parts + 1] = s end
    last = s
  end
  return table.concat(parts, " ")
end
local function newLoop() return { id = 1, name = "T", lineEntity = 50, stopIndex = 0, waypoints = {}, loopEdges = {}, speed = 8, accel = 2 } end
-- out ahead of the loco (west) to the headshunt, back along the loop, out onto the line, back onto the train from behind
local WANT = "PL- PW- HS- HS+(rev) LW+ LP+ LE+ ML+ ML-(rev) PE- PL-"
local function isRunAround(loop, what)
  assert(loop.routeState == "ok", what .. ": " .. tostring(loop.routeHint) .. showLog())
  assert(fmt(loop) == WANT, what .. ": " .. fmt(loop) .. showLog())
  assert(loop.routeReversals == 2 and loop.routeWarning == nil and loop.backFrom ~= nil, what .. ": two reversals, no warning: " .. tostring(loop.routeWarning))
  local first, last = loop.loopEdges[1], loop.loopEdges[#loop.loopEdges]
  assert(edges[first.entity][first.forward and 1 or 2] == STOP, what .. ": starts at the stop node, in the middle of the platform")
  assert(edges[last.entity][last.forward and 2 or 1] == STOP and pos(edges[last.entity][last.forward and 1 or 2])[1] > 120, what .. ": comes back to the stop from behind the train")
end

-- 1. The terminal has no stopping place listed: the platform is still read.
local sn, sp = M.stopNode(50, 0)
assert(sn.entity == STOP, "the stop node")
assert(sp == nil, "(nothing gives the stop's position by itself in this mock)")
local plat, why = M.platform(50, 0, sn, nil)
assert(plat == nil and why:find("no piece was found at the stop node", 1, true) and why:find("network's node data: failed", 1, true), "every way of asking is named when all fail: " .. tostring(why))
netData = true
plat = assert(M.platform(50, 0, sn, nil))
assert(math.abs(plat.pos.x - 120) < 1e-6 and math.abs(plat.pos.y) < 1e-6 and math.abs(math.abs(plat.tx) - 1) < 1e-6, "read from the pieces at the stop node")
sn, sp = M.stopNode(50, 0)
assert(sp and math.abs(sp.x - 120) < 1e-6, "and the stop's position with it")
netData = false
print("platform with no stopping place listed: read from the stop node (" .. plat.how .. ")")

-- 2. Found by itself, with nothing but the stop node and the pathfinder to go on.
local loop = newLoop()
pathfinds = 0
assert(M.auto(loop) == true, "a route is found: " .. tostring(loop.routeHint) .. showLog())
isRunAround(loop, "automatic")
assert(edges[loop.waypoints[1].entity][3] == "LP", "by the loop")
assert(logged("platform track read from the piece trains come in on"), "the log says how the platform was read" .. showLog())
assert(logged("planned as a run-around"), "and that the route was planned as a run-around")
assert(pathfinds < 3000, "bounded search: " .. pathfinds)
print("automatic:", fmt(loop), "(" .. pathfinds .. " pathfinder calls)")

-- 3. One click on the loop: the same, two reversals.
log = {}; LOG = log
loop = newLoop()
loop.waypoints = { { entity = LOOP + 8, index = 0 } }
pathfinds = 0
M.replan(loop)
isRunAround(loop, "one click")
assert(logged("reversing place(s) at 3 set(s) of points"), "the places to reverse are found at the points" .. showLog())
print("one click on the loop:", fmt(loop), "(" .. pathfinds .. " pathfinder calls)")

-- 4. The same line with one stop only: the way in isn't known, and the log says so.
log = {}; LOG = log
local keepStops = stops
stops = { keepStops[1] }
loop = newLoop()
loop.waypoints = { { entity = LOOP + 8, index = 0 } }
M.replan(loop)
assert(logged("the way trains come in is NOT known (the line has only 1 stop(s))"), "said in the log" .. showLog())
stops = keepStops
print("one stop on the line:", loop.routeState, loop.routeWarning or loop.routeHint or fmt(loop))

-- 5. The track nearby can't be listed: said in the log; a route drawn with
-- two clicks (headshunt, loop) still comes back onto the train from behind,
-- reversing on the line in (known from the way trains come in).
log = {}; LOG = log
listEdges = false
loop = newLoop()
assert(M.auto(loop) == false and logged("the track around the stop could not be listed"), "no automatic route, and why" .. showLog())
local hs
for e, d in pairs(edges) do if d[3] == "HS" and pos(d[1])[1] == -30 then hs = e end end
loop = newLoop()
loop.waypoints = { { entity = hs, index = 0 }, { entity = LOOP + 8, index = 0 } }
M.replan(loop)
assert(loop.routeState == "ok" and loop.routeReversals == 2 and loop.routeWarning == nil and loop.backFrom ~= nil, "two clicks: " .. fmt(loop) .. " / " .. tostring(loop.routeWarning) .. showLog())
assert(logged("the track near could not be listed"), "said in the log" .. showLog())
print("track can't be listed, two clicks:", fmt(loop))
-- 6. The same, with ONE click on the loop (seen live: "no set of points ...;
-- any node nearby tried instead: 100 of 476"). The nearby nodes are tried along
-- the platform's line first, so the reversing places past the points are among
-- the first tried, not lost behind hundreds of street nodes.
log = {}; LOG = log
loop = newLoop()
loop.waypoints = { { entity = LOOP + 8, index = 0 } }
M.replan(loop)
assert(loop.routeState == "ok" and loop.routeReversals == 2 and loop.routeWarning == nil and loop.backFrom ~= nil, "one click: " .. fmt(loop) .. " / " .. tostring(loop.routeWarning) .. showLog())
assert(logged("on the platform's line past its ends"), "the ranking is logged" .. showLog())
print("track can't be listed, ONE click:", fmt(loop))
listEdges = true
print("auto route (station) ok")
