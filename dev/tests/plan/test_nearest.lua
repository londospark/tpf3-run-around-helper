-- carriages at x = 0,20,40,60,80 ; first route point at x=75 -> expect part 5 ; at x=5 -> part 1
local function carriage(x) return {fatInstances={{transf={cols=function(_,i) return {x=x,y=0,z=0} end}}}} end
local comps={}
local cl={carriages={}}
for i=1,5 do cl.carriages[i]=1000+i; comps[1000+i]=carriage((i-1)*20) end
api={type={ComponentType={CARRIAGE_LIST="CL",MODEL_INSTANCE_LIST="MIL"}},
     engine={getComponent=function(e,ct) if ct=="CL" then return cl end return comps[e] end}}
local src=io.open(arg[1]):read("*a").."\nreturn {nearest=nearestCarriageIndex}"
local M=assert(load(src,"s"))()
print("point at x=75 ->", (M.nearest(1,{x=75,y=0})))
print("point at x=5  ->", (M.nearest(1,{x=5,y=0})))
