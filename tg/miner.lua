-- Turtle Genesis v0.2: autonomous mining with fuel reserves and persistent progress.
-- No mining of blocks outside vanilla namespace; avoid infrastructure and liquids.
local M = {}
local state = require('state')
local nav = require('nav')
local fuel = require('fuel')
local log = require('log')

local SAFE_SKIP = {
  ['minecraft:bedrock']=true, ['minecraft:water']=true, ['minecraft:lava']=true,
  ['minecraft:barrier']=true, ['minecraft:tnt']=true,
  ['minecraft:chest']=true, ['minecraft:trapped_chest']=true,
  ['minecraft:ender_chest']=true, ['minecraft:barrel']=true,
  ['minecraft:furnace']=true, ['minecraft:blast_furnace']=true,
  ['minecraft:smoker']=true, ['minecraft:hopper']=true,
  ['minecraft:dispenser']=true, ['minecraft:dropper']=true,
  ['minecraft:crafting_table']=true, ['minecraft:spawner']=true,
  ['minecraft:beehive']=true, ['minecraft:bee_nest']=true,
}
local WASTE = {
  ['minecraft:cobblestone']=true, ['minecraft:cobbled_deepslate']=true,
  ['minecraft:stone']=true, ['minecraft:deepslate']=true,
  ['minecraft:dirt']=true, ['minecraft:grass_block']=true,
  ['minecraft:granite']=true, ['minecraft:diorite']=true,
  ['minecraft:andesite']=true, ['minecraft:tuff']=true,
  ['minecraft:gravel']=true, ['minecraft:flint']=true,
  ['minecraft:sand']=true, ['minecraft:netherrack']=true,
  ['minecraft:calcite']=true,
}
local MAX_RADIUS, MAX_FLOORS, FIRST_DESCENT, FLOOR_STEP = 32, 7, 24, 16
local FUEL_RESERVE = 32

local function copyPose(p)
  return {x=p.x,y=p.y,z=p.z,dir=p.dir}
end
local function mineable(name)
  return type(name)=='string' and name:sub(1,10)=='minecraft:'
    and not SAFE_SKIP[name] and not name:find('shulker_box',1,true)
    and not name:find('command_block',1,true)
end
local function isOre(name)
  return name and (name:match('_ore$') ~= nil or name=='minecraft:ancient_debris')
end
local function info()
  if not state.data.miner then
    state.data.miner = {running=false,stage='descend',targetY=state.data.pose.y-FIRST_DESCENT,
      level=1,radius=8,heading=0,home=copyPose(state.data.pose),trip=nil,
      ore=0,passes=0,reason='new'}
    state.save()
  end
  return state.data.miner
end
local function clearJunk()
  for slot=1,16 do if turtle.getItemCount(slot)==0 then return true end end
  local original=turtle.getSelectedSlot()
  local kept = {}
  for slot=1,16 do
    local item=turtle.getItemDetail(slot)
    if item and WASTE[item.name] then
      if (kept[item.name] or 0) >= 64 then
        turtle.select(slot)
        turtle.dropDown()
      else
        kept[item.name]=(kept[item.name] or 0)+item.count
      end
    end
  end
  turtle.select(original)
  for slot=1,16 do if turtle.getItemCount(slot)==0 then return true end end
  return false
end
local function dig(direction)
  local inspect = direction=='down' and turtle.inspectDown
    or direction=='up' and turtle.inspectUp or turtle.inspect
  local excavate = direction=='down' and turtle.digDown
    or direction=='up' and turtle.digUp or turtle.dig
  for i=1,5 do
    local exists, block=inspect()
    if not exists then return true end
    if not block or not mineable(block.name) then
      return false, 'protected block ' .. tostring(block and block.name)
    end
    local ok, reason=excavate()
    if not ok then return false, 'cannot dig ' .. tostring(block.name) .. ': ' .. tostring(reason) end
    if isOre(block.name) then
      local m=info(); m.ore=m.ore+1; state.save()
      print('Ore: ' .. block.name .. ' (total ' .. m.ore .. ')')
    end
    sleep(0.1)
  end
  return not (direction=='down' and turtle.detectDown()
    or direction=='up' and turtle.detectUp() or turtle.detect()), 'block keeps falling'
end
local function scanOre()
  for _, direction in ipairs({'up','down'}) do
    local check=direction=='up' and turtle.inspectUp or turtle.inspectDown
    local exists, block=check()
    if exists and block and isOre(block.name) then
      local ok,reason=dig(direction)
      if not ok then log.event('ore_skipped',reason) end
    end
  end
