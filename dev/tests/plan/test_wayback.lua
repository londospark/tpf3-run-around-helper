-- The way back to the station: the ghost sets back along the track to where the
-- loco couples on, brakes to a stop there, and only the last centimetres are
-- glided. If the coupling place isn't on the way back, it glides as before.
math.atan2 = math.atan2 or math.atan
local sent = {}
api={engine={util={transport={calcPosition=function(g,u) return {x=g.x0+u*100,y=0,z=0} end}},
  getComponent=function(e,c) if c=="TN" then return {edges={{geometry={x0=e*1000}}}} end end},
 cmd={makeCustomEntityUpdateTransformationCmd=function(e,t) return t end,sendCommand=function() end,
  makeCustomEntityUpdateStateCmd=function(e,st) sent[#sent+1]=st; return {} end},
 type={ComponentType={TRANSPORT_NETWORK="TN"},Vec3f={distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end,new=function(x,y,z) return {x=x,y=y,z=z} end},Mat4f={rotZTransl=function(yaw,p) return {yaw=yaw,x=p.x,y=p.y} end}}}
LOGS = {}
local src = io.open(arg[1]):read("*a"):gsub("local function logInfo%(", "local function logInfo_unused(", 1)
local M=assert(load("local logInfo = function(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring(select(i,...)) end LOGS[#LOGS+1]=table.concat(t,' ') end\n"..src.."\nreturn {adv=advanceGhost}","s"))()

-- piece 1 runs x = 1000 -> 1100; the route drives it forwards, reverses just
-- clear of the points (10 m in) and sets back: the way back starts at piece 2
local function newRun(target)
  local loop={speed=10,accel=1,backFrom=2,loopEdges={{entity=1,index=0,forward=true},{entity=1,index=0,forward=false,reversal=true}}}
  return {loop=loop,edgeCursor=1,speed=0,ghost=1,locoYaw=0,vehicleEntity=5,effects=true,
    rake={stage="done"},target=target}
end
local function drive(run)
  sent, LOGS = {}, {}
  local phases, minX, lastRouteX = {}, math.huge, nil
  for i=1,5000 do
    local before = run.phase
    local done = M.adv(run,0.05)
    if run.phase ~= before then phases[#phases+1]=tostring(run.phase) end
    if run.phase == nil and run.gx then lastRouteX = run.gx end
    if run.gx and run.headingFlipped then minX = math.min(minX, run.gx) end
    if done then break end
  end
  return phases, lastRouteX, minX
end

-- coupling place on the way back, 6 m in from the points
local run = newRun({x=1004,y=0,z=0})
local phases, routeX, minX = drive(run)
print(table.concat(phases," > "), "stopped on the track at", routeX, "then at", run.gx)
assert(run.backStop ~= nil and run.backStopped, "drove the way back")
assert(math.abs(routeX - 1004) < 0.3, "stopped on the track at the coaches")
assert(math.abs(run.gx - 1004) < 1e-6 and minX > 1003.9, "no overshoot past the coaches")
assert(phases[#phases]=="finish", "ends the run")
local back = false
for _,st in ipairs(sent) do
  if st.state.vx and st.state.vx < -0.01 then back = true; assert(st.state.dir == -1, "setting back: wheels turn backwards") end
  assert(st.state.speed <= 10.0001, "no speed jump in the glide")
end
assert(back, "set back at all")
assert(math.abs((run.driveTotal or 0) - run.gdist) < 0.3, "progress total is where it stops")

-- coupling place off the way back (another track): glides as before
run = newRun({x=1004,y=8,z=0})
phases = drive(run)
assert(run.backStop == nil, "not driven")
local saw = false
for _,l in ipairs(LOGS) do if l:find("glided instead") then saw = true end end
assert(saw, "says why it glides")

-- no ghost rake (the simple sequence): the coupling place isn't known, glides
run = newRun(nil); run.rake = nil
phases = drive(run)
assert(run.backStop == nil and run.phase ~= nil, "simple sequence glides")
print("way back ok")
