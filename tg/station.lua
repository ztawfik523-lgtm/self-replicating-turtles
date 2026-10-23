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
 assert(detail and soft[detail.name],
  'Cannot create station: protected '..side..' block '..tostring(detail and detail.name))
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
-- The very first chest is crafted before much inventory accumulates.
-- No external storage: require ONLY matching planks (plus an unequipped
-- crafting table, which we equip first). Do not throw other items away.
local function bootstrapChest()
 if amount('minecraft:chest')>0 then return end
 factory.equipCrafting()
 local kind,total
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d then
   assert(d.name:match('^minecraft:[%a_]+_planks local below=blockName('bottom')
 if below=='minecraft:chest' or below=='minecraft:barrel' then
  print('Using existing empty storage below')
  return
 end
 if not selectItem('minecraft:chest') then bootstrapChest() end
 assert(selectItem('minecraft:chest'),'Initial chest missing after crafting')
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
function M.pack()
 local s=assert(state.data.station,'No active station to pack')
 assert(not state.data.processing and not state.data.replication,
  'Processing or replication still in progress; inspect contents')
 if s.ownedDrive then
  assert(blockName('front')=='computercraft:disk_drive','Own drive not found in front')
  assert(not disk.isPresent('front'),'Cannot pack a drive holding media')
  assert(roomFor('computercraft:disk_drive'),'Need inventory space for drive')
  mark('picking_up_drive')
  assert(turtle.dig(),'Could not collect disk drive')
  s.ownedDrive=false
  mark('drive_collected')
 end
 if s.ownedFurnace then
  assert(blockName('front')=='minecraft:furnace','Own furnace not found in front')
  assert(emptyPeripheral('front'),'Furnace still holds items; do not break')
  assert(roomFor('minecraft:furnace'),'Need inventory space to collect furnace')
  mark('picking_up_furnace')
  assert(turtle.dig(),'Could not collect empty furnace')
  s.ownedFurnace=false
  mark('furnace_collected')
 end
 if s.ownedChest then
  assert(blockName('bottom')=='minecraft:chest','Own chest not found below')
  assert(emptyPeripheral('bottom'),'Chest still holds items; run collect')
  assert(roomFor('minecraft:chest'),'Need inventory space to collect chest')
  mark('picking_up_chest')
  assert(turtle.digDown(),'Could not collect empty chest')
  s.ownedChest=false
  mark('chest_collected')
 end
 state.data.station=nil
 state.save()
 log.event('station','packed')
 print('Station packed; equipment carried in inventory')
end

local driveRecipe={
 [1]='minecraft:stone',[2]='minecraft:stone',[3]='minecraft:stone',
 [5]='minecraft:stone',[6]='minecraft:redstone',[7]='minecraft:stone',
 [9]='minecraft:stone',[10]='minecraft:redstone',[11]='minecraft:stone',
}
-- Swap the empty furnace for a new disk drive, from raw stone/redstone
-- or a previously crafted drive. Reuse the chest below for recipe staging.
function M.drive()
 state.assertSafe()
 assert(not state.data.manufacture and not state.data.processing and not state.data.replication,
  'Finish manufacturing, smelting or replication first')
 assert(not state.data.station,'Finish or pack previous station first')
 local prev=turtle.getSelectedSlot()
 local below=blockName('bottom')
 assert(below=='minecraft:chest' or below=='minecraft:barrel' or amount('minecraft:chest')>0,
  'Drive workstation requires chest below or chest item')
 local f=blockName('front')
 assert(not f or f=='minecraft:furnace' or f=='computercraft:disk_drive',
  'Refusing to replace unknown front block '..tostring(f))
 if f=='computercraft:disk_drive' then
  assert(not disk.isPresent('front'),'Drive is occupied')
  print('Drive already available')
  return
 end
 if f=='minecraft:furnace' then
  assert(emptyPeripheral('front'),'Empty the furnace before replacing it')
  assert(roomFor('minecraft:furnace'),'Inventory full; cannot pick up furnace')
 end
 assert(amount('computercraft:disk_drive')>=1
   or (amount('minecraft:stone')>=7 and amount('minecraft:redstone')>=2),
  'Need disk drive item or 7 stone + 2 redstone')
 state.data.station={phase='drive_start',ownedChest=false,ownedFurnace=false,ownedDrive=false}
 state.save()
 placeChest()
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function' and next(chest.list())==nil,
  'Chest below must be empty before drive construction')
 if not selectItem('computercraft:disk_drive') then
  mark('crafting_drive')
  factory.craftStep('disk_drive',driveRecipe,'computercraft:disk_drive')
 end
 if f=='minecraft:furnace' then
  mark('removing_empty_furnace')
  assert(turtle.dig(),'Could not recover furnace before placing drive')
 end
 mark('placing_drive')
 assert(selectItem('computercraft:disk_drive'),'Crafted disk drive not found')
 local ok,reason=turtle.place()
 assert(ok,'Could not place disk drive: '..tostring(reason))
 assert(blockName('front')=='computercraft:disk_drive','Drive placement not verified')
 state.data.station.ownedDrive=true
 mark('drive_placed')
 turtle.select(prev)
 print('Disk drive ready; use produce to manufacture/program offspring')
end

function M.run(kind)
 state.assertSafe()
 assert(not state.data.manufacture,'Manufacturing interrupted; inspect it first')
 assert(not state.data.processing,'Processing interrupted; inspect furnace first')
 assert(not state.data.station,'Previous station still active; inspect or station-pack')
 assert(kind=='iron' or kind=='gold' or kind=='glass'
   or kind=='stone' or kind=='charcoal',
   'Use: station iron|gold|glass|stone|charcoal')
 local prev=turtle.getSelectedSlot()
 -- Validate both pieces of required equipment before touching the terrain.
 local below=blockName('bottom')
 local front=blockName('front')
 if below~='minecraft:chest' and below~='minecraft:barrel' then
  -- No existing chest is necessary if this is the first, plank-only bootstrap.
  local canBootstrap=false
  local planks,kind=0,nil
  canBootstrap=true
  for i=1,16 do
   local d=turtle.getItemDetail(i)
   if d then
    if d.name:match('^minecraft:[%a_]+_planks
 end
 if front~='minecraft:furnace' then
  assert(amount('minecraft:furnace')>=1 or amount('minecraft:cobblestone')>=8,
    'Carry a furnace or eight cobblestone')
 end
 assert(not below or below=='minecraft:chest' or below=='minecraft:barrel' or soft[below],
   'Unsafe block beneath turtle: '..tostring(below))
 assert(not front or front=='minecraft:furnace' or soft[front],
   'Unsafe block in front: '..tostring(front))
 state.data.station={phase='starting',ownedChest=false,ownedFurnace=false}
 state.save()
 placeChest()
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function' and next(chest.list())==nil,
   'Chest below must be empty')
 placeFurnace()
 mark('processing_'..kind)
 -- A failure leaves the station in place with its recovery state.
 process.run(kind)
 mark('processing_finished')
 M.pack()
 turtle.select(prev)
 print('Portable processing complete')
end
return M
),
    'Initial chest requires planks-only inventory; bootstrap before collecting ores')
   if kind and kind~=d.name then error('Initial chest requires one type of planks') end
   kind=d.name
   total=(total or 0)+d.count
  end
 end
 assert(total and total>=8 and total<=64,'Need between 8 and 64 matching planks')
 for i=1,15 do
  if turtle.getItemCount(i)>0 then
   turtle.select(i)
   assert(turtle.transferTo(16),'Unable to combine chest planks')
  end
 end
 local ring={1,2,3,5,7,9,10,11}
 for i=1,7 do
  turtle.select(16)
  assert(turtle.transferTo(ring[i],1),'Could not arrange initial chest recipe')
 end
 turtle.select(16)
 assert(turtle.transferTo(11),'Could not finish initial chest recipe')
 assert(turtle.craft(0),'Invalid chest recipe')
 assert(turtle.craft(1),'Initial chest crafting failed')
 assert(selectItem('minecraft:chest'),'Crafted chest item missing')
 print('Crafted first storage chest from planks')
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
function M.pack()
 local s=assert(state.data.station,'No active station to pack')
 assert(not state.data.processing,'Processing still in progress; inspect contents')
 if s.ownedFurnace then
  assert(blockName('front')=='minecraft:furnace','Own furnace not found in front')
  assert(emptyPeripheral('front'),'Furnace still holds items; do not break')
  assert(roomFor('minecraft:furnace'),'Need inventory space to collect furnace')
  mark('picking_up_furnace')
  assert(turtle.dig(),'Could not collect empty furnace')
  s.ownedFurnace=false
  mark('furnace_collected')
 end
 if s.ownedChest then
  assert(blockName('bottom')=='minecraft:chest','Own chest not found below')
  assert(emptyPeripheral('bottom'),'Chest still holds items; run collect')
  assert(roomFor('minecraft:chest'),'Need inventory space to collect chest')
  mark('picking_up_chest')
  assert(turtle.digDown(),'Could not collect empty chest')
  s.ownedChest=false
  mark('chest_collected')
 end
 state.data.station=nil
 state.save()
 log.event('station','packed')
 print('Station packed; equipment carried in inventory')
