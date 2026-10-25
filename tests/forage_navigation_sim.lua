-- M2 integrated obstacle and power-loss acceptance for real nav.lua + bootstrap.lua.
-- Stone wall blocks the north ray; the reachable tree is behind it. The
-- turtle must bypass sideways, harvest, retrace and still find floor sand.
package.path='tg/?.lua;'..package.path
local physical={x=0,y=0,z=0,dir=0}
local d={pose={x=0,y=0,z=0,dir=0},moves=0,bootstrap={
 home={x=0,y=0,z=0,dir=0},stage='gather_first_wood'}}
local saves,inject,interrupted=0,true,false
local logs,sand,steps,saplings,cobble,shaftDigs,dirt=0,0,0,0,0,0,0
local capped,opened,dugStone={},{},{}
local leafCut,replanted=false,false
local cut={}
local trees={['0:4']=4}
local dirs={{0,1},{1,0},{0,-1},{-1,0}}
local function key(x,z)return x..':'..z end
local function front()
 local v=dirs[physical.dir+1]
 return physical.x+v[1],physical.z+v[2]
end
local st={data=d}
function st.save()
 saves=saves+1
 -- The movement COMPLETED, and nav.lua has already written the new pose
 -- and breadcrumb while clearing its pending intent. Now a reboot occurs.
 if inject and not d.pending and d.forageTrail
    and #d.forageTrail.moves==2 then
  inject=false;interrupted=true
  error('simulated reboot after safe movement state commit')
 end
end
function st.assertSafe()
 assert(not d.pending,'ambiguous pending physical action')
 assert(not d.trip,'unresolved legacy survey')
end
package.loaded.state=st
package.loaded.fuel={level=function()return 2000-steps end,
 ensure=function(n)return 2000-steps>=n end}
