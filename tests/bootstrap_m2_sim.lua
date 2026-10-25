-- M2 integrated mock landscape: two trees, sand bank, shallow stone shaft.
-- Uses real bootstrap.lua and nav.lua; mocks only Minecraft APIs and already
-- verified chest-backed crafting/furnace primitives.
package.path='tg/?.lua;'..package.path
local slots={}
local sel=1
local d={pose={x=0,y=0,z=0,dir=0},moves=0,children=0}
local physical={x=0,y=0,z=0,dir=0}
local world={chest=false,furnace=false,worksiteSapling=false}
local stored={}
local trees={['0:1']=4,['4:0']=4}
local cut={}
local sand={}
for x=1,3 do sand[x..':0']=true end
for x=-3,-1 do sand[x..':0']=true end
local stoneDepth=0
local moves=0
local extraMovementFuel=0
local function key(x,z)return x..':'..z end
local dirs={{0,1},{1,0},{0,-1},{-1,0}}
local function front()
 local v=dirs[physical.dir+1]
 return physical.x+v[1],physical.z+v[2]
end
local function item(i)return slots[i]end
local function add(name,n)
 for i=1,16 do
  if slots[i] and slots[i].name==name and slots[i].count+n<=64 then
   slots[i].count=slots[i].count+n;return true
  end
 end
 for i=1,16 do
  if not slots[i] then slots[i]={name=name,count=n};return true end
 end
 error('Inventory overflow: '..name)
end
local function count(name)
 local n=0;for i=1,16 do
  if slots[i] and slots[i].name==name then n=n+slots[i].count end
 end
 return n
end
local function spend(name,n)
 assert(count(name)>=n,'Short: '..name)
 for i=1,16 do
  local a=slots[i]
  if a and a.name==name then
   local amount=math.min(n,a.count)
   a.count=a.count-amount;n=n-amount
   if a.count==0 then slots[i]=nil end
  end
 end
 assert(n==0)
end
local function blockFront()
 local x,z=front()
 if world.furnace and physical.x==0 and physical.z==0 and physical.dir==0 then
  return 'minecraft:furnace'
 end
 if world.worksiteSapling and physical.x==0 and physical.z==0 and physical.dir==0 then
  return 'minecraft:oak_sapling'
 end
 if physical.y==0 and x==1 and z==0 and sand['1:0'] then
  return 'minecraft:sand'
 end
 if physical.y>=0 and trees[key(x,z)] and physical.y<trees[key(x,z)]
    and not cut[key(x,z)..':'..physical.y] then
  return 'minecraft:oak_log'
 end
 return nil
end
local function below()
 if physical.x==0 and physical.z==0 and physical.y==0 and world.chest then
  return 'minecraft:chest'
 end
 if physical.y==0 and sand[key(physical.x,physical.z)] then return 'minecraft:sand' end
 if physical.x==0 and physical.z==2 and physical.y<=0 and physical.y>-17 then
  return 'minecraft:stone'
 end
 if physical.y==0 then return 'minecraft:grass_block' end
 return nil
