math.atan2 = math.atan2 or math.atan
local sent={}
local carriages={11,12}
api={engine={util={transport={calcPosition=function(g,u) return {x=g.x0+u*100,y=0,z=0} end}},
  getComponent=function(e,c)
    if c=="TN" then return {edges={{geometry={x0=e*1000}}}} end
    if c=="CL" then return {carriages=carriages} end
    if c=="MIL" then return {fatInstances={{transf={cols=function() return {x=500,y=3,z=0} end}}}} end end},
 cmd={makeCustomEntityUpdateTransformationCmd=function(e,t) return t end,sendCommand=function() end,makeCustomEntityUpdateStateCmd=function(e,st) sent[#sent+1]=st; return {} end},
 type={ComponentType={TRANSPORT_NETWORK="TN",CARRIAGE_LIST="CL",MODEL_INSTANCE_LIST="MIL"},Vec3f={distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end,new=function(x,y,z) return {x=x,y=y,z=z} end},Mat4f={rotZTransl=function(yaw,p) return {yaw=yaw,x=p.x,y=p.y} end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {adv=advanceGhost,CONFIG=CONFIG,drive=routeDriveLength}","s"))()
M.CONFIG.reverseBeforeRecouple=true
local loop={speed=20,accel=100,loopEdges={{entity=1,index=0,forward=true},{entity=2,index=0,forward=true},{entity=2,index=0,forward=false,reversal=true},{entity=1,index=0,forward=false}}}
local run={loop=loop,edgeCursor=1,speed=0,ghost=1,locoYaw=0,vehicleEntity=5}
local phases, last, driven = {}, nil, nil
for i=1,3000 do
  local done = M.adv(run,0.1)
  if run.phase ~= last then phases[#phases+1]=tostring(run.phase); last=run.phase end
  if run.phase=="flip" and driven==nil then driven=run.gdist end
  if run.phase=="flip" and not run.flipDone then run.flipDone=true; run.phase="settle"; run.settleTicks=0; run.flipped=true end  -- what flipRun's callback does
  if done then break end
end
print(table.concat(phases," > "))
assert(table.concat(phases," > ")=="flip > settle > approach > finish", "phase order")
-- the card's progress total is what the ghost actually drives (a reversal piece
-- only CLEAR_M in and back, not twice its length)
local expect=M.drive(loop,1,nil)
print(string.format("route driven %.1f m, worked out beforehand %.1f m", driven, expect))
assert(math.abs(driven-expect)<0.5, "progress total matches the drive")
-- the approach glide turns the wheels the way it actually moves: a route that
-- ends driving forwards, past the points, then glides back to the coaches
local function approachDirs(run)
  sent={}
  for i=1,3000 do
    local done=M.adv(run,0.1)
    if run.phase=="flip" and not run.flipDone then run.flipDone=true; run.phase="settle"; run.settleTicks=0; run.flipped=true end
    if done then break end
  end
  local dirs={}
  for _,st in ipairs(sent) do if st.state and st.state.speed>0 and st.state.vx<0 then dirs[st.state.dir]=true end end
  return dirs
end
local d1=approachDirs({loop={speed=20,accel=100,loopEdges={{entity=1,index=0,forward=true}}},edgeCursor=1,speed=0,ghost=1,locoYaw=0,vehicleEntity=5,effects=true})
assert(d1[-1] and not d1[1], "no reversal in the route: the glide back is backwards")
local d2=approachDirs({loop=loop,edgeCursor=1,speed=0,ghost=1,locoYaw=0,vehicleEntity=5,effects=true})
assert(d2[-1] and not d2[1], "with a reversal in the route: still backwards")
print("approach wheel direction ok")
print("flow ok")
