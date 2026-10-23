-- Portable single-turtle smelting station.
-- Carries a chest, crafts a furnace from cobblestone if needed, deploys both,
-- processes one batch, and reclaims its own empty equipment.
-- No movement, external controller, or prebuilt installation required.
local M={}
local state=require('state')
local log=require('log')
local factory=require('factory')
local process=require('process')

local soft={
 ['minecraft:dirt']=true,['minecraft:grass_block']=true,
 ['minecraft:stone']=true,['minecraft:cobblestone']=true,
 ['minecraft:deepslate']=true,['minecraft:cobbled_deepslate']=true,
 ['minecraft:granite']=true,['minecraft:andesite']=true,
 ['minecraft:diorite']=true,['minecraft:tuff']=true,
 ['minecraft:gravel']=true,['minecraft:sand']=true,
 ['minecraft:snow_block']=true,['minecraft:short_grass']=true,
 ['minecraft:grass']=true,
}
local furnaceRecipe={
 [1]='minecraft:cobblestone',[2]='minecraft:cobblestone',
 [3]='minecraft:cobblestone',[5]='minecraft:cobblestone',
 [7]='minecraft:cobblestone',[9]='minecraft:cobblestone',
 [10]='minecraft:cobblestone',[11]='minecraft:cobblestone',
}
local function amount(name)
 local n=0
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d and d.name==name then n=n+d.count end
 end
 return n
end
local function selectItem(name)
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d and d.name==name then turtle.select(i); return true end
 end
 return false
end
local function roomFor(name)
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if not d or (d.name==name and turtle.getItemSpace(i)>0) then return true end
 end
 return false
end
local function inspectAt(side)
 if side=='front' then return turtle.inspect() end
 return turtle.inspectDown()
end
local function blockName(side)
 local found,info=inspectAt(side)
 return found and info and info.name or nil
end
local function ensureClear(side)
 local present,detail=inspectAt(side)
 if not present then return end
 -- Try ordinary excavation rather than refusing every unfamiliar terrain block.
 -- Never mine an inventory or dangerous fluid as part of making a station.
 local name=detail and detail.name or ''
 assert(name~='minecraft:water' and name~='minecraft:lava'
  and not name:find('chest') and not name:find('barrel')
  and not name:find('furnace') and not name:find('shulker_box')
  and not name:find('computercraft:'),
  'Cannot place station over '..tostring(name))
 local ok,reason
 if side=='front' then ok,reason=turtle.dig()
 else ok,reason=turtle.digDown() end
 assert(ok,'Cannot clear '..side..': '..tostring(reason))
end
local function mark(phase)
 state.data.station.phase=phase
 state.save()
 log.event('station',phase)
 print('Station: '..phase)
end
local function placeChest()
 local below=blockName('bottom')
 if below=='minecraft:chest' or below=='minecraft:barrel' then
  print('Using existing empty storage below')
  return
 end
 assert(selectItem('minecraft:chest'),
   'Need one chest item to make a portable station')
 mark('clearing_below')
 ensureClear('bottom')
 mark('placing_chest')
 assert(selectItem('minecraft:chest'),'Chest item missing after clearing ground')
 local ok,reason=turtle.placeDown()
 assert(ok,'Could not place chest below: '..tostring(reason))
 state.data.station.ownedChest=true
 mark('chest_placed')
end
local function placeFurnace()
 if blockName('front')=='minecraft:furnace' then
  print('Using existing furnace ahead')
  return
 end
 if not selectItem('minecraft:furnace') then
  assert(amount('minecraft:cobblestone')>=8,
    'Need one furnace item or eight cobblestone')
  mark('crafting_furnace')
  factory.craftStep('furnace',furnaceRecipe,'minecraft:furnace')
 end
 mark('clearing_front')
 ensureClear('front')
 mark('placing_furnace')
 assert(selectItem('minecraft:furnace'),'Furnace missing from inventory')
 local ok,reason=turtle.place()
 assert(ok,'Could not place furnace ahead: '..tostring(reason))
 state.data.station.ownedFurnace=true
 mark('furnace_placed')
end
local function emptyPeripheral(side)
 local p=peripheral.wrap(side)
 assert(p and type(p.list)=='function',
   'Cannot inspect storage inventory at '..side)
 return next(p.list())==nil
end
-- Reconcile saved state with the actual blocks. A crash after placement or
-- smelting should not force the player to manually clear a bookkeeping flag.
local function reconcile()
 local s=state.data.station
 if not s then return false end
 local front,below=blockName('front'),blockName('bottom')
 if s.phase=='placing_chest' and below=='minecraft:chest' then
  s.ownedChest=true
 end
 if s.phase=='placing_furnace' and front=='minecraft:furnace' then
  s.ownedFurnace=true
 end
 state.save()
 return true
end

