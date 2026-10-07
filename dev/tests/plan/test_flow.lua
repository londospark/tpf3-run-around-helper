math.atan2 = math.atan2 or math.atan
local sent={}
local carriages={11,12}
api={engine={util={transport={calcPosition=function(g,u) return {x=g.x0+u*100,y=0,z=0} end}},
  getComponent=function(e,c)
    if c=="TN" then return {edges={{geometry={x0=e*1000}}}} end
    if c=="CL" then return {carriages=carriages} end
    if c=="MIL" then return {fatInstances={{transf={cols=function() return {x=500,y=3,z=0} end}}}} end end},
 cmd={makeCustomEntityUpdateTransformationCmd=function(e,t) return t end,sendCommand=function() end,makeCustomEntityUpdateStateCmd=function() return {} end},
 type={ComponentType={TRANSPORT_NETWORK="TN",CARRIAGE_LIST="CL",MODEL_INSTANCE_LIST="MIL"},Vec3f={distance=function() return 0 end,new=function(x,y,z) return {x=x,y=y,z=z} end},Mat4f={rotZTransl=function(yaw,p) return {yaw=yaw,x=p.x,y=p.y} end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {adv=advanceGhost,CONFIG=CONFIG}","s"))()
M.CONFIG.reverseBeforeRecouple=true
local loop={speed=20,accel=100,loopEdges={{entity=1,index=0,forward=true},{entity=2,index=0,forward=true},{entity=2,index=0,forward=false,reversal=true},{entity=1,index=0,forward=false}}}
local run={loop=loop,edgeCursor=1,speed=0,ghost=1,locoYaw=0,vehicleEntity=5}
local phases, last = {}, nil
for i=1,3000 do
  local done = M.adv(run,0.1)
  if run.phase ~= last then phases[#phases+1]=tostring(run.phase); last=run.phase end
  if run.phase=="flip" and not run.flipDone then run.flipDone=true; run.phase="settle"; run.settleTicks=0; run.flipped=true end  -- what flipRun's callback does
  if done then break end
end
print(table.concat(phases," > "))
assert(table.concat(phases," > ")=="flip > settle > approach > finish", "phase order")
print("flow ok")
