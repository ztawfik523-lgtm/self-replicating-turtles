-- Simulated first-birth worksite and interruption tests, no Minecraft.
package.path='tg/?.lua;'..package.path
local items,world,born,smelts,makes,collectCount,craftingEquips
local function fixture(initial,front,below)
 items={}
 for k,n in pairs(initial) do items[k]=n end
 world={front=front,bottom=below};born=0;smelts={};makes=0
 collectCount,craftingEquips=0,0
 local function count(name)return items[name] or 0 end
 local function plus(name,n)items[name]=count(name)+n end
 local function minus(name,n)assert(count(name)>=n,name..' insufficient');items[name]=count(name)-n end
 local inv={}
 local function inventory()
  inv={}
  for k,n in pairs(items) do if n>0 then inv[#inv+1]={name=k,count=n} end end
  table.sort(inv,function(a,b)return a.name<b.name end)
 end
 local sel=1
 turtle={
  getItemDetail=function(i)inventory();return inv[i]end,
  getSelectedSlot=function()return sel end,
  select=function(i)sel=i;return true end,
  inspect=function()return world.front~=nil,world.front and {name=world.front} or nil end,
  inspectDown=function()return world.bottom~=nil,world.bottom and {name=world.bottom} or nil end,
  placeDown=function()
   inventory();local k=inv[sel] and inv[sel].name
   assert(k=='minecraft:chest' and world.bottom==nil,'chest placement')
   minus(k,1);world.bottom=k;return true
  end,
  place=function()
   inventory();local k=inv[sel] and inv[sel].name
   assert(world.front==nil,'front occupied')
   assert(k=='minecraft:furnace' or k=='computercraft:disk_drive','bad front block')
   minus(k,1);world.front=k;return true
  end,
  dig=function()
   assert(world.front=='minecraft:furnace','only empty furnace may be reclaimed')
   plus('minecraft:furnace',1);world.front=nil;return true
  end,
  digDown=function() world.bottom=nil;return true end,
 }
 peripheral={wrap=function(side)
  if (side=='bottom' and world.bottom=='minecraft:chest')
     or (side=='front' and world.front=='minecraft:furnace') then
   return {list=function()return {} end}
  end
 end}
 local st={data={pose={x=0,y=0,z=0,dir=0}},
   save=function()end,assertSafe=function()end}
 package.loaded.state=st
 package.loaded.factory={
  equipCrafting=function()
   craftingEquips=craftingEquips+1
   return true
  end,
  collect=function()
   -- In the actual runtime this retrieves the ingredients staged below.
   collectCount=collectCount+1
   return true
  end,
  craftStep=function(label,pattern,output)
   assert(world.bottom=='minecraft:chest')
   local needs={}
   for _,k in pairs(pattern)do needs[k]=(needs[k] or 0)+1 end
   for k,n in pairs(needs)do minus(k,n)end
   plus(output,output=='minecraft:glass_pane' and 16 or 1)
  end,
  make=function()
   assert(world.front=='computercraft:disk_drive')
   assert(world.bottom=='minecraft:chest')
   for k,n in pairs({['minecraft:stone']=7,['minecraft:iron_ingot']=7,
      ['minecraft:glass_pane']=1,['minecraft:diamond']=3,
      ['minecraft:redstone']=1,['minecraft:oak_planks']=14})do minus(k,n) end
   plus('computercraft:turtle_normal',1);makes=makes+1
   return true
  end
 }
 package.loaded.process={
  run=function(kind)
   local map={iron={'minecraft:raw_iron','minecraft:iron_ingot'},
    stone={'minecraft:cobblestone','minecraft:stone'},
    glass={'minecraft:sand','minecraft:glass'}}
   assert(world.front=='minecraft:furnace')
   local pair=assert(map[kind])
   local n=count(pair[1]);assert(n>0)
   minus(pair[1],n);minus('minecraft:coal',math.ceil(n/8))
   plus(pair[2],n);smelts[#smelts+1]=kind
   return n
  end,
  resume=function()st.data.processing=nil;return true end
 }
 package.loaded.replicate={
  lab=function()
   assert(world.front=='computercraft:disk_drive')
   minus('computercraft:turtle_normal',1)
   minus('minecraft:coal',4)
   born=born+1;return true
  end
 }
 return dofile('tg/workshop.lua'),st,count
end

local supplies={
 ['minecraft:chest']=1,['minecraft:cobblestone']=22,
 ['minecraft:raw_iron']=7,['minecraft:redstone']=3,
 ['minecraft:sand']=6,['minecraft:diamond']=3,
 ['minecraft:oak_planks']=14,['minecraft:coal']=8
}
local w,state,count=fixture(supplies)
assert(w.run()==true)
assert(born==1 and makes==1)
assert(world.bottom=='minecraft:chest')
assert(world.front=='computercraft:disk_drive')
assert(#smelts==3)
assert(state.data.birth==nil)
assert(count('minecraft:furnace')==1)
print('PASS: starter materials -> workshop -> 3 smelts -> child')

w,state,count=fixture(supplies,'minecraft:furnace','minecraft:chest')
items['minecraft:chest']=0
items['minecraft:raw_iron']=0
items['minecraft:iron_ingot']=7
items['minecraft:cobblestone']=14
items['minecraft:coal']=7
state.data.birth={stage='smelt_stone'}
assert(w.run())
assert(born==1 and #smelts==2,
 'Recovery should skip completed iron processing')
print('PASS: interrupted birth resumes from observed contents')

w,state=fixture(supplies)
items['minecraft:chest']=0
local ok,err=pcall(w.run)
assert(not ok and tostring(err):find('chest'))
assert(state.data.birth==nil)
print('PASS: invalid starter kit leaves state untouched')

w,state,count=fixture(supplies,nil,'minecraft:chest')
items['minecraft:chest']=0
state.data.birth={stage='craft_furnace',jobId='7:13',childrenBefore=0}
assert(w.run('7:13'))
assert(collectCount==1,'Must collect chest supplies before recreating recipe')
assert(craftingEquips>=1,'Must activate crafting before first recipe')
print('PASS: interrupted furnace grid recovers staging and crafting first')
