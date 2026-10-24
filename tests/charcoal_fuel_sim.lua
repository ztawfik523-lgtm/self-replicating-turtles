-- Exercises REAL tg/process.lua charcoal startup without coal or charcoal.
package.path='tg/?.lua;'..package.path
local turtleSlots={
 [1]={name='minecraft:oak_log',count=3},
 [2]={name='minecraft:oak_planks',count=3}}
local chestSlots,furnaceSlots={},{}
local selected=1
local time=0
local function firstEmpty(t)
 for i=1,27 do if not t[i] then return i end end
 error('inventory full')
end
local function insert(t,slot,name,n)
 if not t[slot] then t[slot]={name=name,count=n}
 else
  assert(t[slot].name==name)
  t[slot].count=t[slot].count+n
 end
end
local function take(t,slot,n)
 local a=t[slot];assert(a and a.count>=n,'Missing item in slot '..slot)
 local name=a.name
 a.count=a.count-n
 if a.count==0 then t[slot]=nil end
 return name
end
local function qty(t,name)
 local n=0;for _,d in pairs(t) do if d.name==name then n=n+d.count end end
 return n
end
local function smelt()
 if furnaceSlots[1] and furnaceSlots[2] then
  local logs=furnaceSlots[1].count
  local fuel=furnaceSlots[2]
  local per=(fuel.name=='minecraft:coal' or fuel.name=='minecraft:charcoal')
       and 8 or 1
  local amount=math.min(logs,fuel.count*per)
  take(furnaceSlots,1,amount)
  take(furnaceSlots,2,math.ceil(amount/per))
  insert(furnaceSlots,3,'minecraft:charcoal',amount)
 end
end
local chestPeripheral={
 list=function()return chestSlots end,
 pushItems=function(side,slot,n,dest)
  assert(side=='front')
  local a=assert(chestSlots[slot])
  local amount=math.min(a.count,n)
  local name=take(chestSlots,slot,amount)
  insert(furnaceSlots,dest,name,amount)
  smelt()
  return amount
 end,
}
local furnacePeripheral={
 list=function()return furnaceSlots end,
 size=function()return 3 end,
 getItemDetail=function(slot)return furnaceSlots[slot]end,
 pushItems=function(side,slot,n)
  assert(side=='bottom')
  local d=assert(furnaceSlots[slot])
  local amount=math.min(n,d.count)
  local name=take(furnaceSlots,slot,amount)
  insert(chestSlots,firstEmpty(chestSlots),name,amount)
  return amount
 end,
}
peripheral={wrap=function(side)
 if side=='front' then return furnacePeripheral
 elseif side=='bottom' then return chestPeripheral end
end}
turtle={
 inspect=function()return true,{name='minecraft:furnace'}end,
 inspectDown=function()return true,{name='minecraft:chest'}end,
 getItemDetail=function(slot)return turtleSlots[slot]end,
 getItemCount=function(slot)return turtleSlots[slot] and turtleSlots[slot].count or 0 end,
 getSelectedSlot=function()return selected end,
 select=function(n)selected=n;return true end,
 dropDown=function(n)
  local a=assert(turtleSlots[selected])
  local amount=math.min(a.count,n or a.count)
  local name=take(turtleSlots,selected,amount)
  insert(chestSlots,firstEmpty(chestSlots),name,amount)
  return true
 end,
 suckDown=function(n)
  local slot
  for i=1,27 do if chestSlots[i] then slot=i;break end end
  if not slot then return false end
  local a=chestSlots[slot]
  local amount=math.min(n or a.count,a.count)
  local name=take(chestSlots,slot,amount)
  insert(turtleSlots,selected,name,amount)
  return true
 end,
}
local st={data={},save=function()end,assertSafe=function()end}
package.loaded.state=st
package.loaded.log={event=function()end}
local epoch=os.epoch
os.epoch=function()time=time+200;return time end
sleep=function()end
local process=dofile('tg/process.lua')
local produced=process.run('charcoal')
assert(produced==3)
assert(qty(turtleSlots,'minecraft:charcoal')==3)
assert(qty(turtleSlots,'minecraft:coal')==0)
assert(qty(turtleSlots,'minecraft:oak_planks')==0)
assert(qty(chestSlots,'minecraft:charcoal')==0)
assert(not next(furnaceSlots))
assert(st.data.processing==nil)
print('PASS: actual furnace processor turns logs+planks into charcoal without coal')

-- Existing coal must take precedence over wooden fuel, preserving planks.
turtleSlots={
 [1]={name='minecraft:oak_log',count=3},
 [2]={name='minecraft:oak_planks',count=3},
 [3]={name='minecraft:coal',count=1}}
chestSlots={};furnaceSlots={};selected=1
assert(process.run('charcoal')==3)
assert(qty(turtleSlots,'minecraft:charcoal')==3)
assert(qty(turtleSlots,'minecraft:oak_planks')==3)
assert(qty(turtleSlots,'minecraft:coal')==0)
assert(not next(chestSlots) and not next(furnaceSlots))
print('PASS: charcoal keeps planks when coal is already available')

os.epoch=epoch
