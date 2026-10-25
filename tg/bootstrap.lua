-- Turtle Genesis M2: one bounded survival-world base/bootstrap job.
-- Only runs when enabled on a fresh, stocked-with-fuel turtle.
-- Uses the project's navigation, factory and furnace-processing subsystems.
local M={}
local state=require('state')
local nav=require('nav')
local fuel=require('fuel')
local factory=require('factory')
local process=require('process')

local SEARCH=12
local SHAFT=17
local RESERVE=36
local TREE_HEIGHT=14
local SAFE={['minecraft:short_grass']=true,['minecraft:tall_grass']=true,
 ['minecraft:grass']=true,['minecraft:snow']=true,['minecraft:fern']=true,
 ['minecraft:large_fern']=true,['minecraft:dead_bush']=true}
local ROCK={['minecraft:stone']=true,['minecraft:deepslate']=true,
 ['minecraft:granite']=true,['minecraft:diorite']=true,
 ['minecraft:andesite']=true,['minecraft:tuff']=true,
 ['minecraft:dirt']=true,['minecraft:grass_block']=true,
 ['minecraft:gravel']=true,['minecraft:clay']=true,
 ['minecraft:sandstone']=true}
local function detail(slot)return turtle.getItemDetail(slot) end
local function count(name)
 local total=0
 for i=1,16 do local d=detail(i)
  if d and d.name==name then total=total+d.count end
 end
 return total
end
local function matching(suffix)
 local name,total=nil,0
 for i=1,16 do local d=detail(i)
  if d and d.name:match('^minecraft:[%a_]+_'..suffix..'$') then
   local n=count(d.name)
   if n>total then total=n;name=d.name end
  end
 end
 return name,total
end
local function selectItem(name)
 for i=1,16 do local d=detail(i)
  if d and d.name==name then turtle.select(i);return true end
 end
 return false
end
local function block(which)
 local f,d
 if which=='front' then f,d=turtle.inspect()
 elseif which=='down' then f,d=turtle.inspectDown()
 else f,d=turtle.inspectUp() end
 return f and d and d.name or nil
end
local function mark(stage)
 state.data.bootstrap.stage=stage
 state.save()
 print('Base: '..stage)
end
local function samePose(a,b)
 return a and b and a.x==b.x and a.y==b.y and a.z==b.z
    and a.dir==b.dir
end
local function atHome()
 assert(samePose(state.data.pose,state.data.bootstrap.home),
  'Turtle is not at the saved base origin; refusing to guess a return route')
end
local function assertFuel(distance)
 local required=distance+RESERVE
 -- A mature colony must consume its own harvested charcoal to keep moving.
 -- fuel.ensure burns only the minimum required coal/charcoal from inventory.
 assert(fuel.ensure(required),
  ('Fuel low: need %d remaining movement units to return safely'):format(required))
end
local function safeFront()
 local n=block('front')
 if not n then return true end
 if SAFE[n] then
  assert(turtle.dig(),'Unable to clear harmless vegetation')
  return not turtle.detect()
 end
 return false
end
local function mineLogColumn()
 local first=block('front')
 if not first or not first:match('^minecraft:[%a_]+_log$') then return false end
 print('Base: harvesting '..first)
 assertFuel(TREE_HEIGHT*2+SEARCH*2+2)
 local old=turtle.getSelectedSlot()
 local ok,why=turtle.dig()
 assert(ok,'Cannot harvest tree trunk: '..tostring(why))
 ok,why=nav.forward()
 assert(ok,'Cannot enter harvested trunk space: '..tostring(why))
 local ascended=0
 for _=1,TREE_HEIGHT do
  local upper=block('up')
  if not upper or not upper:match('^minecraft:[%a_]+_log$') then break end
  assert(turtle.digUp(),'Failed to cut next trunk log')
  assert(nav.up(),'Failed to rise inside tree trunk')
  ascended=ascended+1
 end
 -- Opportunistically gather saplings from a few leaf faces around the
 -- original tree canopy. Sapling drops are not guaranteed.
 local leaves=first:gsub('_log$','_leaves')
 local layers=math.min(3,ascended+1)
 for layer=1,layers do
  for _=1,4 do
   if block('front')==leaves then turtle.dig() end
   assert(nav.right(),'Unable to inspect surrounding tree foliage')
  end
  if layer<layers then
   assert(nav.down(),'Cannot descend under tree canopy')
   ascended=ascended-1
  end
 end
 for _=1,ascended do assert(nav.down(),'Cannot descend harvested tree') end
 assert(nav.back(),'Cannot leave harvested tree location')
 print('Base: harvested logs in inventory: '..tostring(count(first)))
 -- If a sapling was collected during harvesting, replace the trunk.
 local sapling=first:gsub('_log$','_sapling')
 -- Keep replanted saplings away from the permanent furnace cell at home.
 local p,h=state.data.pose,state.data.bootstrap.home
 local worksiteFace=(p.x==h.x and p.y==h.y and p.z==h.z and p.dir==h.dir)
 if not worksiteFace and selectItem(sapling) and not turtle.detect() then
  turtle.place()
 end
 turtle.select(old)
 return true