package.loaded.factory={}
package.loaded.process={}
turtle={
 getItemDetail=function(i)
  if i==1 and logs>0 then return {name='minecraft:oak_log',count=logs} end
  if i==2 and sand>0 then return {name='minecraft:sand',count=sand} end
  if i==3 and saplings>0 then return {name='minecraft:oak_sapling',count=saplings} end
  if i==4 and cobble>0 then return {name='minecraft:cobblestone',count=cobble} end
  if i==5 and dirt>0 then return {name='minecraft:dirt',count=dirt} end
  return nil
 end,
 getFuelLevel=function()return 2000-steps end,
 getSelectedSlot=function()return 1 end,
 select=function()return true end,
 inspect=function()
  local x,z=front()
  local n=nil
  if x==0 and z>=1 and z<=2 and physical.y==0 then n='minecraft:stone' end
  if physical.x==0 and physical.z==4 and physical.y>=2
    and x==1 and z==4 and not leafCut then n='minecraft:oak_leaves' end
  if trees[key(x,z)] and physical.y<trees[key(x,z)]
     and not cut[key(x,z)..':'..physical.y] then n='minecraft:oak_log' end
  return n~=nil,n and {name=n} or nil
 end,
 inspectUp=function()
  local n=trees[key(physical.x,physical.z)]
  local y=physical.y+1
  if n and y<n and not cut[key(physical.x,physical.z)..':'..y] then
   return true,{name='minecraft:oak_log'}
  end
  return false
 end,
 inspectDown=function()
  if physical.x==1 and physical.z==0 and physical.y==0 and sand==0 then
   return true,{name='minecraft:sand'}
  end
  local here=key(physical.x,physical.z)
  if physical.y==0 and capped[here] then
   return true,{name='minecraft:dirt'}
  end
  if physical.y==0 and opened[here] then return false end
  if physical.x==0 and physical.z==3 and physical.y<=0 and
      physical.y>-17 and not dugStone[physical.y] then
   return true,{name='minecraft:stone'}
  end
  if physical.y<0 then return true,{name='minecraft:bedrock'} end
  return true,{name='minecraft:grass_block'}
 end,
 detect=function()
  local x,z=front()
  return (x==0 and z>=1 and z<=2 and physical.y==0)
    or (physical.x==0 and physical.z==4 and physical.y>=2
       and x==1 and z==4 and not leafCut)
   or (trees[key(x,z)] and physical.y<trees[key(x,z)]
     and not cut[key(x,z)..':'..physical.y]) or false
 end,
 dig=function()
  local x,z=front()
  if physical.x==0 and physical.z==4 and physical.y>=2
      and x==1 and z==4 and not leafCut then
   leafCut=true;saplings=saplings+1;return true
  end
  assert(trees[key(x,z)] and physical.y<trees[key(x,z)],
   'Explorer attempted to dig protected wall')
  cut[key(x,z)..':'..physical.y]=true
  logs=logs+1
  return true
 end,
 digUp=function()
  cut[key(physical.x,physical.z)..':'..(physical.y+1)]=true
  logs=logs+1
  return true
 end,
 digDown=function()
  local ok,item=turtle.inspectDown()
  assert(ok and item,'Cannot dig void')
  if item.name=='minecraft:sand' then sand=sand+1
  elseif item.name=='minecraft:stone' then
   dugStone[physical.y]=true
   if physical.y==0 then opened[key(physical.x,physical.z)]=true end
   cobble=cobble+1;shaftDigs=shaftDigs+1
  else
   assert(item.name=='minecraft:grass_block',
     'Shaft tried digging protected subsurface '..item.name)
   dirt=dirt+1;opened[key(physical.x,physical.z)]=true
  end
  return true
 end,
 forward=function()
  local x,z=front()
  if (x==0 and z>=1 and z<=2 and physical.y==0)
    or (trees[key(x,z)] and physical.y<trees[key(x,z)]
      and not cut[key(x,z)..':'..physical.y]) then
   return false,'occupied'
  end
  physical.x=x;physical.z=z;steps=steps+1
  return true
 end,
 place=function()
  local x,z=front()
  if x==0 and z==4 and saplings>0 then
   saplings=saplings-1;replanted=true;return true
  end
  return false
 end,
 placeDown=function()
  local here=key(physical.x,physical.z)
  assert(opened[here],'Only a mined shaft can be capped')
  assert(dirt>0 or cobble>8,'No expendable shaft cap')
  if dirt>0 then dirt=dirt-1 else cobble=cobble-1 end
  capped[here]=true
  opened[here]=nil
  return true
 end,
 back=function()
  local v=dirs[physical.dir+1]
  physical.x=physical.x-v[1];physical.z=physical.z-v[2]
  steps=steps+1
  return true
 end,
 up=function()physical.y=physical.y+1;steps=steps+1;return true end,
 down=function()physical.y=physical.y-1;steps=steps+1;return true end,
 turnRight=function()physical.dir=(physical.dir+1)%4;return true end,
 turnLeft=function()physical.dir=(physical.dir+3)%4;return true end,
}
local boot=dofile('tg/bootstrap.lua')
local ok,why=pcall(boot.searchTerrain,'wood',4)
assert(not ok and tostring(why):find('simulated reboot'))
assert(interrupted and d.forageTrail and #d.forageTrail.moves==2)
assert(not d.pending,'A completed movement must not retain pending intent')
assert(physical.x==d.pose.x and physical.z==d.pose.z)
local movementAtReboot=steps
local amount,total=boot.searchTerrain('wood',4)
assert(total==4 and amount==4,'Detour never reached the tree behind stone')
assert(steps>movementAtReboot)
assert(not d.forageTrail,'Successful forage should clear all breadcrumbs')
assert(physical.x==0 and physical.y==0 and physical.z==0 and physical.dir==0)
assert(d.pose.x==0 and d.pose.y==0 and d.pose.z==0 and d.pose.dir==0)
assert(not cut['0:1:0'] and not cut['0:2:0'],
 'Protected two-block-long wall was destroyed')
assert(leafCut and replanted,'No sapling harvested and replanted')
print('PASS: bypass wall, recover from reboot between movement commits, return home')

local a,b=boot.searchTerrain('cobble',8)
assert(a==8 and b==8 and cobble==8,
 'Adaptive shaft failed to mine a hidden safe stone site')
assert(shaftDigs==9 and capped['0:3'] and
       physical.x==0 and physical.y==0 and physical.z==0)
assert(not d.forageTrail,'Shallow mining left unrecovered route steps')
print('PASS: mine safe stone beyond wall; return from vertical shaft')

a,b=boot.searchTerrain('sand',1)
assert(a==1 and b==1,'A sand floor adjacent to obstacle was missed')
assert(physical.x==0 and physical.z==0 and physical.dir==0)
assert(not d.forageTrail)
print('PASS: gather sand on detour and restore original home heading')

-- A crash DURING physical movement cannot safely be distinguished from one
-- just before it. Never silently guess from a saved breadcrumb in this case.
d.pending={action='forward',pose={x=0,y=0,z=0,dir=0}}
local before=steps
ok,why=pcall(boot.searchTerrain,'wood',5)
assert(not ok and tostring(why):find('ambiguous pending physical action'))
assert(steps==before,'Uncertain movement must halt without moving again')
print('PASS: ambiguous in-flight movement halts without location guessing')