end
turtle={
 getItemDetail=function(i)return item(i) end,
 getItemCount=function(i)return item(i) and item(i).count or 0 end,
 getItemSpace=function(i)return item(i) and 64-item(i).count or 64 end,
 getSelectedSlot=function()return sel end,
 select=function(i)sel=i;return true end,
 getFuelLevel=function()return 1200-moves+extraMovementFuel end,
 inspect=function()
  local n=blockFront()
  return n~=nil,n and {name=n} or nil
 end,
 inspectDown=function()
  local n=below()
  return n~=nil,n and {name=n} or nil
 end,
 inspectUp=function()
  local n=(trees[key(physical.x,physical.z)] and physical.y+1<trees[key(physical.x,physical.z)]
    and not cut[key(physical.x,physical.z)..':'..(physical.y+1)])
      and 'minecraft:oak_log' or nil
  return n~=nil,n and {name=n} or nil
 end,
 detect=function()return blockFront()~=nil end,
 forward=function()
  if blockFront() then return false,'blocked' end
  local x,z=front();physical.x=x;physical.z=z;moves=moves+1
  return true
 end,
 back=function()
  local v=dirs[physical.dir+1]
  physical.x=physical.x-v[1];physical.z=physical.z-v[2];moves=moves+1
  return true
 end,
 up=function()physical.y=physical.y+1;moves=moves+1;return true end,
 down=function()physical.y=physical.y-1;moves=moves+1;return true end,
 turnRight=function()physical.dir=(physical.dir+1)%4;return true end,
 turnLeft=function()physical.dir=(physical.dir+3)%4;return true end,
 dig=function()
  local x,z=front()
  local n=trees[key(x,z)]
  if n and physical.y<n then
   -- Mark harvested log at the current height, while keeping upper logs.
   cut[key(x,z)..':'..physical.y]=true
   add('minecraft:oak_log',1)
   if x==0 and z==1 and physical.y==0 then add('minecraft:oak_sapling',1) end
   return true
  end
  if physical.y==0 and x==1 and z==0 and sand['1:0'] then
   sand['1:0']=nil
   add('minecraft:sand',1)
  end
  return true
 end,
 digUp=function()
  cut[key(physical.x,physical.z)..':'..(physical.y+1)]=true
  add('minecraft:oak_log',1)
  return true
 end,
 digDown=function()
  local n=below()
  if n=='minecraft:sand' then
   sand[key(physical.x,physical.z)]=nil
   add('minecraft:sand',1)
  elseif n=='minecraft:stone' then
   add('minecraft:cobblestone',1)
   stoneDepth=stoneDepth+1
  elseif n=='minecraft:grass_block' then
   add('minecraft:dirt',1)
  elseif n=='minecraft:chest' then error('Attempted to destroy base chest') end
  return true
 end,
 transferTo=function(dst,amount)
  local from=slots[sel]
  if not from then return false end
  local to=slots[dst]
  if to and to.name~=from.name then return false end
  local n=math.min(amount or from.count,from.count,to and 64-to.count or 64)
  if n==0 then return false end
  if not to then slots[dst]={name=from.name,count=n}
  else to.count=to.count+n end
  from.count=from.count-n
  if from.count==0 then slots[sel]=nil end
  return true
 end,
 drop=function()
  slots[sel]=nil;return true
 end,
 dropDown=function()
  assert(world.chest,'No storage to drop into')
  local d=slots[sel]
  if d then stored[d.name]=(stored[d.name] or 0)+d.count end
  slots[sel]=nil
  return true
 end,
 craft=function(n)
  if item(1) and item(1).name=='minecraft:oak_log' then
   local amount=n or 1
   spend('minecraft:oak_log',amount)
   assert(not item(16),'Output slot obstructed')
   slots[16]={name='minecraft:oak_planks',count=4*amount}
   return true
  end
  local recipe={1,2,3,5,7,9,10,11}
  for _,i in ipairs(recipe) do
   assert(item(i) and item(i).name=='minecraft:oak_planks')
  end
  assert(not item(6),'Chest grid center is not empty')
  if n==0 then return true end -- turtle.craft(0) checks without consuming
  spend('minecraft:oak_planks',8)
  slots[16]={name='minecraft:chest',count=1}
  return true
 end,
 placeDown=function()
  assert(item(sel) and item(sel).name=='minecraft:chest')
  assert(physical.x==0 and physical.z==0)
  world.chest=true;spend('minecraft:chest',1);return true
 end,
 place=function()
  if item(sel) and item(sel).name=='minecraft:oak_sapling' then
   world.worksiteSapling=true
   spend('minecraft:oak_sapling',1)
   return true
  end
  if item(sel) and item(sel).name=='minecraft:furnace' then
   world.furnace=true;spend('minecraft:furnace',1);return true
  end
  return false
 end,
}
package.loaded.state={data=d,save=function()end,
 assertSafe=function()assert(not d.pending)end}
package.loaded.fuel={level=function()return turtle.getFuelLevel()end,
 ensure=function(n)
  while turtle.getFuelLevel()<n and count('minecraft:charcoal')>0 do
   spend('minecraft:charcoal',1)
   extraMovementFuel=extraMovementFuel+80
  end
  return turtle.getFuelLevel()>=n
 end}
peripheral={wrap=function(side)
 if side=='bottom' and world.chest then
  return {list=function()
   local result={}
   local i=1
   for name,n in pairs(stored) do
    if n>0 then result[i]={name=name,count=n};i=i+1 end
   end
   return result
  end}
 end
end}
package.loaded.factory={
 collect=function()
  for name,n in pairs(stored) do
   if n>0 then add(name,n) end
  end
  stored={}
  return true
 end,
 craftStep=function(label,pattern,out)
  assert(world.chest)
  assert(label=='bootstrap_furnace')
  spend('minecraft:cobblestone',8)
  add(out,1)
 end
}
package.loaded.process={
 run=function(kind)
  assert(kind=='charcoal' and world.furnace and world.chest)
  local logs=count('minecraft:oak_log')
  assert(logs>=1)
  local planks=count('minecraft:oak_planks')
  assert(planks>=logs)
  spend('minecraft:oak_log',logs)
  spend('minecraft:oak_planks',logs)
  add('minecraft:charcoal',logs)
 end
}
local bootstrap=dofile('tg/bootstrap.lua')
-- This is one integrated M2 acceptance simulation with two injected reboot
-- points: one after log-to-plank conversion and one after chest manufacture.
-- Neither interruption may require extra trees or reset the job ID.
local baseCraft=turtle.craft
local basePlace=turtle.placeDown
local stopCraft=true
turtle.craft=function(n)
 if stopCraft and item(1) and item(1).name=='minecraft:oak_planks'
     and item(2) and item(2).name=='minecraft:oak_planks' then
  stopCraft=false
  error('simulated power loss before first chest craft')
 end
 return baseCraft(n)
