math.atan2 = math.atan2 or math.atan
local sent, log = {}, {}
local carYaw = math.pi  -- loco physically faces -x
local cfgParts = {{part={modelId=5,reversed=false}},{part={modelId=1,reversed=false}}}
api={engine={getComponent=function(e,c)
   if c=="CL" then return {carriages={11,12}} end
   if c=="MIL" then local y=carYaw return {fatInstances={{transf={cols=function(_,i) return {x=math.cos(y),y=math.sin(y)} end}}}} end
   if c=="TV" then return {transportVehicleConfig={vehicles=cfgParts}} end end},
 cmd={makeVehicleReplaceCmd=function(e,cfg) sent[#sent+1]=cfg return {cfg=cfg} end,
      makeCustomEntityDestroyCmd=function() return "destroy" end,makeVehicleSetManualDepartureCmd=function() return "md" end,makeVehicleTryToDepartCmd=function() return "td" end,
      sendCommand=function(cmd,cb) log[#log+1]=cmd if cb then cb(nil,true) end end},
 type={ComponentType={CARRIAGE_LIST="CL",MODEL_INSTANCE_LIST="MIL",TRANSPORT_VEHICLE="TV"},TransportVehicleConfig={new=function(t) local c={vehicles={}} for i,p in ipairs(t.vehicles) do c.vehicles[i]=p end return c end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {v=verifyRun}","s"))()
local run={vehicleEntity=1,gyaw=0.0,locoAtRear=false,loop={name="x"}}   -- ghost faces +x, loco faces -x: mismatch
local st={get=function() return {} end,set=function() end}; M.v(st, run)
assert(#sent==1 and sent[1].vehicles[1].part.reversed==true, "flag toggled")
carYaw=0.0; sent={}
M.v(st, {vehicleEntity=1,gyaw=0.0,locoAtRear=false,loop={name="x"}})
assert(#sent==0, "no change when matching")
print("verify ok")