function M.pack()
 local s=state.data.station
 if not s then return true end
 if state.data.processing then
  local ok,why=process.resume()
  if not ok then
   print('Processing paused: '..tostring(why))
   return false
  end
 end
 local front=blockName('front')
 local below=blockName('bottom')
 if s.ownedFurnace then
  if front=='minecraft:furnace' then
   assert(emptyPeripheral('front'),'Furnace is still processing or contains resources')
   assert(roomFor('minecraft:furnace'),'Need inventory space to reclaim furnace')
   mark('picking_up_furnace')
   assert(turtle.dig(),'Unable to collect furnace')
  elseif front then
   error('A different block replaced the furnace: '..tostring(front))
  end
  s.ownedFurnace=false
  mark('furnace_collected')
 end
 if s.ownedChest then
  if below=='minecraft:chest' then
   if not emptyPeripheral('bottom') then
    factory.collect() -- retrieve output without making the player do it
   end
   assert(emptyPeripheral('bottom'),'Some resources still in chest')
   assert(roomFor('minecraft:chest'),'Need inventory space to reclaim chest')
   mark('picking_up_chest')
   assert(turtle.digDown(),'Unable to collect chest')
  elseif below then
   error('A different block replaced the chest: '..tostring(below))
  end
  s.ownedChest=false
  mark('chest_collected')
 end
 state.data.station=nil
 state.save()
 log.event('station','packed')
 print('Station equipment recovered')
 return true
end

function M.run(kind)
 state.assertSafe()
 assert(kind=='iron' or kind=='gold' or kind=='glass'
   or kind=='stone' or kind=='charcoal',
   'Use: station iron|gold|glass|stone|charcoal')
 assert(not state.data.manufacture,'Finish manufacturing before starting station')

 local prev=turtle.getSelectedSlot()
 local old=state.data.station
 if old then
  reconcile()
  -- If smelting was already started, complete/reconcile that transaction and
  -- collect the equipment. Do not start a second identical smelting batch.
  if state.data.processing or old.phase:find('^processing_')
    or old.phase=='processing_finished' or old.phase:find('pickup')
    or old.phase:find('picking_up',1,true)
    or old.phase:find('_collected',1,true) then
   print('Finishing interrupted station automatically')
   local ok=M.pack()
   turtle.select(prev)
   return ok
  end
  print('Continuing partially placed station')
 else
  -- Only validate initial supplies on a brand-new operation.
  local below,front=blockName('bottom'),blockName('front')
  if below~='minecraft:chest' and below~='minecraft:barrel' then
   assert(amount('minecraft:chest')>=1,'Need chest item in inventory')
  end
  if front~='minecraft:furnace' then
   assert(amount('minecraft:furnace')>=1 or amount('minecraft:cobblestone')>=8,
     'Need furnace item or 8 cobblestone')
  end
  state.data.station={phase='starting',kind=kind,ownedChest=false,ownedFurnace=false}
  state.save()
 end
 placeChest()
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function','Storage unavailable below')
 if next(chest.list()) then
  factory.collect()
 end
 placeFurnace()
 mark('processing_'..kind)
 process.run(kind)
 mark('processing_finished')
 local ok=M.pack()
 turtle.select(prev)
 if ok then print('Portable processing complete') end
 return ok
end

-- Invoked at turtle startup if an earlier station operation was interrupted.
-- Recover using saved job information; don't invent a new operation.
function M.recover()
 local s=state.data.station
 if not s then return true end
 local kind=s.kind or (state.data.processing and state.data.processing.kind)
   or s.phase:match('^processing_(%a+)$')
 if not kind then
  print('Station interrupted before smelting; reclaiming equipment')
  return M.pack()
 end
 return M.run(kind)
end
return M
) then
   print('Finishing interrupted station automatically')
   local ok=M.pack()
   turtle.select(prev)
   return ok
  end
  print('Continuing partially placed station')
 else
  -- Only validate initial supplies on a brand-new operation.
  local below,front=blockName('bottom'),blockName('front')
  if below~='minecraft:chest' and below~='minecraft:barrel' then
   assert(amount('minecraft:chest')>=1,'Need chest item in inventory')
  end
  if front~='minecraft:furnace' then
   assert(amount('minecraft:furnace')>=1 or amount('minecraft:cobblestone')>=8,
     'Need furnace item or 8 cobblestone')
  end
  state.data.station={phase='starting',kind=kind,ownedChest=false,ownedFurnace=false}
  state.save()
 end
 placeChest()
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function','Storage unavailable below')
 if next(chest.list()) then
  factory.collect()
 end
 placeFurnace()
 mark('processing_'..kind)
 process.run(kind)
 mark('processing_finished')
 local ok=M.pack()
 turtle.select(prev)
 if ok then print('Portable processing complete') end
 return ok
end

-- Invoked at turtle startup if an earlier station operation was interrupted.
-- Recover using saved job information; don't invent a new operation.
function M.recover()
 local s=state.data.station
 if not s then return true end
 local kind=s.kind or (state.data.processing and state.data.processing.kind)
   or s.phase:match('^processing_(%a+)$')
 if not kind then
  print('Station interrupted before smelting; reclaiming equipment')
  return M.pack()
 end
 return M.run(kind)
end
return M