end
local ok,reason=pcall(bootstrap.run,'10:initial')
assert(not ok and tostring(reason):find('power loss'))
assert(count('minecraft:oak_planks')>=8)
assert(not world.chest)
turtle.craft=baseCraft
local stopPlacement=true
turtle.placeDown=function()
 if stopPlacement then
  stopPlacement=false
  error('simulated power loss after first chest craft')
 end
 return basePlace()
end
ok,reason=pcall(bootstrap.run,'10:initial')
assert(not ok and tostring(reason):find('power loss'))
assert(count('minecraft:chest')>=1)
assert(not world.chest)
turtle.placeDown=basePlace
-- A power cut after furnace ingredients are staged below, but before
-- turtle.craft, must retrieve those cobblestone and rebuild from the SAME job.
local normalCraft=package.loaded.factory.craftStep
local breakFurnace=true
package.loaded.factory.craftStep=function(label,pattern,out)
 if label=='bootstrap_furnace' and breakFurnace then
  breakFurnace=false
  spend('minecraft:cobblestone',8)
  stored['minecraft:cobblestone']=(stored['minecraft:cobblestone'] or 0)+8
  error('simulated power loss while staging furnace recipe')
 end
 return normalCraft(label,pattern,out)
end
local okFurnace,whyFurnace=pcall(bootstrap.run,'10:initial')
assert(not okFurnace and tostring(whyFurnace):find('power loss'))
assert(d.bootstrap.stage=='craft_bootstrap_furnace')
assert(stored['minecraft:cobblestone']==8)
package.loaded.factory.craftStep=normalCraft

-- Resume a single partially completed furnace batch rather than mining the
-- eight construction cobblestone again or harvesting additional logs.
local baseSmelt=package.loaded.process.run
local stopSmelt=true
package.loaded.process.run=function(kind)
 if stopSmelt then
  stopSmelt=false
  d.processing={kind=kind,stage='smelting'}
  error('simulated power loss in charcoal furnace')
 end
 return baseSmelt(kind)
end
package.loaded.process.resume=function()
 assert(d.processing and d.processing.kind=='charcoal')
 d.processing=nil
 baseSmelt('charcoal')
 return true
end
ok,reason=pcall(bootstrap.run,'10:initial')
assert(not ok and tostring(reason):find('power loss'))
assert(d.processing and world.furnace)
assert(bootstrap.run('10:initial'))
assert(d.processing==nil)
assert(d.bootstrap.jobId=='10:initial')
print('PASS: interrupted planks and chest item resume under original job')
assert(d.bootstrap.complete==true)
assert((stored['minecraft:cobblestone'] or 0)==0,
 'Interrupted furnace recipe left ingredient duplicates below')
print('PASS: interrupted furnace crafting recovers staged cobblestone')
assert(world.chest and world.furnace)
assert(not world.worksiteSapling,'Furnace cell must not be replanted')
assert(count('minecraft:charcoal')>=1)
assert(physical.x==0 and physical.y==0 and physical.z==0 and physical.dir==0)
assert(d.pose.x==physical.x and d.pose.y==physical.y and
       d.pose.z==physical.z and d.pose.dir==physical.dir,
       'Navigation tracked pose diverged from physical turtle')
assert(stoneDepth>=8,'No cobblestone mining happened')
assert(cut['0:1:0'] and cut['4:0:0'])
print('PASS: two trees, sand, shallow stone, chest, furnace and charcoal')

-- Replenish fuel at the SAME base after the player/next job consumes it.
assert((stored['minecraft:sand'] or 0)==6,
 'Sand must be retained in chest after bootstrap')
spend('minecraft:charcoal',count('minecraft:charcoal'))
trees['-4:0']=4  -- new reachable tree after prior harvest
assert(bootstrap.fuelCycle('10:renewal:1'))
assert(d.lastFuelJob=='10:renewal:1')
assert(d.fuelCycle==nil)
assert(count('minecraft:charcoal')>=3)
assert(stored['minecraft:sand']==6,
 'Fuel replenishment lost stored sand')
assert(cut['-4:0:0'],'Fuel replenishment did not harvest available tree')
assert(bootstrap.fuelCycle('10:renewal:1'))
assert(count('minecraft:charcoal')>=3,
 'Repeated completion ID should not consume resources')
assert(physical.x==0 and physical.y==0 and physical.z==0 and physical.dir==0)
print('PASS: depleted base fuel is renewed without rebuilding or losing stock')

-- Even with plenty of charcoal remaining, a low-movement-fuel turtle must
-- consume one piece to power the next round trip. No extra tree is needed.
add('minecraft:charcoal',8)
extraMovementFuel=moves-1200+40
assert(turtle.getFuelLevel()==40)
local beforeRefuel=count('minecraft:charcoal')
assert(bootstrap.fuelCycle('10:renewal:2'))
assert(turtle.getFuelLevel()>=120)
assert(count('minecraft:charcoal')==beforeRefuel-1,
 'Low-fuel turtle did not consume exactly one stocked charcoal')
assert(d.lastFuelJob=='10:renewal:2')
print('PASS: established base powers its own movement from saved charcoal')
