-- Furnace processing for Turtle Genesis. No mining, movement, or added infrastructure.
-- Parent faces a furnace; empty chest/barrel directly below.
local M = {}
local state = require('state')
local log = require('log')

local jobs = {
  iron = {input='minecraft:raw_iron', output='minecraft:iron_ingot'},
  gold = {input='minecraft:raw_gold', output='minecraft:gold_ingot'},
  stone = {input='minecraft:cobblestone', output='minecraft:stone'},
  glass = {input='minecraft:sand', output='minecraft:glass'},
  charcoal = {output='minecraft:charcoal', logs=true},
}

local function setup()
  local present, block = turtle.inspect()
  assert(present and block.name=='minecraft:furnace',
    'Face a normal furnace (not the disk drive)')
  local below, blockBelow = turtle.inspectDown()
  assert(below and (blockBelow.name=='minecraft:chest' or blockBelow.name=='minecraft:barrel'),
    'Place a chest or barrel immediately BELOW the turtle')
  local furnace = peripheral.wrap('front')
  local chest = peripheral.wrap('bottom')
  assert(furnace and type(furnace.list)=='function'
    and type(furnace.pushItems)=='function', 'Front furnace inventory is not exposed')
  assert(chest and type(chest.list)=='function'
    and type(chest.pushItems)=='function', 'Bottom chest inventory is not exposed')
  assert(furnace.size()>=3, 'Furnace must expose its 3 inventory slots')
  return furnace,chest
end

local function firstSlot(items,name)
  for slot,item in pairs(items) do
    if item.name==name then return slot,item.count end
  end
end

local function isLog(name)
  return type(name)=='string' and name:match('^minecraft:[%a_]+_log$')~=nil
end

local function findSource(job)
  for i=1,16 do
    local d=turtle.getItemDetail(i)
    if d and (d.name==job.input or (job.logs and isLog(d.name))) then
      return i,d
    end
  end
end

