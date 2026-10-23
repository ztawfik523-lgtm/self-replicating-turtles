-- Experimental first-birth workshop, not installed until integration gate.
-- Assumes one CHest ITEM as a bootstrap kit, not a prebuilt chest.
-- Uses existing factory, furnace processor, and tested replication sequence.
local M={}
local state=require('state')
local factory=require('factory')
local process=require('process')
local replicate=require('replicate')

local function count(name)
 local n=0
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d and d.name==name then n=n+d.count end
 end
 return n
end
local function countFuel()
 return count('minecraft:coal')+count('minecraft:charcoal')
end
local function planks()
 local totals={}
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d and d.name:match('^minecraft:[%a_]+_planks$') then
   totals[d.name]=(totals[d.name] or 0)+d.count
  end
 end
 local maximum=0
 for _,n in pairs(totals) do maximum=math.max(n,maximum) end
 return maximum
end
local function select(name)
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d and d.name==name then turtle.select(i);return true end
 end
 return false
end
local function block(side)
 local ok,d
 if side=='front' then ok,d=turtle.inspect() else ok,d=turtle.inspectDown() end
 return ok and d and d.name or nil
end
local function phase(s)
 state.data.birth=state.data.birth or {}
 state.data.birth.stage=s
 state.save()
 print('Birth: '..s)
end
local function availableStorage()
 local name=block('bottom')
 return name=='minecraft:chest' or name=='minecraft:barrel'
end
local function storage()
 assert(availableStorage(),'Worksite chest missing')
 local c=peripheral.wrap('bottom')
 assert(c and type(c.list)=='function','Cannot reach chest below')
 return c
end
local function clearFor(side)
 local name=block(side)
 if not name then return end
 -- Never destroy another base's equipment or a liquid; simple terrain can go.
 assert(name:sub(1,10)=='minecraft:' and
    name~='minecraft:lava' and name~='minecraft:water' and
    not name:find('chest',1,true) and
    not name:find('barrel',1,true) and
    not name:find('furnace',1,true) and
    not name:find('shulker',1,true) and
    not name:find('bedrock',1,true),
    'Cannot clear workstation '..side..': '..name)
 local ok,reason
 if side=='bottom' then ok,reason=turtle.digDown()
 else ok,reason=turtle.dig() end
 assert(ok,'Cannot clear '..side..': '..tostring(reason))
end
local function ensureChest()
 if availableStorage() then return end
 assert(select('minecraft:chest'),
   'Starter worksite requires a chest ITEM; automatic wood bootstrap is next milestone')
 phase('place_chest')
 clearFor('bottom')
 assert(select('minecraft:chest'),'Chest item unavailable')
 local ok,reason=turtle.placeDown()
 assert(ok,'Cannot place chest: '..tostring(reason))
 assert(availableStorage(),'Chest did not appear')
end
local furnaceRecipe={
 [1]='minecraft:cobblestone',[2]='minecraft:cobblestone',
 [3]='minecraft:cobblestone',[5]='minecraft:cobblestone',
 [7]='minecraft:cobblestone',[9]='minecraft:cobblestone',
 [10]='minecraft:cobblestone',[11]='minecraft:cobblestone',
}
local driveRecipe={
 [1]='minecraft:stone',[2]='minecraft:stone',[3]='minecraft:stone',
 [5]='minecraft:stone',[6]='minecraft:redstone',[7]='minecraft:stone',
 [9]='minecraft:stone',[10]='minecraft:redstone',[11]='minecraft:stone',
}
local paneRecipe={
 [1]='minecraft:glass',[2]='minecraft:glass',[3]='minecraft:glass',
 [5]='minecraft:glass',[6]='minecraft:glass',[7]='minecraft:glass',
}
local function craftIfMissing(label,output,pattern)
 if count(output)>0 then return end
 phase('craft_'..label)
 factory.craftStep(label,pattern,output)
 assert(count(output)>0,'Craft did not produce '..output)
end
local function furnaceEmpty()
 local p=peripheral.wrap('front')
 assert(p and type(p.list)=='function','Furnace inventory inaccessible')
 return next(p.list())==nil
end
local function ensureFurnace()
 if block('front')=='minecraft:furnace' then return end
 assert(block('front')~='computercraft:disk_drive',
   'Disk drive already ahead; cannot temporarily place furnace there')
 craftIfMissing('furnace','minecraft:furnace',furnaceRecipe)
 phase('place_furnace')
 clearFor('front')
 assert(select('minecraft:furnace'),'Furnace item missing')
 local ok,reason=turtle.place()
 assert(ok,'Cannot place furnace: '..tostring(reason))
 assert(block('front')=='minecraft:furnace','Furnace did not appear')
end
local function getInput(kind)
 if kind=='iron' then return 'minecraft:raw_iron','minecraft:iron_ingot' end
 if kind=='stone' then return 'minecraft:cobblestone','minecraft:stone' end
 if kind=='glass' then return 'minecraft:sand','minecraft:glass' end
