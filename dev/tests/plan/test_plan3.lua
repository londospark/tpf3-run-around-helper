-- Nodes: N0 left points, N1 right points, N2 right stub end, N5 loop mid, N6 mid-platform (stop), N7 left stub end
-- Edges start->end: 0 PLa N0->N6, 1 PLb N6->N1, 2 T N1->N2, 3 L1 N1->N5, 4 L2 N5->N0, 5 ML N7->N0
local function node(i) return {entity=1,index=i} end
local defs = { [0]={0,6},[1]={6,1},[2]={1,2},[3]={1,5},[4]={5,0},[5]={7,0} }
local names = {[0]="PLa",[1]="PLb",[2]="T",[3]="L1",[4]="L2",[5]="ML"}
local NE=5
local edges = {}
for i,d in pairs(defs) do edges[i]={conns={node(d[1]),node(d[2])},geometry={idx=i}} end
-- illegal hairpin pairs (both directions), keyed "node:edgeA-edgeB" with edgeA<edgeB
local forbidden = { ["1:1-3"]=true, ["0:0-4"]=true }
local function allowed(nodeIdx, e1, e2)
  if e1==e2 then return false end
  local a,b=math.min(e1,e2),math.max(e1,e2)
  return not forbidden[nodeIdx..":"..a.."-"..b]
end
local components = {
  LINE={stops={{stationGroup=100,station=0,terminal=0}}}, STATION_GROUP={stations={200}},
  STATION={terminals={{vehicleNodeId=node(6),vehicleEdges={{edgeId={entity=1,index=0},param=0.5}}}}},
}
api={
  type={ComponentType={TRANSPORT_NETWORK="TN",LINE="LINE",STATION_GROUP="STATION_GROUP",STATION="STATION"},
        Vec3f={distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end},
        Vec2f={new=function(x,y) return {x=x,y=y} end},
        enum={TransportMode={TRAIN="TRAIN"}}, Mat4f={rotZTransl=function() end}},
  engine={
    getComponent=function(entity,ct)
      if ct=="TN" then local l={} for i=0,NE do l[i+1]=edges[i] end return {edges=l} end
      return components[ct]
    end,
    util={
      transport={calcPosition=function(g,t) return {x=g.idx*200+t*100,y=0,z=0} end},
      octree={findTransportNetworkNodesInCircle=function(c,r)
        local out={} for _,i in ipairs{0,1,2,5,6,7} do out[#out+1]=node(i) end return out end},
      pathfinding={findPathNodeToNode=function(starts,dests)
        local s,d=starts[1].index,dests[1].index
        local q={{node=s,arr=nil,path={}}}; local seen={[s..":x"]=true}
        while #q>0 do
          local cur=table.remove(q,1)
          if cur.node==d and #cur.path>0 then return cur.path end
          if cur.node==d and #cur.path==0 then return {} end
          for i=0,NE do
            local a,b=defs[i][1],defs[i][2]
            local nxt,fwd
            if a==cur.node then nxt,fwd=b,true elseif b==cur.node then nxt,fwd=a,false end
            if nxt and (cur.arr==nil or allowed(cur.node,cur.arr,i)) then
              local key=nxt..":"..i
              if not seen[key] then
                seen[key]=true
                local p={table.unpack(cur.path)}; p[#p+1]={{entity=1,index=i},fwd}
                q[#q+1]={node=nxt,arr=i,path=p}
              end
            end
          end
        end
        return {}
      end}
    }
  }
}
local src=io.open(arg[1]):read("*a").."\nreturn {planRoute=planRoute,getStopNode=getStopNode,recompute=recomputeLoopRoute}"
local M=assert(load(src,"script"))()
local function wp(...) local t={} for _,i in ipairs{...} do t[#t+1]={entity=1,index=i} end return t end
local function fmt(route,info)
  if not route then return "NO ROUTE: "..tostring(info) end
  local parts={}
  for _,e in ipairs(route) do parts[#parts+1]=names[e.index]..(e.forward and "+" or "-")..(e.reversal and "(rev)" or "") end
  return table.concat(parts," ").."  | reversals="..info.reversals
end
local sn,sp=M.getStopNode(50,0)
print("stop node:", sn.entity..":"..sn.index, "pos:", sp and (sp.x..","..sp.y) or "nil")
print("A loose: L1, ML            ", fmt(M.planRoute(wp(3,5),sn,sp)))
print("B loose: L1, PLa           ", fmt(M.planRoute(wp(3,0),sn,sp)))
print("C explicit: T, L1, ML      ", fmt(M.planRoute(wp(2,3,5),sn,sp)))
print("D loose: L1 only (2 pts)   ", fmt(M.planRoute(wp(3,4),sn,sp)))
print("E impossible: same piece twice not adjacent (PLa,PLa)", fmt(M.planRoute(wp(0,0),sn,sp)))
