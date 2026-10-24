-- Runs the real factory upgrade helper (not a mock of equipCrafting).
package.path='tg/?.lua;'..package.path
package.loaded.state={data={},save=function()end}
package.loaded.log={}
local factory=dofile('tg/factory.lua')
local inventory={[3]={name='minecraft:crafting_table',count=1}}
local selected=10
local left=nil
local right={name='minecraft:diamond_pickaxe'}
local equips=0
turtle={
 getSelectedSlot=function()return selected end,
 select=function(n)selected=n;return true end,
 getItemDetail=function(n)return inventory[n]end,
 getEquippedLeft=function()return left end,
 getEquippedRight=function()return right end,
 equipLeft=function()
  assert(selected==3)
  assert(inventory[selected].name=='minecraft:crafting_table')
  left=inventory[selected];inventory[selected]=nil
  turtle.craft=function()return true end
  equips=equips+1
  return true
 end,
 equipRight=function()error('Would replace mining upgrade')end,
}
assert(factory.equipCrafting())
assert(type(turtle.craft)=='function')
assert(left.name=='minecraft:crafting_table' and
 right.name=='minecraft:diamond_pickaxe')
assert(inventory[3]==nil and selected==10 and equips==1)
assert(factory.equipCrafting() and equips==1)
print('PASS: crafting table equipped automatically without disturbing pickaxe')
turtle.craft=nil
left=nil
inventory[3]=nil
local ok,why=pcall(factory.equipCrafting)
assert(not ok and tostring(why):find('Put one crafting table'))
print('PASS: missing table fails before changing inventory')