local function chooseFuel(kind)
  -- Planks are a last-resort bootstrap fuel for the FIRST charcoal smelt.
  -- One plank burns 1.5 items; using 1 item per plank avoids fractional
  -- furnace accounting and guarantees the batch finishes.
  for i=1,16 do
    local d=turtle.getItemDetail(i)
    if d and (d.name=='minecraft:coal' or d.name=='minecraft:charcoal') then
      return i,d,8
    end
  end
  if kind=='charcoal' then
    for i=1,16 do
      local d=turtle.getItemDetail(i)
      if d and d.name:match('^minecraft:[%a_]+_planks

local function noItems(t)
  return next(t.list())==nil
end

local function putBelow(slot,n)
  turtle.select(slot)
  local before=turtle.getItemCount(slot)
  assert(before>=n,'Not enough source items')
  assert(turtle.dropDown(n), 'Cannot transfer items into chest below')
  assert(before-turtle.getItemCount(slot)==n,'Chest accepted an unexpected item count')
end

local function getBelow(chest)
  local previous=turtle.getSelectedSlot()
  for _=1,30 do
    if noItems(chest) then turtle.select(previous);return end
    local selected
    for i=1,16 do
      if turtle.getItemCount(i)==0 then selected=i;break end
    end
    assert(selected,'Turtle inventory full; items remain safely in chest')
    turtle.select(selected)
    assert(turtle.suckDown(64),'Could not retrieve material from chest')
  end
  turtle.select(previous)
  error('Unable to empty staging chest after 30 attempts')
end

function M.probe()
  local furnace,chest=setup()
  print('Furnace and chest detected; generic inventory APIs available')
  for i=1,3 do
    local d=furnace.getItemDetail(i)
    print(('Furnace %d: %s'):format(i,d and (d.name..' x'..d.count) or 'empty'))
  end
  print('Chest items:', (function()
    local n=0;for _ in pairs(chest.list()) do n=n+1 end;return n
  end)())
end

-- Recover a smelt based on real furnace/chest contents rather than a saved
-- phase label. Safe to repeat after interruption; no new batch is created.
function M.resume()
  local jobState=state.data.processing
  if not jobState then return true end
  local furnace,chest=setup()
  local recipe=assert(jobs[jobState.kind],'Unknown unfinished process')
  local expected=recipe.output
  local maxWait=30 -- seconds without smelting progress before pausing
  local lastProgress=os.epoch('utc')
  local lastInput=nil

  print('Recovering unfinished '..jobState.kind..' smelt')
  while true do
    local product=furnace.getItemDetail(3)
    if product then
      assert(product.name==expected,
        'Unexpected furnace output; leaving it untouched: '..product.name)
      local moved=furnace.pushItems('bottom',3,product.count)
      assert(moved>0,'Could not transfer furnace output to chest')
      lastProgress=os.epoch('utc')
    end

    local input=furnace.getItemDetail(1)
    if not input then break end
    assert(input.name==jobState.input,
      'Furnace input changed; leaving it untouched')
    if not lastInput or input.count<lastInput then
      lastProgress=os.epoch('utc')
    end
    lastInput=input.count

    -- Let an existing furnace burn complete. If it runs out of fuel,
    -- return a retryable pause rather than requiring manual state resets.
    if os.epoch('utc')-lastProgress>maxWait*1000 then
      return false,'Furnace stopped smelting; add fuel and run station again'
    end
    sleep(0.5)
  end

  for _,slot in ipairs({3,2}) do
    local item=furnace.getItemDetail(slot)
    if item then
      local moved=furnace.pushItems('bottom',slot,item.count)
      assert(moved==item.count,'Cannot retrieve leftover furnace item')
    end
  end
  if not noItems(chest) then
    getBelow(chest)
  end
  state.data.processing=nil
  state.save()
  log.event('processed_recovered',jobState.kind)
  print('Unfinished smelt reconciled and items retrieved')
  return true
end

function M.run(kind)
  local job=assert(jobs[kind], 'Use: process iron|gold|stone|glass|charcoal')
  state.assertSafe()
  assert(not state.data.manufacture,'Finish or abort manufacturing before processing')
  if state.data.processing then
    local ok, reason=M.resume()
    if not ok then error(reason) end
    return true
  end
  local furnace,chest=setup()
  assert(noItems(furnace), 'Furnace is not empty; clear it before processing')
  assert(noItems(chest), 'Chest is not empty; run collect or empty it first')
  local sourceSlot,source=findSource(job)
  assert(sourceSlot,'Missing input for '..kind)
  local fuelSlot,fuel,smeltsPerFuel=chooseFuel(kind)
  assert(fuelSlot,'Need coal/charcoal, or planks to light first charcoal smelt')
  local amount=math.min(source.count,64,fuel.count*smeltsPerFuel)
  assert(amount>=1,'No material/fuel available')
  local fuelNeeded=math.ceil(amount/smeltsPerFuel)
  local expected=job.output
  local input=source.name
  local orig=turtle.getSelectedSlot()
  state.data.processing={kind=kind, input=input, amount=amount, stage='staging'}
  state.save()

  putBelow(sourceSlot,amount)
  putBelow(fuelSlot,fuelNeeded)
  state.data.processing.stage='loading_furnace'
  state.save()
  local fuelChestSlot=assert(firstSlot(chest.list(),fuel.name),'Fuel disappeared from chest')
  assert(chest.pushItems('front',fuelChestSlot,fuelNeeded,2)==fuelNeeded,
    'Furnace did not accept fuel through the inventory API')
  local inputChestSlot=assert(firstSlot(chest.list(),input),'Input disappeared from chest')
  assert(chest.pushItems('front',inputChestSlot,amount,1)==amount,
    'Furnace did not accept input through the inventory API')
  state.data.processing.stage='smelting'
  state.save()
  print(('Smelting %d %s -> %s'):format(amount,input,expected))

  local produced=0
  local deadline=os.epoch('utc')+amount*12000+30000
  while produced<amount do
    local item=furnace.getItemDetail(3)
    if item then
      assert(item.name==expected,'Unexpected furnace output: '..item.name)
      local moved=furnace.pushItems('bottom',3,item.count)
      assert(moved>0,'Could not move output from furnace to chest')
      produced=produced+moved
    end
    assert(os.epoch('utc')<=deadline,'Timed out smelting; resources remain in furnace/chest')
    if produced<amount then sleep(0.5) end
  end

  for _,slot in ipairs({2,1,3}) do
    local item=furnace.getItemDetail(slot)
    if item then
      local moved=furnace.pushItems('bottom',slot,item.count)
      assert(moved==item.count,'Unable to recover leftover furnace item')
    end
  end
  state.data.processing.stage='recovering_inventory'
  state.save()
  getBelow(chest)
  turtle.select(orig)
  state.data.processing=nil
  state.save()
  log.event('processed',kind..' x'..produced)
  print(('Processed %d %s. Output recovered.'):format(produced,expected))
  return produced
end

function M.reset()
  assert(state.data.processing,'No interrupted processing to clear')
  local furnace,chest=setup()
  assert(noItems(furnace) and noItems(chest),
    'Empty furnace and retrieve chest items before clearing processing state')
  state.data.processing=nil
  state.save()
  print('Processing state cleared; items must be accounted for manually')
end

return M
) then
        return i,d,1
      end
    end
  end
