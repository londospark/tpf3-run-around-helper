-- Run-arounds belong to a platform (a station and its terminal), not to a line
-- and a stop index: every line stopping there shares it, a stop inserted
-- earlier in a line doesn't move it, there's one per platform, and run-arounds
-- set up before this get their platform once.
-- Two stations (entities 501, 502) in groups 401, 402; three lines.
local LINES = {
  [10] = { stops = { { stationGroup = 401, station = 0, terminal = 1 }, { stationGroup = 402, station = 0, terminal = 0 } } },
  [20] = { stops = { { stationGroup = 402, station = 0, terminal = 0 }, { stationGroup = 401, station = 0, terminal = 1 } } },
  [30] = { stops = { { stationGroup = 401, station = 0, terminal = 0 } } }, -- the same station, another platform
}
api = {
  type = { ComponentType = { LINE = "LINE", STATION_GROUP = "SG", TRANSPORT_VEHICLE = "TV" } },
  engine = { getComponent = function(e, c)
    if c == "LINE" then return LINES[e] end
    if c == "SG" then return { stations = { e + 100 } } end
  end },
}
LOG = {}
local M = assert(load("local print = function(...) local t = {} for i = 1, select('#', ...) do t[i] = tostring(select(i, ...)) end LOG[#LOG + 1] = table.concat(t, ' ') end\n"
  .. io.open(arg[1]):read("*a") .. "\nreturn {find=findLoopForArrival, place=stopPlace, ensure=ensureData, gui=handleGuiCmd}", "s"))()

-- a run-around set up from line 10 at its first stop (station 501, terminal 1)
local data = { loops = {}, runs = {}, pending = {} }
local state = { get = function() return data end, set = function(_, d) data = d end }
M.gui(data, "AddLoopAtStop", { lineEntity = 10, stopIndex = 0, name = "A" })
local loop = data.loops[1]
assert(loop.station == 501 and loop.terminal == 1, "it belongs to its platform")
assert(M.find(data.loops, 10, 0) == loop, "line 10 at that stop")
assert(M.find(data.loops, 20, 1) == loop, "line 20 stops at the same platform: the same run-around")
assert(M.find(data.loops, 30, 0) == nil, "another platform of the same station: not this one")
assert(M.find(data.loops, 10, 1) == nil, "another station: none")
-- one per platform, whichever line it is set up from
M.gui(data, "AddLoopAtStop", { lineEntity = 20, stopIndex = 1, name = "B" })
assert(#data.loops == 1, "no second run-around at the same platform")
-- a stop inserted earlier in line 10: the run-around stays with its platform
table.insert(LINES[10].stops, 1, { stationGroup = 402, station = 0, terminal = 0 })
assert(M.find(data.loops, 10, 1) == loop, "found at the platform's new stop index")
assert(M.find(data.loops, 10, 0) == nil, "not at the stop index it was set up at")
table.remove(LINES[10].stops, 1)
print("platform: shared by lines 10 and 20, one per platform, survives a stop inserted earlier")

-- a run-around saved before platforms: matched by line and stop until it is converted, once
data = { loops = { { id = 7, name = "Old", lineEntity = 20, stopIndex = 1, waypoints = {}, loopEdges = {} } } }
M.ensure(state)
local old = data.loops[1]
assert(old.station == 501 and old.terminal == 1, "converted to its platform")
assert(M.find(data.loops, 10, 0) == old, "and so shared with line 10")
local said = false
for _, l in ipairs(LOG) do if l:find("now belongs to its platform", 1, true) then said = true end end
assert(said, "the conversion is logged")
-- one whose line has gone: kept by line and stop, and tried no more after a while
data = { loops = { { id = 8, name = "Gone", lineEntity = 99, stopIndex = 0, waypoints = {}, loopEdges = {} } } }
for _ = 1, 101 do M.ensure(state) end
assert(data.loops[1].station == nil and data.loops[1].unplaceable == true, "gave up converting a run-around whose line has gone")
assert(M.find(data.loops, 99, 0) == data.loops[1], "still matched by its line and stop")
print("old run-arounds: converted once; a gone line's kept as it was")
print("platform ok")
