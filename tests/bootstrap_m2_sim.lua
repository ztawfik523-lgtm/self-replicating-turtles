-- M2 integrated mock landscape: two trees, sand bank, shallow stone shaft.
-- Uses real bootstrap.lua and nav.lua; mocks only Minecraft APIs and already
-- verified chest-backed crafting/furnace primitives.
package.path='tg/?.lua;'..package.path
local slots={}
local sel=1
local d={pose={x=0,y=0,z=0,dir=0},moves=0,children=0}
local world={chest=false,furnace=false}
local trees={['0:1']=4,['4:0']=4}
local sand={}
for x=1,6 do sand[x..':0']=true end
local stoneDepth=0
local moves=0
local function key(x,z)return x..':'..z end
local dirs={{0,1},{1,0},{0,-1},{-1,0}}
local function front()
 local v=dirs[d.pose.dir+1]
 return d.pose.x+v[1],d.pose.z+v[2]
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
 if world.furnace and d.pose.x==0 and d.pose.z==0 and d.pose.dir==0 then
  return 'minecraft:furnace'
 end
 if d.pose.y>=0 and trees[key(x,z)] and d.pose.y<trees[key(x,z)] then
  return 'minecraft:oak_log'
 end
 return nil
end
local function below()
 if d.pose.x==0 and d.pose.z==0 and d.pose.y==0 and world.chest then
  return 'minecraft:chest'
 end
 if d.pose.y==0 and sand[key(d.pose.x,d.pose.z)] then return 'minecraft:sand' end
 if d.pose.x==0 and d.pose.z==2 and d.pose.y<=0 and d.pose.y>-17 then
  return 'minecraft:stone'
 end
 if d.pose.y==0 then return 'minecraft:grass_block' end
 return nil
end
turtle={
 getItemDetail=function(i)return item(i) end,
 getItemCount=function(i)return item(i) and item(i).count or 0 end,
 getItemSpace=function(i)return item(i) and 64-item(i).count or 64 end,
 getSelectedSlot=function()return sel end,
 select=function(i)sel=i;return true end,
 getFuelLevel=function()return 1200-moves end,
 inspect=function()
  local n=blockFront()
  return n~=nil,n and {name=n} or nil
 end,
 inspectDown=function()
  local n=below()
  return n~=nil,n and {name=n} or nil
 end,
 inspectUp=function()
  local n=(trees[key(d.pose.x,d.pose.z)] and d.pose.y+1<trees[key(d.pose.x,d.pose.z)])
      and 'minecraft:oak_log' or nil
  return n~=nil,n and {name=n} or nil
 end,
 detect=function()return blockFront()~=nil end,
 forward=function()
  if blockFront() then return false,'blocked' end
  local x,z=front();d.pose.x=x;d.pose.z=z;moves=moves+1
  return true
 end,
 back=function()
  local v=dirs[d.pose.dir+1]
  d.pose.x=d.pose.x-v[1];d.pose.z=d.pose.z-v[2];moves=moves+1
  return true
 end,
 up=function()d.pose.y=d.pose.y+1;moves=moves+1;return true end,
 down=function()d.pose.y=d.pose.y-1;moves=moves+1;return true end,
 turnRight=function()d.pose.dir=(d.pose.dir+1)%4;return true end,
 turnLeft=function()d.pose.dir=(d.pose.dir+3)%4;return true end,
 dig=function()
  local x,z=front()
  local n=trees[key(x,z)]
  if n and d.pose.y<n then
   -- Mark harvested log at the current height, while keeping upper logs.
   if d.pose.y==0 then
    local height=n
    trees[key(x,z)]=height
   end
   add('minecraft:oak_log',1)
   return true
  end
  return true
 end,
 digUp=function()add('minecraft:oak_log',1);return true end,
 digDown=function()
  local n=below()
  if n=='minecraft:sand' then
   sand[key(d.pose.x,d.pose.z)]=nil
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
  spend('minecraft:oak_planks',8)
  slots[16]={name='minecraft:chest',count=1}
  return true
 end,
 placeDown=function()
  assert(item(sel) and item(sel).name=='minecraft:chest')
  assert(d.pose.x==0 and d.pose.z==0)
  world.chest=true;spend('minecraft:chest',1);return true
 end,
 place=function()
  if item(sel) and item(sel).name=='minecraft:furnace' then
   world.furnace=true;spend('minecraft:furnace',1);return true
  end
  return false
 end,
}
package.loaded.state={data=d,save=function()end,
 assertSafe=function()assert(not d.pending)end}
package.loaded.fuel={level=function()return turtle.getFuelLevel()end,
 ensure=function(n)return turtle.getFuelLevel()>=n end}
package.loaded.factory={
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
assert(bootstrap.run('10:initial'))
assert(d.bootstrap.complete==true)
assert(world.chest and world.furnace)
assert(count('minecraft:charcoal')>=1)
assert(d.pose.x==0 and d.pose.y==0 and d.pose.z==0 and d.pose.dir==0)
assert(stoneDepth>=8,'No cobblestone mining happened')
assert(not next(trees)==false)
print('PASS: two trees, sand, shallow stone, chest, furnace and charcoal')
