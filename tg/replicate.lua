-- Controlled reproduction test. Parent faces disk drive; deployment cell behind is empty.
-- Fresh turtle items have no disk mount until placed and initialized.
local M = {}
local config = require('config')
local state = require('state')
local nav = require('nav')
local clone = require('clone')
local fuel = require('fuel')
local log = require('log')

local function findTurtle()
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and item.name:find('^computercraft:turtle_') then return i end
  end
  return nil
end

local function mark(stage)
  assert(state.data.replication, 'No replication in progress')
  state.data.replication.stage = stage
  state.save()
  log.event('replication', stage)
  print('Replication: ' .. stage)
end

local function turnAround()
  assert(nav.right())
  assert(nav.right())
end

local function takeFromDrive()
  assert(disk.isPresent('front'), 'No item in drive to recover')
  local ok = turtle.suck(1)
  if not ok then
    print('Direct extraction failed; trying disk eject...')
    disk.eject('front')
    sleep(0.5)
    ok = turtle.suck(1)
  end
  assert(ok and findTurtle(),
    'Could not collect turtle from disk drive; check drive and dropped item')
  assert(not disk.isPresent('front'), 'Drive still occupied after retrieving turtle')
  return findTurtle()
end

local function describeFront()
  local found, detail = turtle.inspect()
  local block = found and detail.name or ('none (' .. tostring(detail) .. ')')
  print('Front block: ' .. block)
  print('Front peripheral: ' .. tostring(peripheral.getType('front')))
  print('Attached: ' .. table.concat(peripheral.getNames(), ', '))
  return found and detail.name or nil
end

local function childPeripheral()
  local name = describeFront()
  assert(name and name:find('computercraft:turtle', 1, true),
    'The block in front is not a CC turtle')
  local p
  -- A peripheral may become available a tick after placing a block.
  for i = 1, 10 do
    p = peripheral.wrap('front')
    if p and type(p.turnOn) == 'function' and type(p.getID) == 'function'
      and type(p.shutdown) == 'function' then return p end
    sleep(0.1)
  end
  error('Front turtle block exists, but no computer peripheral can be accessed')
end

local function finishInitialization()
  -- Also used to resume safely after a failed placement-stage check.
  local childComputer = childPeripheral()
  childComputer.turnOn()
  sleep(0.5)
  local id = childComputer.getID()
  assert(type(id) == 'number', 'Child did not obtain an ID')
  print('Initialized child ID: ' .. id)
  childComputer.shutdown()
  sleep(0.2)
  mark('init_shutdown')

  assert(turtle.dig(), 'Could not pick up initialized child with mining upgrade')
  if not findTurtle() then turtle.suck(1) end
  assert(findTurtle(), 'Initialized child not recovered after digging')
  mark('init_collected')
  turnAround()
  mark('init_facing_drive')
  assert(not disk.isPresent('front'), 'Disk drive unexpectedly occupied')
  turtle.select(assert(findTurtle()))
  assert(turtle.drop(1), 'Could not insert initialized turtle into drive')
  mark('initialized_inserted')
  sleep(0.3)
  assert(disk.getMountPath('front'),
    'Initialized turtle still has no mount; cannot program')
end

local function initializeChild()
  print('Uninitialized turtle: assigning a computer ID before cloning')
  local child = takeFromDrive()
  mark('init_retrieved')
  turnAround()
  mark('init_facing_child')
  assert(not turtle.detect(), 'Space behind parent must be empty')
  turtle.select(child)
  assert(turtle.place(), 'Could not place fresh turtle for initialization')
  mark('init_placed')
  finishInitialization()
end

local function programAndDeploy()
  if not disk.getMountPath('front') then initializeChild() end
  assert(disk.getMountPath('front'), 'Child turtle drive has no filesystem')
  clone.install('front')
  mark('programmed')
  local child = takeFromDrive()
  mark('programmed_retrieved')

  turnAround()
  mark('facing_deployment')
  assert(not turtle.detect(), 'Deployment space behind parent must be empty')
  turtle.select(child)
  assert(turtle.place(), 'Could not place programmed child')
  mark('child_placed')

  local coal = assert(fuel.findFuelSlot(), 'No coal/charcoal available for child')
  assert(turtle.getItemCount(coal) >= config.childFuelItems,
    'Not enough coal/charcoal for child')
  turtle.select(coal)
  assert(turtle.drop(config.childFuelItems),
    'Could not transfer starting fuel to child')
  mark('fuel_transferred')

  local childComputer = childPeripheral()
  childComputer.turnOn()
  sleep(0.5)
  assert(childComputer.isOn(), 'Child did not power on')
  print('Child running; computer ID ' .. tostring(childComputer.getID()))
  mark('child_booted')

  turnAround()
  state.data.children = state.data.children + 1
  state.data.replication = nil
  state.save()
  log.event('child_complete', 'generation=' .. (state.data.generation + 1))
  print('Replication lab test complete. Check offspring: generation='
    .. tostring(state.data.generation + 1))
  return true
end

function M.diagnose()
  print('Replication stage:', tostring(state.data.replication and state.data.replication.stage))
  describeFront()
end

function M.resume()
  assert(not state.data.pending and not state.data.trip,
    'Unsafe navigation/trip state; inspect before resuming')
  local job = assert(state.data.replication, 'No interrupted replication')
  if job.stage == 'init_placed' then
    print('Resuming placed child initialization')
    finishInitialization()
    return programAndDeploy()
  end
  assert(job.stage == 'inserted',
    'Resume currently supports only inserted or init_placed, got: ' .. tostring(job.stage))
  assert(peripheral.hasType('front', 'drive'), 'Parent must still face the drive')
  assert(disk.isPresent('front'), 'Inserted child is missing from disk drive')
  print('Resuming from drive insertion')
  return programAndDeploy()
end

function M.lab()
  state.assertSafe()
  assert(peripheral.hasType('front', 'drive'), 'Face an empty disk drive')
  assert(not disk.isPresent('front'), 'Disk drive must be empty')
  local child = assert(findTurtle(), 'Put one spare turtle item in inventory')
  local coal = assert(fuel.findFuelSlot(child), 'Provide coal or charcoal for offspring')
  assert(turtle.getItemCount(coal) >= config.childFuelItems,
    'Need at least ' .. config.childFuelItems .. ' coal/charcoal for child')
  assert(not turtle.detectUp(), 'Keep space above the parent unobstructed')
  print('Preflight OK: spare turtle, fuel and empty disk drive')
  state.data.replication = {stage = 'start', childSlot = child, fuelSlot = coal}
  state.save()
  turtle.select(child)
  assert(turtle.drop(1), 'Could not insert child item into disk drive')
  mark('inserted')
  sleep(0.2)
  assert(disk.isPresent('front'), 'Drive did not accept turtle item')
  return programAndDeploy()
end

return M