end

function M.run(kind)
 state.assertSafe()
 assert(not state.data.manufacture,'Manufacturing interrupted; inspect it first')
 assert(not state.data.processing,'Processing interrupted; inspect furnace first')
 assert(not state.data.station,'Previous station still active; inspect or station-pack')
 assert(kind=='iron' or kind=='gold' or kind=='glass'
   or kind=='stone' or kind=='charcoal',
   'Use: station iron|gold|glass|stone|charcoal')
 local prev=turtle.getSelectedSlot()
 -- Validate both pieces of required equipment before touching the terrain.
 local below=blockName('bottom')
 local front=blockName('front')
 if below~='minecraft:chest' and below~='minecraft:barrel' then
  assert(amount('minecraft:chest')>=1,'Carry one chest item')
 end
 if front~='minecraft:furnace' then
  assert(amount('minecraft:furnace')>=1 or amount('minecraft:cobblestone')>=8,
    'Carry a furnace or eight cobblestone')
 end
 assert(not below or below=='minecraft:chest' or below=='minecraft:barrel' or soft[below],
   'Unsafe block beneath turtle: '..tostring(below))
 assert(not front or front=='minecraft:furnace' or soft[front],
   'Unsafe block in front: '..tostring(front))
 state.data.station={phase='starting',ownedChest=false,ownedFurnace=false}
 state.save()
 placeChest()
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function' and next(chest.list())==nil,
   'Chest below must be empty')
 placeFurnace()
 mark('processing_'..kind)
 -- A failure leaves the station in place with its recovery state.
 process.run(kind)
 mark('processing_finished')
 M.pack()
 turtle.select(prev)
 print('Portable processing complete')
