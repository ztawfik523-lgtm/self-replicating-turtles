-- Reject invalid chestless first-birth kit; then exercise staged chest item.
-- Unlike earlier tests, chest bootstrap uses realistic 16 inventory slots,
-- transferTo and turtle.craft(1).
package.path='tg/?.lua;'..package.path
local inventory={}
local world={front='minecraft:dirt',bottom='minecraft:dirt'}
local chosen=1
local born=0
local function get(i) return inventory[i] end
local function count(name)
 local total=0
 for i=1,16 do local d=get(i)
  if d and d.name==name then total=total+d.count end
 end
 return total
end
local function put(name,n)
 for i=1,16 do
  local d=get(i)
  if d and d.name==name and d.count+n<=64 then
   d.count=d.count+n;return
  end
 end
 for i=1,16 do
  if not get(i) then inventory[i]={name=name,count=n};return end
 end
 error('Inventory full adding '..name)
end
local function consume(name,n)
 assert(count(name)>=n,'Not enough '..name)
 for i=1,16 do
  local d=get(i)
  if d and d.name==name and n>0 then
   local take=math.min(n,d.count)
   d.count=d.count-take;n=n-take
   if d.count==0 then inventory[i]=nil end
  end
 end
 assert(n==0)
end
local starting={
 {'minecraft:raw_iron',7},{'minecraft:coal',8},
 {'minecraft:cobblestone',22},{'minecraft:redstone',3},
 {'minecraft:sand',6},{'minecraft:diamond',3},
 {'minecraft:oak_planks',22},
}
local positions={1,2,3,5,6,7,9}
for i,v in ipairs(starting) do inventory[positions[i]]={name=v[1],count=v[2]} end
turtle={
 getItemDetail=function(i)return get(i) end,
 getItemCount=function(i)return get(i) and get(i).count or 0 end,
 getItemSpace=function(i)return get(i) and (64-get(i).count) or 64 end,
 getSelectedSlot=function()return chosen end,
 select=function(i)chosen=i;return true end,
 transferTo=function(target,n)
  local from=get(chosen);if not from then return false end
  local dest=get(target)
  if dest and dest.name~=from.name then return false end
  local amount=math.min(from.count,n or from.count,64-(dest and dest.count or 0))
  if amount<=0 then return false end
  if not dest then inventory[target]={name=from.name,count=amount}
  else dest.count=dest.count+amount end
  from.count=from.count-amount
  if from.count==0 then inventory[chosen]=nil end
  return true
 end,
 craft=function(n)
  local recipe={1,2,3,5,7,9,10,11}
  for _,i in ipairs(recipe) do
   local d=get(i)
   if not d or d.name~='minecraft:oak_planks' or d.count~=1 then
    return false,'Wrong initial chest recipe at slot '..i
   end
  end
  if get(6) then return false,'Chest center obstructed' end
  if n==0 then return true end
  for _,i in ipairs(recipe) do inventory[i]=nil end
  assert(chosen==6,'Output slot needs to be empty center')
  inventory[6]={name='minecraft:chest',count=1}
  return true
 end,
 inspect=function()return world.front~=nil,world.front and {name=world.front} end,
 inspectDown=function()return world.bottom~=nil,world.bottom and {name=world.bottom} end,
 dig=function()
  assert(world.front~='computercraft:disk_drive')
  if world.front=='minecraft:furnace' then put('minecraft:furnace',1) end
  world.front=nil;return true
 end,
 digDown=function()world.bottom=nil;return true end,
 place=function()
  local d=assert(get(chosen))
  assert(world.front==nil)
  assert(d.name=='minecraft:furnace' or d.name=='computercraft:disk_drive')
  world.front=d.name;consume(d.name,1);return true
 end,
 placeDown=function()
  assert(world.bottom==nil)
  assert(get(chosen) and get(chosen).name=='minecraft:chest')
  world.bottom='minecraft:chest';consume('minecraft:chest',1);return true
 end
}
peripheral={wrap=function(side)
 local installed=(side=='bottom' and world.bottom=='minecraft:chest')
     or (side=='front' and world.front=='minecraft:furnace')
 if installed then return {list=function()return {} end} end
end}
local st={data={pose={x=0,y=0,z=0,dir=0},children=0},
 save=function()end,assertSafe=function()end}
package.loaded.state=st
package.loaded.factory={
 equipCrafting=function()return true end,
 collect=function()return true end,
 craftStep=function(_,pattern,output)
  assert(world.bottom=='minecraft:chest')
  local wanted={}
  for _,name in pairs(pattern) do wanted[name]=(wanted[name] or 0)+1 end
  for name,n in pairs(wanted) do consume(name,n) end
  put(output,output=='minecraft:glass_pane' and 16 or 1)
 end,
 make=function()
  assert(world.bottom=='minecraft:chest' and world.front=='computercraft:disk_drive')
  for name,n in pairs({
    ['minecraft:oak_planks']=14,['minecraft:stone']=7,
    ['minecraft:iron_ingot']=7,['minecraft:redstone']=1,
    ['minecraft:glass_pane']=1,['minecraft:diamond']=3
  }) do consume(name,n) end
  put('computercraft:turtle_normal',1)
  return true
 end
}
package.loaded.process={
 run=function(kind)
  assert(world.front=='minecraft:furnace')
  local recipes={iron={'minecraft:raw_iron','minecraft:iron_ingot'},
    stone={'minecraft:cobblestone','minecraft:stone'},
    glass={'minecraft:sand','minecraft:glass'}}
  local r=assert(recipes[kind])
  local amount=count(r[1])
  assert(amount>0)
  consume(r[1],amount)
  consume('minecraft:coal',math.ceil(amount/8))
  put(r[2],amount)
 end
}
package.loaded.replicate={
 lab=function()
  assert(world.front=='computercraft:disk_drive')
  assert(count('computercraft:turtle_normal')==1)
  consume('computercraft:turtle_normal',1)
  consume('minecraft:coal',4)
  born=born+1;st.data.children=st.data.children+1
 end
}
local w=dofile('tg/workshop.lua')
assert(count('minecraft:chest')==0)
local ok,reason=pcall(w.run,'controller:1')
assert(not ok and tostring(reason):find('chest'))
assert(born==0 and st.data.birth==nil)
put('minecraft:chest',1)
consume('minecraft:oak_planks',8) -- initial mixed kit needs only 14 planks
assert(w.run('controller:1')==true)
assert(born==1)
assert(world.bottom=='minecraft:chest')
assert(world.front=='computercraft:disk_drive')
assert(st.data.birth==nil)
assert(count('minecraft:oak_planks')==0)
-- The worker can lose its final journal write after a successful birth.
-- Re-running the same job ID must acknowledge completion, not clone again.
assert(w.run('controller:1'))
assert(born==1)
print('PASS: chest item required; starter kit -> placed worksite -> offspring')
