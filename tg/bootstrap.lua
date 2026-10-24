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
 assert(fuel.level()>=distance+RESERVE,
  ('Fuel low: need %d remaining movement units to return safely'):format(distance+RESERVE))
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
 for _=1,ascended do assert(nav.down(),'Cannot descend harvested trunk') end
 assert(nav.back(),'Cannot leave harvested tree location')
 print('Base: harvested logs in inventory: '..tostring(count(first)))
 -- If a sapling was collected during harvesting, replace the trunk.
 local sapling=first:gsub('_log$','_sapling')
 if selectItem(sapling) and not turtle.detect() then turtle.place() end
 turtle.select(old)
 return true
end
local function scan(resource,needed)
 local function have()
  if resource=='wood' then
   local _,n=matching('log');return n
  elseif resource=='sand' then return count('minecraft:sand') end
 end
 local before=have()
 for heading=1,4 do
  local dist=0
  for _=1,SEARCH do
   if have()>=needed then break end
   if fuel.level()<2*(dist+1)+TREE_HEIGHT*2+RESERVE then break end
   local current=block('front')
   if resource=='wood' and current
       and current:match('^minecraft:[%a_]+_log$') then
    mineLogColumn()
   end
   if not safeFront() then break end
   local ok=nav.forward()
   if not ok then break end
   dist=dist+1
   if resource=='sand' then
    local down=block('down')
    if down=='minecraft:sand' then
     turtle.digDown()
    end
   end
  end
  for _=1,dist do assert(nav.back(),'Return path to base is blocked') end
  assert(nav.right(),'Cannot change survey heading')
  local p,h=state.data.pose,state.data.bootstrap.home
  assert(p.x==h.x and p.y==h.y and p.z==h.z,
   'Survey failed to return to the base location')
  if have()>=needed then break end
 end
 -- Restore the base heading even if the search found enough material on
 -- its first or second ray. Returning only to (x,y,z) is insufficient.
 local original=state.data.bootstrap.home.dir
 while state.data.pose.dir~=original do
  assert(nav.right(),'Cannot restore base facing')
 end
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
local function firstChest()
 if block('down')=='minecraft:chest' then return end
 local wood,logs=matching('log')
 assert(wood and logs>=4,'Need at least four same-type logs before first chest')
 assert(type(turtle.craft)=='function','First turtle needs crafting upgrade equipped')
 local original=turtle.getSelectedSlot()
 cleanBeforeCraft(wood)
 for i=2,16 do
  if detail(i) then
   turtle.select(i)
   assert(turtle.transferTo(1),'Cannot merge bootstrap logs')
  end
 end
 assert(detail(1) and detail(1).name==wood,'Log staging failed')
 assert(logs<=16,'Oversized log stack for first-chest craft')
 turtle.select(16)
 local ok,why=turtle.craft(logs)
 assert(ok,'Cannot craft first planks: '..tostring(why))
 local planks=wood:gsub('_log$','_planks')
 assert(detail(16) and detail(16).name==planks,'Log conversion produced unexpected item')
 turtle.select(16)
 assert(turtle.transferTo(1),'Cannot move planks to crafting grid')
 for _,slot in ipairs({2,3,5,7,9,10,11}) do
  turtle.select(1)
  assert(turtle.transferTo(slot,1),'Cannot prepare chest recipe')
 end
 turtle.select(16)
 ok,why=turtle.craft(1)
 assert(ok,'First chest crafting failed: '..tostring(why))
 assert(count('minecraft:chest')>=1,'Crafted chest output missing')
 local down=block('down')
 assert(not down or ROCK[down] or SAFE[down],
  'Unsafe first chest placement over '..tostring(down))
 if down then assert(turtle.digDown(),'Cannot dig space for first chest') end
 assert(selectItem('minecraft:chest'),'First chest disappeared')
 ok,why=turtle.placeDown()
 assert(ok,'Cannot place first chest: '..tostring(why))
 assert(block('down')=='minecraft:chest','First chest not detected')
 turtle.select(original)
end
local function mineCobble()
 if count('minecraft:cobblestone')>=8 then return end
 atHome()
 assertFuel(2*SHAFT+16)
 -- Offset the shaft from the storage block, so no downward digging occurs
 -- in the home cell occupied by the chest.
 local moved=0
 for _=1,2 do
  assert(safeFront(),'No safe access from home to planned mining shaft')
  assert(nav.forward(),'Cannot approach shallow stone shaft')
  moved=moved+1
 end
 local depth=0
 for _=1,SHAFT do
  if count('minecraft:cobblestone')>=8 then break end
  local n=block('down')
  if not n or not ROCK[n] then break end
  assert(turtle.digDown(),'Cannot mine shaft material: '..n)
  assert(nav.down(),'Cannot descend cleared shaft')
  depth=depth+1
 end
 for _=1,depth do assert(nav.up(),'Cannot climb back up the shaft') end
 for _=1,moved do assert(nav.back(),'Cannot return from shallow shaft') end
 atHome()
 assert(count('minecraft:cobblestone')>=8,
  'Shallow shaft lacked eight cobblestone: safer to relocate than drill blindly')
end
local FURNACE={
 [1]='minecraft:cobblestone',[2]='minecraft:cobblestone',
 [3]='minecraft:cobblestone',[5]='minecraft:cobblestone',
 [7]='minecraft:cobblestone',[9]='minecraft:cobblestone',
 [10]='minecraft:cobblestone',[11]='minecraft:cobblestone'}
local function furnace()
 if block('front')=='minecraft:furnace' then return end
 if count('minecraft:furnace')==0 then
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
  end
 end
 turtle.select(old)
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
 atHome()
 if block('down')~='minecraft:chest' then
  mark('gather_first_wood')
  local _,n=scan('wood',4)
  assert(n>=4,'No accessible tree in local search; choose a wooded start area')
  mark('craft_and_place_first_chest')
  firstChest()
 end
 if count('minecraft:sand')<6 then
  mark('gather_sand')
  scan('sand',6)
  assert(count('minecraft:sand')>=6,
   'No six sand near home; relocate base near a river or sandy terrain')
 end
 if count('minecraft:cobblestone')<8 then
  mark('gather_cobblestone')
  mineCobble()
 end
 if block('front')~='minecraft:furnace' then
  mark('craft_and_place_furnace')
  furnace()
 end
 if count('minecraft:charcoal')==0 then
  -- A plank lights the first smelt. Harvest after constructing the chest
  -- but BEFORE occupying the front face with furnace; if a furnace already
  -- occupies front, other clear exploration rays may still work.
  mark('gather_charcoal_logs')
  local _,n=scan('wood',4)
  assert(n>=1,'Need one more tree for charcoal; no accessible logs')
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
return M
