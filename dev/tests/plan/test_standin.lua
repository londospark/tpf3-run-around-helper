local names={[10]="r::/res/models/runaround_standin/standin_cm1200.mdl",[11]="r::/res/models/runaround_standin/standin_cm1400.mdl",[12]="r::/res/models/runaround_standin/standin_cm4400.mdl"}
api={res={modelRep={getAll=function() return names end,getAsTable=function(id) return {metadata={extent={bbMax={6.1933,1,1},bbMin={-6.4228,-1,0}}}} end}}}
local M=assert(load(io.open(arg[1]):read("*a").."\nreturn {f=findStandInModelId}","s"))()
assert(M.f(1)==10); print("standin pick ok")
