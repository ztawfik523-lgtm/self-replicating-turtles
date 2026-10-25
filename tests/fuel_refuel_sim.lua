-- Real fuel.ensure must automatically turn earned charcoal into movement.
package.path='tg/?.lua;'..package.path
local level=40
local slots={
 [3]={name='minecraft:charcoal',count=3},
 [7]={name='minecraft:oak_log',count=4}
}
local selected=7
turtle={
 getFuelLevel=function()return level end,
 getSelectedSlot=function()return selected end,
 select=function(i)selected=i;return true end,
 getItemDetail=function(i)return slots[i]end,
 getItemCount=function(i)return slots[i] and slots[i].count or 0 end,
 refuel=function(n)
  local d=slots[selected]
  if not d or (d.name~='minecraft:coal' and d.name~='minecraft:charcoal')
     or d.count<n then return false end
  d.count=d.count-n
  if d.count==0 then slots[selected]=nil end
  level=level+80*n
  return true
 end,
}
local fuel=dofile('tg/fuel.lua')
assert(fuel.ensure(120))
assert(level==120 and slots[3].count==2)
assert(selected==7,'Auto refuel did not restore selected inventory slot')
assert(fuel.ensure(120) and slots[3].count==2,
 'At desired movement fuel must not burn another charcoal')
assert(fuel.ensure(280) and level==280 and slots[3]==nil,
 'Fuel should consume minimum two remaining charcoal items')
assert(not fuel.ensure(400) and level==280,
 'No fuel cannot claim safe travel budget')
assert(slots[7].name=='minecraft:oak_log',
 'Fuel function consumed harvested tree logs')
print('PASS: earned charcoal fuels movement, not just smelting')
