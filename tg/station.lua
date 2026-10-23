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
