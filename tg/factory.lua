-- Turtle Genesis: fixed manufacturing pipeline for a Mining + Crafting Turtle.
-- Needs a working chest/barrel below as temporary storage.
local M={}
local state=require('state')
local log=require('log')
local GRID={1,2,3,5,6,7,9,10,11}
local BUFFER={4,8,12,13,14,15,16}
local function detail(i) return turtle.getItemDetail(i) end
local function count(name)
  local n=0
  for i=1,16 do local d=detail(i);if d and d.name==name then n=n+d.count end end
  return n
end
local function matchingPlanks()
  for i=1,16 do
    local d=detail(i)
    if d and d.name:match('^minecraft:[%a_]+_planks$') and count(d.name)>=14 then return d.name end
  end
end
local function hasCrafting()
  for _,side in ipairs({'Left','Right'}) do
    local fn=turtle['getEquipped'..side]
    local d=fn and fn()
    if d and d.name=='minecraft:crafting_table' then return true end
  end
  return false
end
local function ensureCrafting()
  if hasCrafting() then return end
  local slot
  for i=1,16 do if detail(i) and detail(i).name=='minecraft:crafting_table' then slot=i;break end end
  assert(slot,'This Mining Turtle needs a crafting table item to equip')
  local left,right=turtle.getEquippedLeft(),turtle.getEquippedRight()
  assert(not left or not right,'Both upgrade slots occupied; make room for crafting')
  turtle.select(slot)
  local ok,why
  if not left then ok,why=turtle.equipLeft() else ok,why=turtle.equipRight() end
  assert(ok,'Cannot equip crafting table: '..tostring(why))
  assert(hasCrafting(),'Crafting table upgrade did not register')
  print('Equipped crafting upgrade')
end
local function chest()
  local exists,block=turtle.inspectDown()
  assert(exists and (block.name=='minecraft:chest' or block.name=='minecraft:barrel'),
    'Place a chest or barrel UNDER the parent turtle')
  local p=peripheral.wrap('bottom')
  assert(p and type(p.list)=='function','Bottom storage inventory peripheral unavailable')
  return p
end
local function emptyChest()
  for _slot,_item in pairs(chest().list()) do return false end
  return true
end
function M.collect()
  local storage=chest()
  local previous=turtle.getSelectedSlot()
  for _=1,40 do
    local wanted
    for _slot,item in pairs(storage.list()) do wanted=item.name;break end
    if not wanted then turtle.select(previous);return true end
    local chosen
    for i=1,16 do
      local d=detail(i)
      if d and d.name==wanted and turtle.getItemSpace(i)>0 then chosen=i;break end
    end
    if not chosen then
      for i=1,16 do if not detail(i) then chosen=i;break end end
    end
    assert(chosen,'Inventory full restoring staged items')
    turtle.select(chosen)
    assert(turtle.suckDown(64),'Cannot retrieve item from chest')
  end
  turtle.select(previous)
  error('Chest still contains items after 40 withdrawals')
end
function M.needs()
  local plank=matchingPlanks()
  local names={
    ['minecraft:stone']=7,['minecraft:redstone']=1,
    ['minecraft:glass_pane']=1,['minecraft:iron_ingot']=7,
    ['minecraft:diamond']=3,
  }
  local ok=true
  print('Materials for one Mining + Crafting Turtle:')
  for name,needed in pairs(names) do
    local have=count(name)
    print(('%s: %d/%d'):format(name,have,needed))
    if have<needed then ok=false end
  end
  print('Planks: '..(plank and (plank..' 14/14') or 'need 14 of one type'))
  if not plank then ok=false end
  local coal=count('minecraft:coal')+count('minecraft:charcoal')
  print('Coal/charcoal for child: '..coal..'/4')
  if coal<4 then ok=false end
  print('Crafting upgrade: '..(hasCrafting() and 'equipped' or 'requires crafting table item'))
  return ok and (hasCrafting() or count('minecraft:crafting_table')>=1),plank
end
local function stashSlot(i)
  if not detail(i) then return end
  turtle.select(i)
  assert(turtle.dropDown(),'Cannot store item from slot '..i)
  assert(not detail(i),'Could not completely empty slot '..i)
end
local function bufferFor(name)
  for _,i in ipairs(BUFFER) do
    local d=detail(i)
    if d and d.name==name and turtle.getItemSpace(i)>0 then return i end
  end
  for _,i in ipairs(BUFFER) do if not detail(i) then return i end end
  error('Not enough scratch inventory slots')