end
return M
) then
     if kind and kind~=d.name then canBootstrap=false end
     kind=d.name
     planks=planks+d.count
    elseif d.name~='minecraft:crafting_table' then canBootstrap=false end
   end
  end
  assert(amount('minecraft:chest')>=1 or (canBootstrap and planks>=8 and planks<=64),
    'Need a chest item, or bootstrap early with only 8+ matching planks')
 end
 if front~='minecraft:furnace' then
  assert(amount('minecraft:furnace')>=1 or amount('minecraft:cobblestone')>=8,
    'Carry a furnace or eight cobblestone')
 end
 assert(not below or below=='minecraft:chest' or below=='minecraft:barrel' or soft[below],
   'Unsafe block beneath turtle: '..tostring(below))
 assert(not front or front=='minecraft:furnace' or soft[front],
   'Unsafe block in front: '..tostring(front))
 state.data.station={phase='starting',ownedChest=false,ownedFurnace=false}
 state.save()
 placeChest()
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function' and next(chest.list())==nil,
   'Chest below must be empty')
 placeFurnace()
 mark('processing_'..kind)
 -- A failure leaves the station in place with its recovery state.
 process.run(kind)
 mark('processing_finished')
 M.pack()
 turtle.select(prev)
 print('Portable processing complete')
