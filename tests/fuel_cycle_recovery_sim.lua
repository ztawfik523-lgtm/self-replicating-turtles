-- One consolidated M2 recovery regression: resume before chest collection,
-- do not falsely complete after a failed deposit, and fail capacity preflight.
package.path='tg/?.lua;'..package.path
local slot={}
local stored={{name='minecraft:sand',count=6}}
local selected=1
local resumed,collects,deposits,failDeposit=false,0,0,true
local saved=0
local state={data={
 pose={x=0,y=0,z=0,dir=0},
 bootstrap={complete=true,home={x=0,y=0,z=0,dir=0}},
 processing={kind='charcoal',stage='smelting'}
},save=function()saved=saved+1 end,assertSafe=function()end}
package.loaded.state=state
package.loaded.nav={}
package.loaded.fuel={}
local function insert(name,count)
 for i=1,16 do
  if not slot[i] then slot[i]={name=name,count=count};return end
 end
 error('mock turtle inventory full')
end
local function count(name)
 local n=0
 for i=1,16 do
  if slot[i] and slot[i].name==name then n=n+slot[i].count end
 end
 return n
end
turtle={
 getSelectedSlot=function()return selected end,
 select=function(i)selected=i;return true end,
 getItemDetail=function(i)return slot[i] end,
 getItemCount=function(i)return slot[i] and slot[i].count or 0 end,
 inspect=function()return true,{name='minecraft:furnace'} end,
 inspectDown=function()return true,{name='minecraft:chest'} end,
 dropDown=function()
  local item=slot[selected]
  assert(item,'nothing to deposit')
  deposits=deposits+1
  if failDeposit then return false end
  stored[#stored+1]={name=item.name,count=item.count}
  slot[selected]=nil
  return true
 end
}
peripheral={wrap=function(side)
 assert(side=='bottom','unexpected peripheral')
 return {list=function()
  local contents={}
  for i,item in ipairs(stored) do contents[i]={name=item.name,count=item.count} end
  return contents
 end}
end}
package.loaded.process={
 resume=function()
  assert(not resumed,'interrupted smelt repeated')
  assert(#stored==1 and stored[1].name=='minecraft:sand',
   'Chest was emptied BEFORE interrupted smelt could resume')
  resumed=true
  state.data.processing=nil
  insert('minecraft:charcoal',3)
  return true
 end
}
package.loaded.factory={
 collect=function()
  assert(resumed,'Factory must not collect a furnace staging chest before recovery')
  collects=collects+1
  for _,item in ipairs(stored) do insert(item.name,item.count) end
  stored={}
  return true
 end
}
local base=dofile('tg/bootstrap.lua')
local ok,reason=pcall(base.fuelCycle,'10:recovery')
assert(not ok and tostring(reason):find('Cannot deposit') or
       (not ok and tostring(reason):find('Storage chest full')),
 'Missing expected final storage failure: '..tostring(reason))
assert(resumed and collects==1 and deposits==1)
assert(not state.data.lastFuelJob and state.data.fuelCycle and
       state.data.fuelCycle.jobId=='10:recovery',
       'Failed final deposit must leave original job incomplete')
failDeposit=false
assert(base.fuelCycle('10:recovery'))
assert(state.data.lastFuelJob=='10:recovery' and not state.data.fuelCycle)
assert(count('minecraft:charcoal')==3 and
       stored[1].name=='minecraft:sand')
assert(base.fuelCycle('10:recovery') and collects==1,
 'Completed fuel job must be idempotent')
print('PASS: recover furnace first, never commit before successful deposit')

-- Storage bigger than a turtle inventory must pause BEFORE sucking any items.
slot={};stored={}
for i=1,17 do stored[i]={name='minecraft:oak_log',count=1} end
state.data={pose={x=0,y=0,z=0,dir=0},
 bootstrap={complete=true,home={x=0,y=0,z=0,dir=0}}}
resumed=false;collects=0
ok,reason=pcall(base.fuelCycle,'10:capacity')
assert(not ok and tostring(reason):find('empty turtle slots'),
 'Expected non-destructive overflow preflight')
assert(collects==0 and #stored==17 and state.data.lastFuelJob==nil)
assert(state.data.fuelCycle.jobId=='10:capacity')
print('PASS: oversized base storage refuses destructive partial collection')
