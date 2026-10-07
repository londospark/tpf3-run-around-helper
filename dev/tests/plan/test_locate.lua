-- straight edges along x: edge i spans x=(i-1)*50 .. i*50
local edges={}
api={engine={util={transport={calcPosition=function(g,u) return {x=(g.i-1)*50+u*50,y=0,z=0} end}},getComponent=function(e,c) return {edges={{geometry={i=e}}}} end},
 type={ComponentType={TRANSPORT_NETWORK=1},Vec3f={distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {loc=locateOnRoute}","s"))()
local loop={loopEdges={{entity=1,index=0,forward=true},{entity=2,index=0,forward=true},{entity=3,index=0,forward=true}}}
local k,s,d=M.loc(loop,{x=70,y=3}); print(k,s,d); assert(k==2 and math.abs(s-20)<3 and d<4)
loop.loopEdges[2].forward=false
k,s,d=M.loc(loop,{x=70,y=3}); print(k,s,d); assert(k==2 and math.abs(s-30)<3)
print("locate ok")
