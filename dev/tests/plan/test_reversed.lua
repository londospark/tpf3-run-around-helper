math.atan2 = math.atan2 or math.atan
api = {}
local M = assert(load(io.open(arg[1]):read("*a").."\nreturn {r=locoIsReversed}","s"))()
local function run(o) local r={startHead={x=1,y=0},startSign=1,startReversed=false,gyaw=0.0} for k,v in pairs(o) do r[k]=v end return r end
-- The live case: loco faced along the head (+x) with reversed=false, ghost keeps that facing, train is flipped.
local rev = M.r(run({flipped=true, gyaw=0.0}))
assert(rev == true, "flipped train, same world facing -> flag toggled")
-- no flip (fallback): same head, same facing -> flag unchanged
assert(M.r(run({flipped=false, gyaw=0.0})) == false)
-- the ghost turned round (wye or balloon): world facing reversed, train flipped -> flag same as at the start
assert(M.r(run({flipped=true, gyaw=math.pi})) == false)
-- start had the loco facing against the head with reversed=true
assert(M.r(run({startSign=-1, startReversed=true, flipped=true, gyaw=math.pi})) == false)   -- facing kept (pi), head flipped: sign against->along... 
print("locoIsReversed ok")