end
local function take(name,dest)
  for _,i in ipairs(BUFFER) do
    local d=detail(i)
    if d and d.name==name then
      turtle.select(i)
      if turtle.transferTo(dest,1) then return end
    end
  end
  error('Ingredient missing while staging: '..name)
end
local function craftStep(label,pattern,expected)
  local demand={}
  for _,name in pairs(pattern) do demand[name]=(demand[name] or 0)+1 end
  for name,n in pairs(demand) do
    assert(count(name)>=n,('%s: missing %s (%d/%d)'):format(label,name,count(name),n))
  end
  assert(emptyChest(),'Chest not empty; run tg/main.lua collect first')
  -- Unrelated items cannot remain in any inventory slot during turtle.craft.
  for i=1,16 do
    local d=detail(i)
    if d and not demand[d.name] then stashSlot(i) end
  end
  -- Evacuate the 3x3 slots to the seven non-crafting positions.
  for _,i in ipairs(GRID) do
    while detail(i) do
      turtle.select(i)
      local to=bufferFor(detail(i).name)
      assert(turtle.transferTo(to),'Cannot stage ingredient in slot '..i)
    end
  end
  for i,name in pairs(pattern) do take(name,i) end
  for _,i in ipairs(BUFFER) do stashSlot(i) end
  local valid,reason=turtle.craft(0)
  assert(valid,'Invalid recipe for '..label..': '..tostring(reason))
  turtle.select(16)
  local ok,why=turtle.craft(1)
  assert(ok,'Crafting '..label..' failed: '..tostring(why))
  assert(count(expected)>0,'Output not found for '..label)
  M.collect()
  print('Crafted '..label)
  log.event('crafted',label)
end
M.craftStep=craftStep -- Shared fixed-recipe helper for portable station.
M.equipCrafting=ensureCrafting
function M.make()
  state.assertSafe()
  assert(not state.data.manufacture,'Interrupted manufacturing present; inspect before retry')
  local enough,planks=M.needs()
  assert(enough,'Missing required materials')
  chest()
  assert(emptyChest(),'Temporary chest must be empty')
  ensureCrafting()
  state.data.manufacture={phase='prepare'}
  state.save()
  local ok,err=pcall(function()
    local function step(label,pattern,output)
      state.data.manufacture.phase=label
      state.save()
      craftStep(label,pattern,output)
    end
    step('sticks',{[1]=planks,[5]=planks},'minecraft:stick')
    step('chest',{[1]=planks,[2]=planks,[3]=planks,[5]=planks,[7]=planks,[9]=planks,[10]=planks,[11]=planks},'minecraft:chest')
    step('crafting_table',{[1]=planks,[2]=planks,[5]=planks,[6]=planks},'minecraft:crafting_table')
    step('diamond_pickaxe',{[1]='minecraft:diamond',[2]='minecraft:diamond',[3]='minecraft:diamond',[6]='minecraft:stick',[10]='minecraft:stick'},'minecraft:diamond_pickaxe')
    step('computer',{[1]='minecraft:stone',[2]='minecraft:stone',[3]='minecraft:stone',[5]='minecraft:stone',[6]='minecraft:redstone',[7]='minecraft:stone',[9]='minecraft:stone',[10]='minecraft:glass_pane',[11]='minecraft:stone'},'computercraft:computer_normal')
    step('turtle',{[1]='minecraft:iron_ingot',[2]='minecraft:iron_ingot',[3]='minecraft:iron_ingot',[5]='minecraft:iron_ingot',[6]='computercraft:computer_normal',[7]='minecraft:iron_ingot',[9]='minecraft:iron_ingot',[10]='minecraft:chest',[11]='minecraft:iron_ingot'},'computercraft:turtle_normal')
    step('mining_upgrade',{[1]='minecraft:diamond_pickaxe',[2]='computercraft:turtle_normal'},'computercraft:turtle_normal')
    step('crafting_upgrade',{[1]='computercraft:turtle_normal',[2]='minecraft:crafting_table'},'computercraft:turtle_normal')
  end)
  if not ok then
    printError('Manufacturing stopped at '..tostring(state.data.manufacture.phase))
    printError(tostring(err))
    printError('Use tg/main.lua collect if any items remain below')
    return false,err
  end
  state.data.manufacture=nil
  state.save()
  print('Crafted Mining + Crafting Turtle; verify upgrades in game')
  return true
end
function M.abort()
  local job=assert(state.data.manufacture,'No interrupted manufacturing')
  M.collect()
  assert(emptyChest(),'Workspace chest still contains components')
  state.data.manufacture=nil
  state.save()
  print('Manufacturing cleared at phase '..tostring(job.phase))
  print('Recheck supplies: earlier crafts may already have consumed items')
end
return M
