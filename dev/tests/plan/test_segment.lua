math.atan2 = math.atan2 or math.atan
local now = 0
local sent = {}
api={engine={util={getWorld=function() return 1 end,transport={calcPosition=function(g,u) return {x=g.x0+u*2000,y=0,z=0} end}},
  getComponent=function(e,c) if c=="GT" then return {gameTime=now} end return {edges={{geometry={x0=e*10000}}}} end},
 cmd={makeCustomEntityUpdateTransformationCmd=function(e,t) return t end,sendCommand=function() end,makeCustomEntityUpdateStateCmd=function(e,st) sent[#sent+1]=st return st end},
 type={ComponentType={TRANSPORT_NETWORK="TN",GAME_TIME="GT"},Vec3f={distance=function(a,b) return math.abs(a.x-b.x) end,new=function(x,y,z) return {x=x,y=y,z=z} end},Mat4f={rotZTransl=function(yaw,p) return {} end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {adv=advanceGhost}","s"))()
local env=setmetatable({ug_require=function(p) return {} end},{__index=_G})
assert(load(io.open(arg[2]):read("*a"),"g","t",env))()
local segDist
-- pull segmentDistance out by running a free-entity update and capturing the drive state
local drive
local tu={colorAttributePostition=0,addDriveAnimationState=function(d) drive=d end}
env.ug_require=function(p) if p:find("transformator_util") then return tu end return {} end
assert(load(io.open(arg[2]):read("*a"),"g","t",env))()
local G=env.data()
local loop={speed=20,accel=2,loopEdges={{entity=1,index=0,forward=true}}}
local run={loop=loop,edgeCursor=1,speed=0,ghost=1,locoYaw=0,effects=true}
local dt=0.1
local worst=0
for i=1,150 do
  M.adv(run,dt); now = now + dt*1000
  local st = sent[#sent].state
  G.train.updateFn({}, {currentInfo={world={gameTime=now},customState={state=st}}}, {addAnimationState=function() end,setModelInstanceAttributeVec3f=function() end})
  worst = math.max(worst, math.abs(drive - run.gdist))
end
print(string.format("after 15 s: script %.1f m, wheel formula %.1f m, worst gap %.2f m", run.gdist, drive, worst))
assert(worst < 2.5, "wheel distance follows the ghost")
print("segment ok")