end
return M
),
    'Initial chest requires planks-only inventory; bootstrap before collecting ores')
   if kind and kind~=d.name then error('Initial chest requires one type of planks') end
   kind=d.name
   total=(total or 0)+d.count
  end
 end
 assert(total and total>=8 and total<=64,'Need between 8 and 64 matching planks')
 for i=1,15 do
  if turtle.getItemCount(i)>0 then
   turtle.select(i)
   assert(turtle.transferTo(16),'Unable to combine chest planks')
  end
 end
 local ring={1,2,3,5,7,9,10,11}
 for i=1,7 do
  turtle.select(16)
  assert(turtle.transferTo(ring[i],1),'Could not arrange initial chest recipe')
 end
 turtle.select(16)
 assert(turtle.transferTo(11),'Could not finish initial chest recipe')
 assert(turtle.craft(0),'Invalid chest recipe')
 assert(turtle.craft(1),'Initial chest crafting failed')
 assert(selectItem('minecraft:chest'),'Crafted chest item missing')
 print('Crafted first storage chest from planks')
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
function M.pack()
 local s=assert(state.data.station,'No active station to pack')
 assert(not state.data.processing,'Processing still in progress; inspect contents')
 if s.ownedFurnace then
  assert(blockName('front')=='minecraft:furnace','Own furnace not found in front')
  assert(emptyPeripheral('front'),'Furnace still holds items; do not break')
  assert(roomFor('minecraft:furnace'),'Need inventory space to collect furnace')
  mark('picking_up_furnace')
  assert(turtle.dig(),'Could not collect empty furnace')
  s.ownedFurnace=false
  mark('furnace_collected')
 end
 if s.ownedChest then
  assert(blockName('bottom')=='minecraft:chest','Own chest not found below')
  assert(emptyPeripheral('bottom'),'Chest still holds items; run collect')
  assert(roomFor('minecraft:chest'),'Need inventory space to collect chest')
  mark('picking_up_chest')
  assert(turtle.digDown(),'Could not collect empty chest')
  s.ownedChest=false
  mark('chest_collected')
 end
 state.data.station=nil
 state.save()
 log.event('station','packed')
 print('Station packed; equipment carried in inventory')
end

function M.run(kind)
 state.assertSafe()
 assert(not state.data.manufacture,'Manufacturing interrupted; inspect it first')
 assert(not state.data.processing,'Processing interrupted; inspect furnace first')
 assert(not state.data.station,'Previous station still active; inspect or station-pack')
 assert(kind=='iron' or kind=='gold' or kind=='glass'
   or kind=='stone' or kind=='charcoal',
   'Use: station iron|gold|glass|stone|charcoal')
 local prev=turtle.getSelectedSlot()
 -- Validate both pieces of required equipment before touching the terrain.
 local below=blockName('bottom')
 local front=blockName('front')
 if below~='minecraft:chest' and below~='minecraft:barrel' then
  assert(amount('minecraft:chest')>=1,'Carry one chest item')
 end
 if front~='minecraft:furnace' then
  assert(amount('minecraft:furnace')>=1 or amount('minecraft:cobblestone')>=8,
    'Carry a furnace or eight cobblestone')
 end
 assert(not below or below=='minecraft:chest' or below=='minecraft:barrel' or soft[below],
   'Unsafe block beneath turtle: '..tostring(below))
 assert(not front or front=='minecraft:furnace' or soft[front],
   'Unsafe block in front: '..tostring(front))
 state.data.station={phase='starting',ownedChest=false,ownedFurnace=false}
 state.save()
 placeChest()
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function' and next(chest.list())==nil,
   'Chest below must be empty')
 placeFurnace()
 mark('processing_'..kind)
 -- A failure leaves the station in place with its recovery state.
 process.run(kind)
 mark('processing_finished')
 M.pack()
 turtle.select(prev)
 print('Portable processing complete')
end
return M