end
local function returnHome(m)
  local trip=m.trip
  local home=trip.home
  while state.data.pose.x~=home.x or state.data.pose.z~=home.z or state.data.pose.y~=home.y do
    local distance=math.abs(state.data.pose.x-home.x)+math.abs(state.data.pose.z-home.z)
      +math.abs(state.data.pose.y-home.y)
    if not fuel.ensure(distance) then error('No fuel to return from mining tunnel') end
    local ok,reason=nav.back()
    if not ok then error('Return path blocked: ' .. tostring(reason)) end
  end
  assert(state.data.pose.dir==home.dir,'Direction mismatch on tunnel return')
  m.trip=nil
  m.passes=m.passes+1
  m.heading=m.heading+1
  if m.heading>=4 then
    m.heading=0
    m.radius=m.radius+8
    if m.radius>MAX_RADIUS then
      if m.level>=MAX_FLOORS then
        m.stage='done'; m.running=false; m.reason='surveyed planned area'
      else
        m.stage='descend'; m.level=m.level+1
        m.targetY=state.data.pose.y-FLOOR_STEP
        m.radius=8
        print('Descending to mining level ' .. m.level)
      end
    end
  end
  state.save()
end
local function tunnel(m)
  if not m.trip then
    if not fuel.ensure(2*m.radius+FUEL_RESERVE) then
      m.running=false; m.reason='insufficient coal for round trip';state.save()
      print('Mining paused: insufficient fuel, not stranded')
      return false
    end
    local desired=(m.home.dir+m.heading)%4
    while state.data.pose.dir~=desired do assert(nav.right()) end
    m.trip={home=copyPose(state.data.pose),phase='out',goal=m.radius}
    state.save()
    print(('Mining level=%d direction=%d distance=%d fuel=%s'):format(
      m.level,m.heading,m.radius,tostring(turtle.getFuelLevel())))
  end
  local trip=m.trip
  assert(state.data.pose.dir==trip.home.dir,'Tunnel orientation changed; manual recovery required')
  if trip.phase=='out' then
    local home=trip.home
    local distance=math.abs(state.data.pose.x-home.x)+math.abs(state.data.pose.z-home.z)
      +math.abs(state.data.pose.y-home.y)
    if distance>=trip.goal then
      trip.phase='back';state.save()
    elseif not fuel.ensure(distance+FUEL_RESERVE+1) then
      trip.phase='back';m.reason='low fuel';state.save()
    elseif not clearJunk() then
      trip.phase='back';m.reason='inventory full of valuables';state.save()
    else
      scanOre()
      local ok,reason=dig('front')
      if ok then
        ok,reason=nav.forward()
        if ok then scanOre() end
      end
      if not ok then
        trip.phase='back';m.reason=tostring(reason);state.save()
        print('Tunnel stopped: ' .. tostring(reason))
      end
    end
  else
    returnHome(m)
  end
  return true
end
local function descend(m)
  if not fuel.ensure(math.abs(state.data.pose.y-m.targetY)+FUEL_RESERVE) then
    m.running=false;m.reason='need coal to descend';state.save()
    print('Mining paused: insufficient descent fuel')
    return false
  end
  if state.data.pose.y<=m.targetY then
    m.stage='tunnel';m.home=copyPose(state.data.pose)
    m.heading=0;m.trip=nil;state.save()
    print('Mining level ' .. m.level .. ' reached')
    return true
  end
  local ok,reason=dig('down')
  if ok then ok,reason=nav.down() end
  if not ok then
    m.running=false;m.reason='descent blocked: '..tostring(reason);state.save()
    print('Mining paused: '..m.reason)
    return false
  end
  scanOre()
  return true
end

function M.run(maxPasses)
  state.assertSafe()
  local m=info()
  if m.stage=='done' then print('Mining completed all planned levels');return end
  assert(not (m.trip and m.stage~='tunnel'), 'Invalid persisted miner state')
  if maxPasses then assert(maxPasses>=1 and maxPasses%1==0,'Pass count must be positive integer') end
  m.running=true;state.save()
  local startPasses=m.passes
  while m.running and (not maxPasses or m.passes-startPasses<maxPasses) do
    if m.stage=='descend' then
      if not descend(m) then break end
    elseif m.stage=='tunnel' then
      if not tunnel(m) then break end
    elseif m.stage=='done' then break
    else error('Unknown mining stage: '..tostring(m.stage)) end
  end
  if maxPasses and m.running then m.running=false; m.reason='requested passes complete';state.save() end
  print(('Mining paused: %s; ore=%d, tunnels=%d'):format(tostring(m.reason),m.ore,m.passes))
end

function M.status()
  local m=info()
  print(('Miner: %s, %s, level=%d radius=%d heading=%d'):format(
    m.running and 'RUNNING' or 'STOPPED',m.stage,m.level,m.radius,m.heading))
  print(('Ores=%d tunnels=%d reason=%s'):format(m.ore,m.passes,tostring(m.reason)))
  if m.trip then print('Tunnel phase:',m.trip.phase) end
end

function M.stop()
  local m=info();m.running=false;m.reason='user stopped';state.save()
  print('Miner disabled. If away from base, next auto run completes the return first.')
end
return M