end
-- The explorer never destroys unknown blocks and never crosses a knowingly
-- unsupported ledge. Successful movement is journaled by nav.lua along with
-- the tracked pose. Rewind works after ordinary reboots; an interrupted step
-- leaves state.pending set and is intentionally NOT auto-reconciled.
local reverse={forward='back',back='forward',up='down',down='up'}
local function face(dir)
 for _=1,4 do
  if state.data.pose.dir==dir then return end
  assert(nav.right(),'Failed to restore exploration heading')
 end
 error('Could not face planned exploration direction')
end
local function rewindTrail(depth)
 local trail=assert(state.data.forageTrail,'No saved exploration route')
 depth=depth or 0
 assert(depth>=0 and depth<=#trail.moves,'Invalid return depth')
 while #trail.moves>depth do
  local step=trail.moves[#trail.moves]
  assert(step and reverse[step.action],'Malformed exploration breadcrumb')
  face(step.dir)
  assert(fuel.ensure(#trail.moves+RESERVE+4),
   'Not enough fuel to safely retrace exploration breadcrumbs')
  local before=#trail.moves
  local ok,why=nav[reverse[step.action]]()
  assert(ok,'Cannot retrace '..step.action..' step: '..tostring(why))
  assert(#trail.moves==before-1,
   'Breadcrumb stack did not shrink after returning')
 end
end
local function recoverExploration()
 local trail=state.data.forageTrail
 if not trail then return end
 assert(trail.origin and type(trail.moves)=='table',
  'Exploration recovery data incomplete; refusing unsafe navigation')
 print('Base: recovering '..#trail.moves..' saved exploration steps')
 rewindTrail(0)
 face(trail.origin.dir)
 assert(samePose(state.data.pose,trail.origin),
  'Saved explorer route did not return to its original home')
 state.data.forageTrail=nil
 state.save()
end
-- The shaft no longer has a fixed position two blocks in front of home.
-- This routine is only called from an explored, supported surface cell and
-- uses the exact same durable breadcrumbs as the rest of the terrain search.
local SHAFT_SAFE={
 ['minecraft:grass_block']=true,['minecraft:dirt']=true,
 ['minecraft:coarse_dirt']=true,['minecraft:stone']=true,
 ['minecraft:granite']=true,['minecraft:diorite']=true,
 ['minecraft:andesite']=true,['minecraft:tuff']=true
}
local function probeCobble()
 local route=assert(state.data.forageTrail,'Shaft requires active forage route')
 local p,h=state.data.pose,state.data.bootstrap.home
 if p.y~=h.y or math.abs(p.x-h.x)+math.abs(p.z-h.z)<2 then return end
 local checkpoint=#route.moves
 local oldSlot=turtle.getSelectedSlot()
 local caps={'minecraft:dirt','minecraft:coarse_dirt','minecraft:granite',
  'minecraft:diorite','minecraft:andesite','minecraft:tuff','minecraft:cobblestone'}
 local function capMaterial()
  for _,name in ipairs(caps) do
   -- Keep the eight cobble needed for the actual furnace, never sacrifice it
   -- merely to cover an otherwise exhausted shaft.
   if count(name)>(name=='minecraft:cobblestone' and 8 or 0) then
    return name
   end
  end
 end
 for _=1,SHAFT do
  local extra=(capMaterial() and 0 or 1)
  if count('minecraft:cobblestone')>=8+extra then break end
  local below=block('down')
  if not below or not SHAFT_SAFE[below] then break end
  if not fuel.ensure(2*(#route.moves+1)+RESERVE+8) then break end
  local free=false
  for i=1,16 do
   local d=detail(i)
   if not d or (turtle.getItemSpace and turtle.getItemSpace(i)>0) then
    free=true;break
   end
  end
  if not free then break end
  assert(turtle.digDown(),'Cannot excavate shallow mining shaft')
  assert(nav.down(),'Cannot descend a mined shaft safely')
 end
 rewindTrail(checkpoint)
 if not block('down') then
  -- Leaving an open hole on the outbound route would break the next trip.
  -- Plug with a recovered nonessential block; spare cobble is a fallback.
  local item=assert(capMaterial(),'Cannot cap shallow shaft without spare solid material')
  assert(selectItem(item),'Shaft cap material disappeared')
  assert(turtle.placeDown(),'Could not cap excavated shaft with '..item)
  assert(block('down'),'Shaft cap did not become solid ground')
 end
 turtle.select(oldSlot)
end
local function scan(resource,needed)
 local function have()
  if resource=='wood' then
   local _,n=matching('log');return n
  elseif resource=='sand' then return count('minecraft:sand')
  elseif resource=='cobble' then return count('minecraft:cobblestone') end
 end
 assert(resource=='wood' or resource=='sand' or resource=='cobble',
  'Unsupported forage target')
 atHome()
 assert(not state.data.forageTrail,'An old exploration route must be recovered first')
 local home=state.data.bootstrap.home
 state.data.forageTrail={origin={x=home.x,y=home.y,z=home.z,dir=home.dir},moves={}}
 state.save()
 local trail=state.data.forageTrail
 local before=have()
 local shafts,visited=0,{}
 -- Movement budget includes retracing every successful outbound step and
 -- the reserved fuel needed to ascend/descend a harvested tree.
 local function walk()
  if have()>=needed then return false end
  if not fuel.ensure(2*(#trail.moves+5)+TREE_HEIGHT*2+RESERVE) then
   return false
  end
  local ahead=block('front')
  if resource=='wood' and ahead
      and ahead:match('^minecraft:[%a_]+_log$') then
   mineLogColumn()
  elseif resource=='sand' and ahead=='minecraft:sand' then
   for _=1,6 do
    if have()>=needed or block('front')~='minecraft:sand' then break end
    if not turtle.dig() then break end
   end
  end
  if not safeFront() then return false end
  local depth=#trail.moves
  local ok=nav.forward()
  if not ok then return false end
  -- The target may have been an exposed cliff edge or a fluid surface.
  -- Retreat immediately; never continue further into unsupported terrain.
  local ground=block('down')
  if not ground or ground=='minecraft:lava' or ground=='minecraft:water' then
   rewindTrail(depth)
   return false
  end
  if resource=='sand' and ground=='minecraft:sand' and have()<needed then
   assert(turtle.digDown(),'Could not gather sand below explored path')
  elseif resource=='cobble' and have()<needed and shafts<6 then
   local p,h=state.data.pose,state.data.bootstrap.home
   local key=p.x..':'..p.z
   if not visited[key] and p.y==h.y and
      math.abs(p.x-h.x)+math.abs(p.z-h.z)>=2 and SHAFT_SAFE[ground] then
    visited[key]=true
    shafts=shafts+1
    probeCobble()
   end
  end
  return true
 end
 local function detour(heading,dist)
  -- Test either side for a path around a narrow (up to six-block-long)
  -- obstruction. Never tunnel through the protected original front blocks.
  local maxAdvance=math.min(6,SEARCH-dist)
  if maxAdvance<1 then return nil end
  local startDepth=#trail.moves
  for _,side in ipairs({(heading+1)%4,(heading+3)%4}) do
   face(side)
   if walk() then
    face(heading)
    for advanced=1,maxAdvance do
     if not walk() then break end
     face((side+2)%4)
     if walk() then
      face(heading)
      return advanced
     end
     face(heading)
    end
   end
   rewindTrail(startDepth)
   face(heading)
  end
  return nil
 end
 -- Survey four compass rays, bypassing short obstructions whenever
 -- possible. Every side excursion returns to the original ray before the
 -- next forward step; the full physical route is retraced from breadcrumbs.
 for i=0,3 do
  local heading=(home.dir+i)%4
  face(heading)
  local dist=0
  while dist<SEARCH and have()<needed do
   if walk() then
    dist=dist+1
   else
    local advanced=detour(heading,dist)
    if not advanced then break end
    dist=dist+advanced
   end
  end
  rewindTrail(0)
  face(home.dir)
  assert(samePose(state.data.pose,home),'Explorer did not return to base')
  if have()>=needed then break end
 end
 state.data.forageTrail=nil
 state.save()
 atHome()
 return have()-before,have()
end
local function cleanBeforeCraft(wood)
 -- The first chest must be crafted before a mixed inventory is accumulated.
 -- Preserve the matching logs and discard only wild drops (leaves, saplings,
 -- dirt, sticks). Starting turtle inventory is checked before gathering.
 for i=1,16 do local d=detail(i)
  if d and d.name~=wood then
   turtle.select(i)
   assert(turtle.drop(),'Cannot clear incidental foraging item '..d.name)
  end
 end
end
-- Recoverable chestless crafting: retries observe what was physically
-- produced, instead of harvesting extra trees or discarding finished planks.
local function firstChest()
 if block('down')=='minecraft:chest' then return end
 assert(type(turtle.craft)=='function','First turtle needs crafting upgrade equipped')
 local original=turtle.getSelectedSlot()
 if count('minecraft:chest')==0 then
  local planks,plankCount=matching('planks')
  if not planks or plankCount<8 then
   local wood,logs=matching('log')
   assert(wood and logs>=4,'Need at least four same-type logs before first chest')
   assert(logs<=16,'Oversized log stack for first-chest craft')
   cleanBeforeCraft(wood)
   for i=2,16 do
    if detail(i) then
     turtle.select(i)
     assert(turtle.transferTo(1) and not detail(i),
      'Cannot consolidate bootstrap logs')
    end
   end
   assert(detail(1) and detail(1).name==wood,'Log staging failed')
   mark('convert_first_logs')
   turtle.select(16)
   -- turtle.craft(limit) counts RECIPE STEPS, not output items:
   -- each log step yields four planks.
   local ok,why=turtle.craft(logs)
   assert(ok,'Cannot craft first planks: '..tostring(why))
   planks=wood:gsub('_log$','_planks')
   assert(count(planks)>=8,'Log conversion produced too few planks')
  else
   -- The prior run may have completed log conversion or been interrupted
   -- midway through arranging the 3x3 chest pattern.
   mark('resume_first_planks')
  end
  cleanBeforeCraft(planks)
  -- Reconstruct the recipe from physical inventory every time. This handles
  -- all partial item transfers between slots without replaying log crafting.
  for i=2,16 do
   if detail(i) then
    turtle.select(i)
    assert(turtle.transferTo(1) and not detail(i),
     'Cannot consolidate bootstrap planks')
   end
  end
  assert(detail(1) and detail(1).name==planks and
   detail(1).count>=8,'At least eight matching planks needed')
  mark('craft_first_chest')
  for _,slot in ipairs({2,3,5,7,9,10,11}) do
   turtle.select(1)
   assert(turtle.transferTo(slot,1),'Cannot prepare chest recipe')
  end
  turtle.select(16)
  local valid,why=turtle.craft(0)
  assert(valid,'First chest pattern invalid: '..tostring(why))
  local ok,err=turtle.craft(1)
  assert(ok,'First chest crafting failed: '..tostring(err))
  assert(count('minecraft:chest')>=1,'Crafted chest output missing')
 else
  -- Crash after successful chest craft: do not spend any more wood.
  mark('resume_placed_chest_item')
 end
 local down=block('down')
 assert(not down or ROCK[down] or SAFE[down],
  'Unsafe first chest placement over '..tostring(down))
 if down then assert(turtle.digDown(),'Cannot dig space for first chest') end
 assert(selectItem('minecraft:chest'),'First chest disappeared')
 mark('place_first_chest')
 local ok,why=turtle.placeDown()
 assert(ok,'Cannot place first chest: '..tostring(why))
 assert(block('down')=='minecraft:chest','First chest not detected')
 turtle.select(original)
end
local function mineCobble()
 if count('minecraft:cobblestone')>=8 then return end
 atHome()
 local _,available=scan('cobble',8)
 assert(available>=8,
  'No safe shallow stone shaft found in bounded terrain; base preserved')
end
local FURNACE={
 [1]='minecraft:cobblestone',[2]='minecraft:cobblestone',
 [3]='minecraft:cobblestone',[5]='minecraft:cobblestone',
 [7]='minecraft:cobblestone',[9]='minecraft:cobblestone',
 [10]='minecraft:cobblestone',[11]='minecraft:cobblestone'}
local function furnace()
 if block('front')=='minecraft:furnace' then return end
 if count('minecraft:furnace')==0 then
  -- Save intent before craftStep moves ingredients into the chest.
  -- A reboot may occur after those items are staged but before output.
  mark('craft_bootstrap_furnace')
  factory.craftStep('bootstrap_furnace',FURNACE,'minecraft:furnace')
 end
 local n=block('front')
 assert(not n or ROCK[n] or SAFE[n],
  'Unsafe furnace placement over '..tostring(n))
 if n then assert(turtle.dig(),'Could not clear furnace front cell') end
 assert(selectItem('minecraft:furnace'),'Furnace item missing')
 assert(turtle.place(),'Furnace placement failed')
 assert(block('front')=='minecraft:furnace','Furnace missing after placement')
end
local function deposit()
 -- Keep charcoal for future turtle refueling. Store mineral products and
 -- leftover logs/planks where the central planner can observe them.
 local keep={'minecraft:charcoal','minecraft:coal'}
 local retain={};for _,name in ipairs(keep) do retain[name]=true end
 local old=turtle.getSelectedSlot()
 for i=1,16 do local d=detail(i)
  if d and not retain[d.name] then
   turtle.select(i)
   assert(turtle.dropDown(),'Storage chest full; cannot deposit '..d.name)
   -- dropDown can return success for a PARTIAL transfer if the chest filled.
   -- Never label a stockpile complete while materials remain in the turtle.
   assert(turtle.getItemCount(i)==0,
    'Storage chest only accepted part of '..d.name..'; retry after making room')
  end
 end
 turtle.select(old)
end
-- Also usable by future maintenance jobs. Testing this public primitive exercises
-- the REAL navigator, trail journal and resource scanner together.
function M.searchTerrain(resource,needed)
 state.assertSafe()
 recoverExploration()
 return scan(resource,needed)
end
function M.run(jobId)
 state.assertSafe()
 local current=state.data.bootstrap
 if current and current.complete then return true end
 if not current then
  local hasInventory=false
  for i=1,16 do if detail(i) then hasInventory=true;break end end
  assert(not hasInventory,'M2 initial turtle must have empty inventory; load movement fuel into turtle first')
  assert(type(turtle.craft)=='function',
   'M2 needs a Mining + Crafting Turtle, not a Mining-only turtle')
  assert(fuel.level()>=140,'M2 starts with at least 140 movement fuel loaded')
  state.data.bootstrap={stage='start',home={
   x=state.data.pose.x,y=state.data.pose.y,z=state.data.pose.z,
   dir=state.data.pose.dir},jobId=jobId,complete=false}
  state.save()
 else
  assert(not current.jobId or current.jobId==jobId,
    'Another base job is already in progress')
 end
 -- A normal reboot between movements is recoverable using saved steps.
 -- state.assertSafe still refuses any interrupted / physically ambiguous move.
 recoverExploration()
 atHome()
 if block('down')~='minecraft:chest' then
  -- An interrupted conversion may already have yielded planks or a chest.
  -- Avoid a new forest trip unless there is insufficient material to craft.
  local _,plankCount=matching('planks')
  if count('minecraft:chest')==0 and plankCount<8 then
   mark('gather_first_wood')
   local _,n=scan('wood',4)
   assert(n>=4,'No accessible tree in local search; choose a wooded start area')
  end
  mark('craft_and_place_first_chest')
  firstChest()
 end
 if count('minecraft:sand')<6 then
  mark('gather_sand')
  scan('sand',6)
  assert(count('minecraft:sand')>=6,
   'No six sand near home; relocate base near a river or sandy terrain')
 end
 -- If an interrupted furnace recipe left cobble or other inputs in the
 -- temporary chest, recover them BEFORE checking whether to mine more stone.
 -- This is safe to repeat: collect() is a no-op for an empty chest.
 local stage=state.data.bootstrap.stage
 if stage=='craft_bootstrap_furnace' or stage=='recover_bootstrap_furnace' then
  assert(block('down')=='minecraft:chest',
   'Cannot recover first furnace crafting without the base chest')
  mark('recover_bootstrap_furnace')
  factory.collect()
  mark('furnace_materials_recovered')
 end
 -- A carried or placed furnace has already consumed construction stone.
 -- Do not remine the same eight blocks during an interrupted charcoal run.
 if block('front')~='minecraft:furnace' and
     count('minecraft:furnace')==0 and
     count('minecraft:cobblestone')<8 then
  mark('gather_cobblestone')
  mineCobble()
 end
 if block('front')~='minecraft:furnace' then
  mark('craft_and_place_furnace')
  furnace()
 end
 -- A power cut during smelting leaves inputs/outputs in the actual furnace.
 -- Reconcile that physical batch FIRST; do not harvest another tree or start
 -- another batch just because the turtle's inventory lacks charcoal.
 if state.data.processing then
  mark('resume_first_charcoal')
  local ok,reason=process.resume()
  assert(ok,'Cannot resume interrupted charcoal: '..tostring(reason))
 end
 if count('minecraft:charcoal')==0 then
  -- A plank lights the initial batch. Reuse harvested logs after recovery,
  -- gathering another tree only when the turtle genuinely lacks fuel inputs.
  local _,n=matching('log')
  if n<1 then
   mark('gather_charcoal_logs')
   _,n=scan('wood',4)
  end
  assert(n>=1,'Need another tree for charcoal; no accessible logs')
  mark('smelt_first_charcoal')
  process.run('charcoal')
 end
 atHome()
 assert(block('down')=='minecraft:chest' and
        block('front')=='minecraft:furnace','Base infrastructure missing')
 assert(count('minecraft:charcoal')>=1,'Charcoal production did not generate fuel')
 mark('store_materials')
 deposit()
 current=state.data.bootstrap
 current.complete=true
 current.stage='complete'
 state.save()
 print('Base: complete; chest, furnace and charcoal available at home')
 return true
end
-- Reusable fuel loop after the first base has been established.
-- Job ID is recorded after successful processing to prevent duplicate batches
-- if a network response is lost after the furnace completes.
function M.fuelCycle(jobId)
 state.assertSafe()
 local home=assert(state.data.bootstrap,'No initialized M2 base')
 assert(home.complete,'Fuel maintenance requires a completed base')
 assert(jobId and type(jobId)=='string','Fuel job ID required')
 if state.data.lastFuelJob==jobId then return true end
 recoverExploration()
 if state.data.fuelCycle then
  assert(state.data.fuelCycle.jobId==jobId,
   'Finish the interrupted fuel cycle before accepting another job')
 end
 atHome()
 assert(block('down')=='minecraft:chest',
  'Base storage is missing; refuse to stage items in open air')
 assert(block('front')=='minecraft:furnace',
  'Base furnace no longer faces the turtle')
 local old=turtle.getSelectedSlot()
 if not state.data.fuelCycle then
  state.data.fuelCycle={jobId=jobId,stage='prepare'}
  state.save()
 end
 -- Recover the furnace transaction BEFORE retrieving items from its staging
 -- chest; otherwise a restart may remove unprocessed furnace inputs.
 if state.data.processing then
  state.data.fuelCycle.stage='recover_smelt'
  state.save()
  local ok,reason=process.resume()
  assert(ok,'Previous charcoal processing is paused: '..tostring(reason))
 end
 local chest=peripheral.wrap('bottom')
 assert(chest and type(chest.list)=='function','Cannot inspect the base storage')
 local stored=chest.list()
 assert(type(stored)=='table','Base storage inventory not readable')
 if next(stored) then
  local storedSlots,freeSlots=0,0
  for _,item in pairs(stored) do
   if item and (item.count or 0)>0 then storedSlots=storedSlots+1 end
  end
  for i=1,16 do if not detail(i) then freeSlots=freeSlots+1 end end
  -- Conservatively reserve a complete turtle slot for each chest stack.
  -- Stop before moving any items if there is not enough room.
  assert(storedSlots<=freeSlots,
   ('Base chest has %d stacks but only %d empty turtle slots; '..
    'free inventory space before fuel maintenance'):format(storedSlots,freeSlots))
  factory.collect()
 end
 -- Refueling the turtle is part of the fuel cycle, not a player task.
 -- Try to restore a reasonable travel budget before considering how many
 -- charcoal items remain. This can deliberately trigger a replacement batch.
 if fuel.level()<120 then fuel.ensure(120) end
 if count('minecraft:charcoal')+count('minecraft:coal')>=3 then
  deposit()
  turtle.select(old)
  -- Completion is committed only after the material was actually stored.
  state.data.lastFuelJob=jobId
  state.data.fuelCycle=nil
  state.save()
  return true
 end
 state.data.fuelCycle.stage='harvest_more_wood'
 state.save()
 local wood,logs=matching('log')
 if not wood or logs<3 then
  scan('wood',4)
  wood,logs=matching('log')
 end
 assert(wood and logs>=2,'Insufficient accessible trees for another fuel batch')
 local plankName=wood:gsub('_log$','_planks')
 if count(plankName)<math.min(logs,4) and
     count('minecraft:coal')+count('minecraft:charcoal')==0 then
  state.data.fuelCycle.stage='craft_furnace_fuel'
  state.save()
  factory.craftStep('wooden_fuel_planks',{[1]=wood},plankName)
 end
 assert(count(wood)>=1,'No logs left to smelt after obtaining furnace fuel')
 state.data.fuelCycle.stage='make_charcoal'
 state.save()
 if state.data.processing then
  local ok,reason=process.resume()
  assert(ok,'Cannot finish interrupted charcoal: '..tostring(reason))
 else
  process.run('charcoal')
 end
 atHome()
 assert(count('minecraft:charcoal')>=1,
  'Charcoal fuel cycle finished without recovering charcoal')
 deposit()
 turtle.select(old)
 state.data.lastFuelJob=jobId
 state.data.fuelCycle=nil
 state.save()
 print('Base: charcoal replenished and surplus stored')
 return true
end
function M.woodCycle(jobId)
 state.assertSafe()
 assert(state.data.bootstrap and state.data.bootstrap.complete,'Base not established')
 assert(type(jobId)=='string','Missing job ID')
 if state.data.lastWoodJob==jobId then return true end
 recoverExploration()
 local running=state.data.woodCycle
 assert(not running or running.jobId==jobId,'Different lumber job in progress')
 atHome()
 assert(block('down')=='minecraft:chest' and block('front')=='minecraft:furnace',
  'Worksite chest/furnace required')
 assert(not state.data.processing and not state.data.manufacture and
  not state.data.birth,'Worksite busy')
 local old=turtle.getSelectedSlot()
 if not running then
  state.data.woodCycle={jobId=jobId,stage='collect'}
  state.save()
 end
 local chest=assert(peripheral.wrap('bottom'),'Storage unavailable')
 local stored=assert(chest.list(),'Cannot read storage')
 local occupied,free=0,0
 for _,item in pairs(stored) do
  if item and item.count and item.count>0 then occupied=occupied+1 end
 end
 for i=1,16 do if not detail(i) then free=free+1 end end
 assert(occupied<=free,'Not enough turtle slots to retrieve stored stock')
 if next(stored) then factory.collect() end
 local function planks()local _,n=matching('planks');return n end
 for _=1,12 do
  if planks()>=14 then break end
  local wood,logs=matching('log')
  if not wood or logs<1 then
   state.data.woodCycle.stage='harvest'
   state.save()
   scan('wood',4)
   wood,logs=matching('log')
  end
  assert(wood and logs>0,'No reachable logs for plank reserve')
  state.data.woodCycle.stage='craft'
  state.save()
  factory.craftStep('reserve_planks',{[1]=wood},wood:gsub('_log$','_planks'))
 end
 assert(planks()>=14,'Same-species plank reserve remains below 14')
 state.data.woodCycle.stage='store'
 state.save()
 deposit()
 turtle.select(old)
 state.data.lastWoodJob=jobId
 state.data.woodCycle=nil
 state.save()
 return true
end

return M