end

local function noItems(t)
  return next(t.list())==nil
end

local function putBelow(slot,n)
  turtle.select(slot)
  local before=turtle.getItemCount(slot)
  assert(before>=n,'Not enough source items')
  assert(turtle.dropDown(n), 'Cannot transfer items into chest below')
  assert(before-turtle.getItemCount(slot)==n,'Chest accepted an unexpected item count')
end

local function getBelow(chest)
  local previous=turtle.getSelectedSlot()
  for _=1,30 do
    if noItems(chest) then turtle.select(previous);return end
    local selected
    for i=1,16 do
      if turtle.getItemCount(i)==0 then selected=i;break end
    end
    assert(selected,'Turtle inventory full; items remain safely in chest')
    turtle.select(selected)
    assert(turtle.suckDown(64),'Could not retrieve material from chest')
  end
  turtle.select(previous)
  error('Unable to empty staging chest after 30 attempts')
end

function M.probe()
  local furnace,chest=setup()
  print('Furnace and chest detected; generic inventory APIs available')
  for i=1,3 do
    local d=furnace.getItemDetail(i)
    print(('Furnace %d: %s'):format(i,d and (d.name..' x'..d.count) or 'empty'))
  end
  print('Chest items:', (function()
    local n=0;for _ in pairs(chest.list()) do n=n+1 end;return n
  end)())
end

-- Recover a smelt based on real furnace/chest contents rather than a saved
-- phase label. Safe to repeat after interruption; no new batch is created.
function M.resume()
  local jobState=state.data.processing
  if not jobState then return true end
  local furnace,chest=setup()
  local recipe=assert(jobs[jobState.kind],'Unknown unfinished process')
  local expected=recipe.output
  local maxWait=30 -- seconds without smelting progress before pausing
  local lastProgress=os.epoch('utc')
  local lastInput=nil

  print('Recovering unfinished '..jobState.kind..' smelt')
  while true do
    local product=furnace.getItemDetail(3)
    if product then
      assert(product.name==expected,
        'Unexpected furnace output; leaving it untouched: '..product.name)
      local moved=furnace.pushItems('bottom',3,product.count)
      assert(moved>0,'Could not transfer furnace output to chest')
      lastProgress=os.epoch('utc')
    end

    local input=furnace.getItemDetail(1)
    if not input then break end
    assert(input.name==jobState.input,
      'Furnace input changed; leaving it untouched')
    if not lastInput or input.count<lastInput then
      lastProgress=os.epoch('utc')
    end
    lastInput=input.count

    -- Let an existing furnace burn complete. If it runs out of fuel,
    -- return a retryable pause rather than requiring manual state resets.
    if os.epoch('utc')-lastProgress>maxWait*1000 then
      return false,'Furnace stopped smelting; add fuel and run station again'
    end
    sleep(0.5)
  end

  for _,slot in ipairs({3,2}) do
    local item=furnace.getItemDetail(slot)
    if item then
      local moved=furnace.pushItems('bottom',slot,item.count)
      assert(moved==item.count,'Cannot retrieve leftover furnace item')
    end
  end
  if not noItems(chest) then
    getBelow(chest)
  end
  state.data.processing=nil
  state.save()
  log.event('processed_recovered',jobState.kind)
  print('Unfinished smelt reconciled and items retrieved')
  return true
