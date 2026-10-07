math.atan2 = math.atan2 or math.atan
local sent={}
api={engine={util={transport={calcPosition=function(g,u) return {x=g.x0+u*100,y=0,z=0} end}},getComponent=function(e,c) return {edges={{geometry={x0=e*1000}}}} end},
 cmd={makeCustomEntityUpdateTransformationCmd=function(e,t) return t end,makeCustomEntityUpdateStateCmd=function(e,st) sent[#sent+1]=st return st end,sendCommand=function() end},
 type={ComponentType={TRANSPORT_NETWORK=1},Vec3f={distance=function(a,b) return math.abs(a.x-b.x) end,new=function(x,y,z) return {x=x,y=y,z=z} end},Mat4f={rotZTransl=function(yaw,p) return {yaw=yaw,x=p.x,y=p.y} end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {adv=advanceGhost,CONFIG=CONFIG}","s"))()
local loop={speed=20,accel=100,loopEdges={{entity=1,index=0,forward=true},{entity=2,index=0,forward=true}}}
local run={hasTail=false,effects=true,topSpeed=30,loop=loop,edgeCursor=1,speed=0,ghost=1,locoYaw=0}
for i=1,60 do M.adv(run,0.1) end
local maxS=0 for _,m in ipairs(sent) do if m.speed01>maxS then maxS=m.speed01 end end
print("state messages:",#sent,"max speed01",maxS,"last",sent[#sent].speed01, "seg", sent[#sent].state.seg and sent[#sent].state.seg.acc)
assert(#sent>=5 and maxS>0.5 and sent[1].state.seg ~= nil)
print("effects state ok")
