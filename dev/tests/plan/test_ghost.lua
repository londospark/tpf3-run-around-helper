local names={[1]="vehicle/train/br89/br89.mdl",[2]="modx::/foo/baden.mdl",[3]="r::/res/models/runaround_ghost/br89.mdl",[4]="r::/res/models/runaround_ghost/mogul_2_6_0.mdl",[5]="r::/res/models/runaround_ghost/br_e94.mdl",[6]="r::/res/models/runaround_ghost/alco_hh600.mdl"}
local eng={[1]="STEAM",[2]="STEAM"}
api={res={modelRep={getAll=function() return names end,get=function(id) return {metadata={landVehicle={engines={{type=eng[id]}}}}} end}}}
local src=io.open(arg[1]):read("*a").."\nreturn {g=findGhostModelId}"
local M=assert(load(src,"s"))()
assert(M.g(1)==3, "exact"); assert(M.g(2)==4, "steam fallback"); print("ghost lookup ok")