end

function M.run(kind)
  local job=assert(jobs[kind], 'Use: process iron|gold|stone|glass|charcoal')
  state.assertSafe()
  assert(not state.data.manufacture,'Finish or abort manufacturing before processing')
  if state.data.processing then
    local ok, reason=M.resume()
    if not ok then error(reason) end
    return true
  end
  local furnace,chest=setup()
  assert(noItems(furnace), 'Furnace is not empty; clear it before processing')
  assert(noItems(chest), 'Chest is not empty; run collect or empty it first')
  local sourceSlot,source=findSource(job)
  assert(sourceSlot,'Missing input for '..kind)
  local fuelSlot,fuel=chooseCoal()
  assert(fuelSlot,'Need coal or charcoal to smelt')
  local amount=math.min(source.count,64, fuel.count*8)
  assert(amount>=1,'No material/fuel available')
  local fuelNeeded=math.ceil(amount/8)
  local expected=job.output
  local input=source.name
  local orig=turtle.getSelectedSlot()
  state.data.processing={kind=kind, input=input, amount=amount, stage='staging'}
  state.save()

  putBelow(sourceSlot,amount)
  putBelow(fuelSlot,fuelNeeded)
  state.data.processing.stage='loading_furnace'
  state.save()
  local fuelChestSlot=assert(firstSlot(chest.list(),fuel.name),'Fuel disappeared from chest')
  assert(chest.pushItems('front',fuelChestSlot,fuelNeeded,2)==fuelNeeded,
    'Furnace did not accept fuel through the inventory API')
  local inputChestSlot=assert(firstSlot(chest.list(),input),'Input disappeared from chest')
  assert(chest.pushItems('front',inputChestSlot,amount,1)==amount,
    'Furnace did not accept input through the inventory API')
  state.data.processing.stage='smelting'
  state.save()
  print(('Smelting %d %s -> %s'):format(amount,input,expected))

  local produced=0
  local deadline=os.epoch('utc')+amount*12000+30000
  while produced<amount do
    local item=furnace.getItemDetail(3)
    if item then
      assert(item.name==expected,'Unexpected furnace output: '..item.name)
      local moved=furnace.pushItems('bottom',3,item.count)
      assert(moved>0,'Could not move output from furnace to chest')
      produced=produced+moved
    end
    assert(os.epoch('utc')<=deadline,'Timed out smelting; resources remain in furnace/chest')
    if produced<amount then sleep(0.5) end
  end

  for _,slot in ipairs({2,1,3}) do
    local item=furnace.getItemDetail(slot)
    if item then
      local moved=furnace.pushItems('bottom',slot,item.count)
      assert(moved==item.count,'Unable to recover leftover furnace item')
    end
  end
  state.data.processing.stage='recovering_inventory'
  state.save()
  getBelow(chest)
  turtle.select(orig)
  state.data.processing=nil
  state.save()
  log.event('processed',kind..' x'..produced)
  print(('Processed %d %s. Output recovered.'):format(produced,expected))
  return produced
end

function M.reset()
  assert(state.data.processing,'No interrupted processing to clear')
  local furnace,chest=setup()
  assert(noItems(furnace) and noItems(chest),
    'Empty furnace and retrieve chest items before clearing processing state')
  state.data.processing=nil
  state.save()
  print('Processing state cleared; items must be accounted for manually')
end

return M
