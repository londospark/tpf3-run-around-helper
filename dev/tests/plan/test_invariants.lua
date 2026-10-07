-- model id -> per-compartment number of load configs
local models = { [4225]={1}, [7777]={1,3}, [4510]={1} }
local function meta(id) local c={} for i,n in ipairs(models[id]) do local lcs={} for j=1,n do lcs[j]={} end c[i]={loadConfigs=lcs} end return {metadata={transportVehicle={compartments=c}}} end
api={type={TransportVehiclePart={new=function() return {part={}} end},LoadConfig={new=function() return {} end},Vec3f={new=function(x,y,z) return {x=x,y=y,z=z} end}},
     res={modelRep={get=function(id) return meta(id) end}}}
local src=io.open(arg[1]):read("*a").."\nreturn {snap=snapshotPart,loco=partFromSnapshot,stand=makeStandInPart}"
local M=assert(load(src,"s"))()
local function live(id,loads,autos) return {part={modelId=id,reversed=false,compartment2loadConfig=loads,color={x=1,y=2,z=3}},autoLoadConfig=autos,purchaseTime=7,maintenanceChange=0,maintenanceState=0.5} end
local failures=0
local function check(label, part)
  local id=part.part.modelId; local comps=models[id]
  local nl=#part.part.compartment2loadConfig
  local ok1 = (nl==#comps)                                   -- compartment2loadConfig.size() == model compartments.size()
  local ok2 = (#part.autoLoadConfig==nl)                     -- autoLoadConfig.size() == compartment2loadConfig.size()
  local ok3=true
  for c,lc in ipairs(part.part.compartment2loadConfig) do if not (lc.loadConfigIndex>=0 and lc.loadConfigIndex<comps[c]) then ok3=false end end
  print(string.format("%-34s compartments=%d autos=%d  sizes-match:%s  autos-match:%s  index-in-range:%s", label, nl, #part.autoLoadConfig, tostring(ok1), tostring(ok2), tostring(ok3)))
  if not (ok1 and ok2 and ok3) then failures=failures+1 end
end
local normal=M.snap(live(4225,{{loadConfigIndex=0}},{true}))
check("normal loco restored", M.loco(normal,true))
check("stand-in (from normal loco)", M.stand(4510,normal))
local modded=M.snap(live(7777,{{loadConfigIndex=0},{loadConfigIndex=2,cargoTypeId=15}},{false,true}))
check("modded 2-compartment loco restored", M.loco(modded,true))
local weird=M.snap(live(4225,{{loadConfigIndex=5}},{}))   -- saved index out of range, no autos saved
check("out-of-range index + empty autos", M.loco(weird,false))
check("stand-in inheriting index 5", M.stand(4510,weird))
print(failures==0 and "ALL INVARIANTS HOLD" or ("FAILURES: "..failures))
