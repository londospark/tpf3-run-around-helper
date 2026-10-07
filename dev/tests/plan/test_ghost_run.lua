math.atan2 = math.atan2 or math.atan
local log={}
api={engine={util={transport={calcPosition=function(g,u) return {x=g.x0+u*100,y=0,z=0} end}},
  getComponent=function(e,c) return {edges={{geometry={x0=e*1000}}}} end},
 cmd={makeCustomEntityUpdateTransformationCmd=function(e,t) log[#log+1]=t return t end,sendCommand=function() end},
 type={ComponentType={TRANSPORT_NETWORK=1},Vec3f={distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end,new=function(x,y,z) return {x=x,y=y,z=z} end},
  Mat4f={rotZTransl=function(yaw,p) return {yaw=yaw,x=p.x,y=p.y} end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {adv=advanceGhost,CONFIG=CONFIG}","s"))()
M.CONFIG.reverseBeforeRecouple=true
local loop={speed=20,accel=100,loopEdges={{entity=1,index=0,forward=true},{entity=2,index=0,forward=true},{entity=2,index=0,forward=false,reversal=true},{entity=1,index=0,forward=false}}}
local run={hasTail=true,loop=loop,edgeCursor=1,speed=0,ghost=1,locoYaw=math.pi}  -- loco faces -x while travel is +x
local n=0
local minx,maxx=1e9,-1e9
while true do
  n=n+1; local r=M.adv(run,0.1); if #log>0 then local t=log[#log]; if t.x then maxx=math.max(maxx,t.x) end end
  if run.phase=="flip" or n>2000 then break end
end
print("phase",run.phase,"steps",n,"final",run.gx,run.gy,"yaw",run.gyaw)
-- piece 2 is x 2000..2100: ghost should have gone only to 2010 then back to 2010 start-of-reversal
print("max x on piece 2:",maxx)
assert(maxx<2012 and maxx>2009 and run.phase=="flip")
-- facing: loco faces -x (pi); travel +x, one reversal flips: final yaw = pi + pi = 2pi -> facing +x
print("yaw",run.gyaw, run.yawOffset)
-- wagon restore: [S w1 w2 w3 w4 S] flipped -> [loco w4 w3 w2 w1] with flags toggled
api.type.TransportVehicleConfig={new=function(t) local c={vehicles={}} for i,p in ipairs(t.vehicles) do c.vehicles[i]=p end return c end}
api.type.TransportVehiclePart={new=function() return {part={}} end}
api.type.LoadConfig={new=function() return {} end}
api.res={modelRep={getAll=function() return {[9]="m::/res/models/runaround_standin/standin_cm1200.mdl"} end,get=function() return {metadata={transportVehicle={compartments={{loadConfigs={{}}}}}}} end}}
local M2=assert(load(io.open(arg[1]):read("*a").."\nreturn {b=buildConfigWithLocoReattached}","s2"))()
local cur={vehicles={{part={modelId=9,reversed=false}},{part={modelId=1,reversed=false,tag="w1"}},{part={modelId=2,reversed=true,tag="w2"}},{part={modelId=3,reversed=false,tag="w3"}},{part={modelId=9,reversed=false}}}}
local snap={modelId=5,reversed=false,loads={{loadConfigIndex=0}},autos={true},purchaseTime=1,maintenanceChange=0}
local cfg=M2.b(cur,snap,false,9,true,{false,true,false})
local order={} for i,p in ipairs(cfg.vehicles) do order[i]=(p.part.tag or "L")..(p.part.reversed and "r" or "-") end
print(table.concat(order," "))
assert(table.concat(order," ")=="Lr w3r w2- w1r")
print("wagon restore ok")
