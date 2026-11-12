math.atan2 = math.atan2 or math.atan
-- The route found without being shown it, and a route from ONE click.
--
-- (A simple layout: one piece per stretch, and a terminal that lists its
-- stopping place. test_auto_route_station.lua has track as the game's own
-- stations really have it: no stopping place listed, many short pieces.)
--
-- A terminus platform (PLa, PLb; the stop at N6) with a run-round loop beside
-- it (L1, Lm, L2), a headshunt each end (T, ML), a dead-end siding on the other
-- side (S1) and a street. Trains come in from the west (ML -> PLa).
--
--        N5b ----- Lm ----- N5a
--       /                      \
--   N7 -ML- N0 -PLa- N6 -PLb- N1 -T- N2
--                          N8 -S1-/
local POS = { [0] = { 0, 0 }, [1] = { 200, 0 }, [2] = { 300, 0 }, [6] = { 100, 0 }, [7] = { -200, 0 }, [51] = { 170, 5 }, [52] = { 30, 5 }, [8] = { 100, -5 } }
local EDGES = { -- entity -> { from node, to node, name }
  [10] = { 0, 6, "PLa" }, [11] = { 6, 1, "PLb" }, [12] = { 1, 2, "T" }, [13] = { 1, 51, "L1" }, [14] = { 51, 52, "Lm" }, [15] = { 52, 0, "L2" },
  [16] = { 7, 0, "ML" }, [17] = { 1, 8, "S1" },
}
local STREET = 18
local function node(i) return { entity = 1, index = i } end
-- pairs of pieces a train can't pass between at a node (the two trailing branches of a set of points)
local forbidden = { ["1:11-13"] = true, ["1:11-17"] = true, ["1:13-17"] = true, ["0:10-15"] = true }
local function allowed(n, a, b)
  if a == b then return false end
  return not forbidden[n .. ":" .. math.min(a, b) .. "-" .. math.max(a, b)]
