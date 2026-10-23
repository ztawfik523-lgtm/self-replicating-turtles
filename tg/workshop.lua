-- Portable workstation construction. No movement or pre-placed stations required.
-- One empty chest below the turtle; one furnace or drive in front.
local M = {}
local state = require('state')
local factory = require('factory')
local log = require('log')

local SAFE_BELOW = {
  ['minecraft:dirt']=true, ['minecraft:grass_block']=true,
  ['minecraft:stone']=true, ['minecraft:cobblestone']=true,
  ['minecraft:deepslate']=true, ['minecraft:cobbled_deepslate']=true,
  ['minecraft:gravel']=true, ['minecraft:sand']=true,
}
local FRONT={
  furnace={id='minecraft:furnace',items={'minecraft:furnace'}},
  drive={id='computercraft:disk_drive',items={'computercraft:disk_drive'}},
}
local function slotFor(name)
  for i=1,16 do
    local d=turtle.getItemDetail(i)
    if d and d.name==name then return i end
  end
end
local function count(name)
  local n=0
  for i=1,16 do
    local d=turtle.getItemDetail(i)
    if d and d.name==name then n=n+d.count end
  end
  return n
end
local function freeSlot()
  for i=1,16 do if turtle.getItemCount(i)==0 then return true end end
  return false
end
local function bottomInventory()
  local p=peripheral.wrap('bottom')
  assert(p and type(p.list)=='function','Chest below not accessible')
  return p
end
local function empty(p)
  return next(p.list())==nil
end
local function safeToWork()
  state.assertSafe()
  assert(not state.data.processing,'Processing unfinished; inspect furnace/chest first')
  assert(not state.data.manufacture,'Manufacturing unfinished; inspect chest first')
end

-- First chest can be made before a storage chest exists. Keep only planks
-- and equipped turtle upgrades in inventory at this early bootstrap stage.
-- Not a general item rearranger; it fails rather than dropping resources.
local function bootstrapChest()
  if slotFor('minecraft:chest') then return end
  factory.equipCrafting()
  local plank,total
  for i=1,16 do
    local d=turtle.getItemDetail(i)
    if d then
      assert(d.name:match('^minecraft:[%a_]+_planks$'),
        'Bootstrap chest: inventory must contain ONLY planks (craft chest early)')
      if plank and plank~=d.name then error('Bootstrap chest: mixed wood types') end
      plank=d.name
      total=(total or 0)+d.count
    end
  end
  assert(total and total>=8 and total<=64,'Bootstrap chest needs 8-64 matching planks')
  local prev=turtle.getSelectedSlot()
  -- Move all planks into slot 16.
  for i=1,15 do
    if turtle.getItemCount(i)>0 then
      turtle.select(i)
      assert(turtle.transferTo(16),'Could not stage planks into slot 16')
    end
  end
  local ring={1,2,3,5,7,9,10,11}
  for i=1,7 do
    turtle.select(16)
    assert(turtle.transferTo(ring[i],1),'Cannot arrange chest recipe')
  end
  turtle.select(16)
  assert(turtle.transferTo(11),'Cannot place remaining planks into recipe grid')
  assert(turtle.craft(0),'Chest crafting pattern invalid')
  assert(turtle.craft(1),'Failed to craft initial chest')
  turtle.select(prev)
  assert(slotFor('minecraft:chest'),'Chest output missing')
  print('Bootstrapped initial chest from planks')
end

local function ensureChest()
  local found,below=turtle.inspectDown()
  if found and (below.name=='minecraft:chest' or below.name=='minecraft:barrel') then
    assert(empty(bottomInventory()),'Chest below contains items; retrieve before rebuilding')
    return
  end
  if found then
    assert(SAFE_BELOW[below.name],'Refusing to remove block below: '..below.name)
  end
  if not slotFor('minecraft:chest') then bootstrapChest() end
  local s=assert(slotFor('minecraft:chest'),'Need a chest item or eight matching planks')
  if found then assert(turtle.digDown(),'Cannot clear location for chest below') end
  turtle.select(s)
  assert(turtle.placeDown(),'Cannot place chest below turtle')
  local ok,block=turtle.inspectDown()
  assert(ok and block.name=='minecraft:chest','Chest placement could not be verified')
  assert(empty(bottomInventory()),'New chest is unexpectedly not empty')
  print('Placed chest below')