end
local function ensureSmelt(kind,wanted)
 local source,target=getInput(kind)
 local attempts=0
 while count(target)<wanted do
  attempts=attempts+1
  assert(attempts<16,'Too many smelting attempts: '..kind)
  assert(count(source)>0,
    ('Missing %s: have %d %s, need %d'):format(source,count(target),target,wanted))
  if state.data.processing then
   phase('resume_'..kind)
   local ok,reason=process.resume()
   assert(ok,'Processing needs resources: '..tostring(reason))
  else
   phase('smelt_'..kind)
   process.run(kind)
  end
 end
end
local function ensureDrive()
 if block('front')=='computercraft:disk_drive' then return end
 craftIfMissing('disk_drive','computercraft:disk_drive',driveRecipe)
 local ahead=block('front')
 if ahead=='minecraft:furnace' then
  assert(furnaceEmpty(),'Furnace has material; cannot replace it with drive')
  phase('replace_furnace')
  assert(turtle.dig(),'Could not recover empty furnace')
 else
  clearFor('front')
 end
 phase('place_disk_drive')
 assert(select('computercraft:disk_drive'),'Disk drive item missing')
 local ok,reason=turtle.place()
 assert(ok,'Cannot place disk drive: '..tostring(reason))
 assert(block('front')=='computercraft:disk_drive','Disk drive not placed')
end
local function childItemPresent()
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d and d.name:match('^computercraft:turtle_') then return true end
 end
 return false
end
local function preflight()
 assert(not state.data.pending and not state.data.trip,
  'Movement uncertain; cannot construct base in an unknown position')
 assert(not state.data.replication or childItemPresent(),
  'Partial child deployment requires inspection before resuming')
 local needs={}
 local function need(name,n)
  if count(name)<n then needs[#needs+1]=name..' '..count(name)..'/'..n end
 end
 if not availableStorage() then need('minecraft:chest',1) end
 if planks()<14 then needs[#needs+1]='14 same-type planks' end
 need('minecraft:diamond',3)
 need('minecraft:redstone',block('front')=='computercraft:disk_drive' and 1 or 3)
 if count('minecraft:iron_ingot')<7 then
  need('minecraft:raw_iron',7-count('minecraft:iron_ingot'))
 end
 local stoneShort=math.max(0,14-count('minecraft:stone'))
 if count('minecraft:cobblestone')<stoneShort+
   ((block('front')=='minecraft:furnace' or
     count('minecraft:furnace')>0) and 0 or 8) then
  needs[#needs+1]='cobblestone for stone and furnace'
 end
 if count('minecraft:glass_pane')==0 and count('minecraft:glass')<6 then
  need('minecraft:sand',6-count('minecraft:glass'))
 end
 local fuelNeeded=4
 if count('minecraft:iron_ingot')<7 then fuelNeeded=fuelNeeded+1 end
 if stoneShort>0 then fuelNeeded=fuelNeeded+math.ceil(stoneShort/8) end
 if count('minecraft:glass_pane')==0 and count('minecraft:glass')<6 then
  fuelNeeded=fuelNeeded+1
 end
 if countFuel()<fuelNeeded then
  needs[#needs+1]='coal/charcoal '..countFuel()..'/'..fuelNeeded
 end
 assert(#needs==0,'Missing first-birth inputs: '..table.concat(needs,'; '))
end
function M.run(jobId)
 state.assertSafe()
 assert(not state.data.manufacture,
    'Existing partial factory craft requires inventory reconciliation')
 assert(not state.data.replication,
    'Existing partial child deployment requires dedicated recovery')
 local prev=turtle.getSelectedSlot()
 if state.data.birth and jobId and state.data.birth.jobId
     and state.data.birth.jobId~=jobId then
  error('Different birth job is already being executed')
 end
 if state.data.birth and state.data.birth.childrenBefore
     and (state.data.children or 0)>state.data.birth.childrenBefore then
  -- Child already booted before the controller/journal recorded completion.
  state.data.birth=nil
  state.save()
  return true
 end
 if not state.data.birth then
  preflight()
  state.data.birth={stage='start',jobId=jobId,
      childrenBefore=state.data.children or 0}
  state.save()
 end
 -- Each operation uses observations; do not rely on saved phase alone.
 ensureChest()
 local needIron=count('minecraft:iron_ingot')<7
 local needStone=count('minecraft:stone')<14 and
   block('front')~='computercraft:disk_drive'
 local needGlass=count('minecraft:glass_pane')==0 and count('minecraft:glass')<6
 if needIron or needStone or needGlass then
  ensureFurnace()
  if needIron then ensureSmelt('iron',7) end
  if needStone then ensureSmelt('stone',14) end
  if needGlass then ensureSmelt('glass',6) end
 end
 if count('minecraft:glass_pane')==0 then
  craftIfMissing('glass_pane','minecraft:glass_pane',paneRecipe)
 end
 ensureDrive()
 if not childItemPresent() then
  phase('manufacture')
  local ok,reason=factory.make()
  assert(ok,'Child manufacture failed: '..tostring(reason))
 end
 phase('deploy_child')
 assert(not state.data.replication,'Interrupted clone needs dedicated recovery')
 replicate.lab()
 phase('complete')
 state.data.birth=nil
 state.save()
 turtle.select(prev)
 print('Birth sequence complete; worksite remains installed')
 return true
end
return M