end
local pathfinds = 0
local stops = { { stationGroup = 100, station = 0, terminal = 0 }, { stationGroup = 101, station = 0, terminal = 0 } }
api = {
  type = { ComponentType = { TRANSPORT_NETWORK = "TN", LINE = "LINE", STATION_GROUP = "SG", STATION = "ST", BASE_EDGE = "BE", BASE_EDGE_STREET = "BES" },
    Vec3f = { distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end },
    Vec2f = { new = function(x, y) return { x = x, y = y } end },
    enum = { TransportMode = { TRAIN = "TRAIN" } }, Mat4f = { rotZTransl = function() end } },
  engine = {
    getComponent = function(entity, ct)
      if ct == "TN" then
        if entity == STREET then return { edges = { { conns = { node(90), node(91) }, geometry = { street = true } } } } end
        local d = EDGES[entity]
        return d and { edges = { { conns = { node(d[1]), node(d[2]) }, geometry = { e = entity } } } } or nil
      end
      if ct == "BES" then return entity == STREET and {} or nil end
      if ct == "LINE" then return { stops = stops } end
      if ct == "SG" then return { stations = { entity + 100 } } end
      if ct == "ST" then
        if entity == 200 then return { terminals = { { vehicleNodeId = node(6), vehicleEdges = { { edgeId = { entity = 10, index = 0 }, param = 1.0 } } } } } end
        return { terminals = { { vehicleNodeId = node(7), vehicleEdges = { { edgeId = { entity = 16, index = 0 }, param = 0.0 } } } } }
      end
    end,
    util = {
      transport = { calcPosition = function(g, t)
        if g.street then return { x = 100 + t * 10, y = 8, z = 0 } end
        local a, b = POS[EDGES[g.e][1]], POS[EDGES[g.e][2]]
        return { x = a[1] + (b[1] - a[1]) * t, y = a[2] + (b[2] - a[2]) * t, z = 0 }
      end },
      octree = {
        findTransportNetworkNodesInCircle = function() local out = {} for i in pairs(POS) do out[#out + 1] = node(i) end table.sort(out, function(a, b) return a.index < b.index end) return out end,
        findEntitiesInCircle = function(_, _, ct) assert(ct == "BE") local out = { STREET } for e in pairs(EDGES) do out[#out + 1] = e end table.sort(out) return out end,
      },
      pathfinding = { findPathNodeToNode = function(starts, dests)
        pathfinds = pathfinds + 1
        local s, d = starts[1].index, dests[1].index
        local q, seen = { { node = s, path = {} } }, {}
        while #q > 0 do
          local cur = table.remove(q, 1)
          if cur.node == d then return cur.path end
          for e, def in pairs(EDGES) do
            local nxt, fwd
            if def[1] == cur.node then nxt, fwd = def[2], true elseif def[2] == cur.node then nxt, fwd = def[1], false end
            if nxt and (cur.arr == nil or allowed(cur.node, cur.arr, e)) and not seen[nxt .. ":" .. e] then
              seen[nxt .. ":" .. e] = true
              local p = { table.unpack(cur.path) }; p[#p + 1] = { { entity = e, index = 0 }, fwd }
              q[#q + 1] = { node = nxt, arr = e, path = p }
            end
          end
        end
        return {}
      end },
    },
  },
}
local log = {}
local M = assert(load("local print = function(...) local t = {} for i = 1, select('#', ...) do t[i] = tostring(select(i, ...)) end LOG[#LOG + 1] = table.concat(t, ' ') end\n"
  .. io.open(arg[1]):read("*a") .. "\nreturn {auto=autoRoute, replan=replanLoop, gui=handleGuiCmd}", "s"))
LOG = log
M = M()
local function fmt(loop)
  local parts = {}
  for _, e in ipairs(loop.loopEdges) do parts[#parts + 1] = EDGES[e.entity][3] .. (e.forward and "+" or "-") .. (e.reversal and "(rev)" or "") end
  return table.concat(parts, " ")
end
local function newLoop() return { id = 1, name = "T", lineEntity = 50, stopIndex = 0, waypoints = {}, loopEdges = {}, speed = 8, accel = 2 } end
local WANT = "PLb+ T+ T-(rev) L1+ Lm+ L2+ ML- ML+(rev) PLa+"

-- 1. Found by itself: out by the headshunt, along the loop, back onto the train from behind.
local loop = newLoop()
pathfinds = 0
assert(M.auto(loop) == true, "a route is found: " .. tostring(loop.routeHint))
print("automatic:", fmt(loop), "(" .. pathfinds .. " pathfinder calls)")
assert(fmt(loop) == WANT, fmt(loop))
assert(loop.auto == true and #loop.waypoints == 1 and loop.waypoints[1].entity == 14, "by the loop beside the platform")
assert(loop.routeState == "ok" and loop.routeWarning == nil and loop.backFrom ~= nil and loop.routeReversals == 2, "a clean run-around")
assert(loop.routeDrive and loop.routeDrive > 300 and loop.routeDrive < loop.routeLength, "the distance driven (reversing just clear of the points) is known")
assert(pathfinds < 3000, "bounded search")

-- 2. One click on the loop does the same.
loop = newLoop()
loop.waypoints = { { entity = 14, index = 0 } }
M.replan(loop)
assert(fmt(loop) == WANT and loop.routeState == "ok" and loop.routeWarning == nil, "one click: " .. fmt(loop))
print("one click on the loop:", fmt(loop))

-- 3. A click that gives a route which is not a run-around is said so.
loop = newLoop()
loop.waypoints = { { entity = 17, index = 0 } } -- the dead-end siding: out and back the same way
M.replan(loop)
assert(loop.routeState == "ok" and loop.routeWarning and loop.routeWarning:find("same end", 1, true), "siding: " .. tostring(loop.routeWarning) .. " / " .. fmt(loop))
print("click on the siding:", loop.routeWarning)
loop = newLoop()
loop.waypoints = { { entity = 16, index = 0 } } -- behind the train: back through the coaches
M.replan(loop)
assert(loop.routeWarning and loop.routeWarning:find("back through the train", 1, true), "behind: " .. tostring(loop.routeWarning) .. " / " .. fmt(loop))
print("click behind the train:", loop.routeWarning)

-- 4. No loop (the points at the far end gone): nothing found, the loop left empty with a hint.
local l2 = EDGES[15]
EDGES[15] = nil
loop = newLoop()
assert(M.auto(loop) == false and #loop.waypoints == 0 and #loop.loopEdges == 0, "no way round: nothing kept")
assert(loop.routeHint and loop.routeHint:find("Draw route", 1, true), tostring(loop.routeHint))
print("no loop:", loop.routeHint)
-- ... and one click there says why in plain words
loop.waypoints = { { entity = 14, index = 0 } }
M.replan(loop)
assert(loop.routeState == "ok" or (loop.routeState == "problem" and loop.routeHint), "a click with no way back is explained")
print("a click with no way back:", loop.routeState, loop.routeHint or loop.routeWarning or fmt(loop))
EDGES[15] = l2

-- 5. No track beside the platform at all.
local keep = { EDGES[13], EDGES[14], EDGES[15], EDGES[17] }
EDGES[13], EDGES[14], EDGES[15], EDGES[17] = nil, nil, nil, nil
loop = newLoop()
assert(M.auto(loop) == false and loop.routeHint:find("no other track beside this platform", 1, true), tostring(loop.routeHint))
print("plain terminus:", loop.routeHint)
EDGES[13], EDGES[14], EDGES[15], EDGES[17] = keep[1], keep[2], keep[3], keep[4]

-- 6. From the card: adding a run-around finds its route; clicking replaces it; "find it again" brings it back.
local data = { loops = {}, runs = {}, pending = {} }
M.gui(data, "AddLoopAtStop", { lineEntity = 50, stopIndex = 0, name = "Terminus" })
loop = data.loops[1]
assert(loop and loop.auto and fmt(loop) == WANT, "added with its route")
M.gui(data, "AddLoopEdgeFromWorldClick", { loopId = loop.id, entity = 13, index = 0 })
assert(loop.auto == nil and #loop.waypoints == 1 and loop.waypoints[1].entity == 13, "a click starts the player's own route")
assert(fmt(loop) == WANT, "(by the other end of the same loop: the same way round) " .. fmt(loop))
M.gui(data, "ClearLoopPoints", { loopId = loop.id })
assert(#loop.loopEdges == 0 and loop.routeState == "none")
M.gui(data, "AutoRoute", { loopId = loop.id })
assert(loop.auto and fmt(loop) == WANT, "found again")
print("card: added with its route, redrawn by a click, found again")
print("auto route ok")
