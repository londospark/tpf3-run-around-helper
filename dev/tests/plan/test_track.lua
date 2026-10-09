-- The track under the loco copy, sent to ghost_real: points every 2 m from
-- -24 to +24 m along the copy's facing (long enough for a Big Boy's tender), in its own frame, following the route
-- onto the pieces that join on, and straight on where nothing joins.
math.atan2 = math.atan2 or math.atan
-- pieces of 100 m along x, piece e from x = (e-1)*100; piece 9 is elsewhere
api={engine={util={transport={calcPosition=function(g,u) return {x=g.x0+u*100,y=g.y0,z=0} end}},
  getComponent=function(e,c) return {edges={{geometry={x0=(e-1)*100,y0=(e==9) and 500 or 0}}}} end},
 type={ComponentType={TRANSPORT_NETWORK="TN"},Vec3f={distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {strip=trackStrip}","s"))()
local function xs(tr) local o={} for i=1,#tr.pts,2 do o[#o+1]=tr.pts[i] end return o end
local function check(tr, want, what)
  local got = xs(tr)
  assert(#got == 25, what .. ": 25 points")
  for i, x in ipairs(got) do assert(math.abs(x - want(-24 + 2 * (i - 1))) < 1e-6 and math.abs(tr.pts[2*i]) < 1e-6, what .. ": point " .. i .. " at " .. x) end
end
local loop = { loopEdges = { {entity=1,index=0,forward=true}, {entity=2,index=0,forward=true}, {entity=3,index=0,forward=true} } }
-- 5 m into piece 2 (x = 105): back onto piece 1, ahead on piece 2
local run = { edgeCursor = 2, edgeProgress = 5, gx = 105, gy = 0, gyaw = 0 }
check(M.strip(run, loop, 1), function(s) return s end, "facing the way of travel")
-- facing back (driving backwards): model x points the other way
run.gyaw = math.pi
check(M.strip(run, loop, -1), function(s) return s end, "facing back")
-- 95 m into the last piece: beyond its end the track runs straight on
run = { edgeCursor = 3, edgeProgress = 95, gx = 295, gy = 0, gyaw = 0 }
check(M.strip(run, loop, 1), function(s) return s end, "straight on past the end")
-- a next piece that doesn't join (across a reversal): not followed
loop.loopEdges[4] = {entity=9,index=0,forward=true}
check(M.strip(run, loop, 1), function(s) return s end, "not onto a piece that doesn't join")
print("track ok")