end

local function craftMissing(kind)
  local target=FRONT[kind].id
  if slotFor(target) then return end
  if kind=='furnace' then
    assert(count('minecraft:cobblestone')>=8,'Need 8 cobblestone to craft furnace')
    factory.craftRecipe('furnace',{
      [1]='minecraft:cobblestone',[2]='minecraft:cobblestone',
      [3]='minecraft:cobblestone',[5]='minecraft:cobblestone',
      [7]='minecraft:cobblestone',[9]='minecraft:cobblestone',
      [10]='minecraft:cobblestone',[11]='minecraft:cobblestone',
    },target)
  else
    assert(count('minecraft:stone')>=7 and count('minecraft:redstone')>=2,
      'Need 7 stone and 2 redstone to craft disk drive')
    factory.craftRecipe('disk_drive',{
      [1]='minecraft:stone',[2]='minecraft:stone',[3]='minecraft:stone',
      [5]='minecraft:stone',[6]='minecraft:redstone',[7]='minecraft:stone',
      [9]='minecraft:stone',[10]='minecraft:redstone',[11]='minecraft:stone',
    },target)
  end
  assert(slotFor(target),'Crafted workstation not in inventory')
end
local function recoverFront()
  local exists,front=turtle.inspect()
  if not exists then return end
  assert(front.name=='minecraft:furnace' or front.name=='computercraft:disk_drive',
    'Refusing to dig unknown front block: '..front.name)
  assert(freeSlot(),'Need a free inventory slot to pick up workstation')
  if front.name=='minecraft:furnace' then
    local p=peripheral.wrap('front')
    assert(p and empty(p),'Cannot pick up non-empty furnace')
  else
    assert(not disk.isPresent('front'),'Cannot remove disk drive with item inserted')
  end
  assert(turtle.dig(),'Could not retrieve front workstation block')
  assert(not turtle.detect(),'Front workstation block still present')
  print('Recovered '..front.name)
end

function M.prepare(kind)
  assert(FRONT[kind], 'Usage: workshop furnace|drive')
  safeToWork()
  local old=turtle.getSelectedSlot()
  local ok,err=pcall(function()
    ensureChest()
    local has,block=turtle.inspect()
    if has and block.name==FRONT[kind].id then
      print(kind..' workstation already prepared')
      return
    end
    -- Do not destroy an old workstation until the replacement is ready.
    craftMissing(kind)
    recoverFront()
    turtle.select(assert(slotFor(FRONT[kind].id)))
    assert(turtle.place(),'Could not place '..kind..' in front')
    local present,actual=turtle.inspect()
    assert(present and actual.name==FRONT[kind].id,
      'Placed block is not expected '..FRONT[kind].id)
    print('Workshop ready: '..kind..' in front, chest below')
    log.event('workshop_prepared',kind)
  end)
  turtle.select(old)
  if not ok then error(err,0) end
end

function M.pack()
  safeToWork()
  local before=turtle.getSelectedSlot()
  local ok,err=pcall(function()
    local exists,down=turtle.inspectDown()
    assert(exists and (down.name=='minecraft:chest' or down.name=='minecraft:barrel'),
      'No chest below to pack')
    assert(empty(bottomInventory()),'Cannot pack: chest below contains items')
    -- Need space to recover both station items.
    local free=0
    for i=1,16 do if turtle.getItemCount(i)==0 then free=free+1 end end
    local frontExists=turtle.detect()
    assert(free >= (frontExists and 2 or 1),
      'Need free inventory slots for portable workstations')
    recoverFront()
    assert(turtle.digDown(),'Could not pick up empty chest')
    local now,block=turtle.inspectDown()
    assert(not now,'Chest below still present: '..tostring(block and block.name))
    print('Workstation packed for transport')
    log.event('workshop_packed','')
  end)
  turtle.select(before)
  if not ok then error(err,0) end
end
return M
