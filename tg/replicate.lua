-- Lab reproduction: parent faces an EMPTY disk drive; AIR directly behind it.
-- Supply one child turtle item and a stack of coal/charcoal in parent inventory.
-- Experimental: test whether turtle.drop/suck can manipulate a disk drive.
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
  state.data.replication.stage = stage
  state.save()
  log.event('replication', stage)
end

function M.lab()
  state.assertSafe()
  assert(peripheral.getType('front') == 'drive', 'Face an empty disk drive')
  assert(not disk.isPresent('front'), 'Disk drive must be empty')
  local child = assert(findTurtle(), 'Put ONE normal/advanced turtle item in inventory')
  local coal = assert(fuel.findFuelSlot(child), 'Provide coal or charcoal for child')
  assert(turtle.getItemCount(coal) >= config.childFuelItems, 'Need more coal for child')
  -- No automatic retry after interruption. A human must reconcile partial work.
  state.data.replication = {stage = 'start', childSlot = child, fuelSlot = coal}
  state.save()

  turtle.select(child)
  assert(turtle.drop(1), 'Could not insert child item into disk drive')
  mark('inserted')
  sleep(0.3)
  assert(disk.isPresent('front'), 'Drive did not receive child: check for dropped item')
  clone.install('front')
  mark('programmed')
  -- Disk drive is an inventory on some CC builds; verify extraction in-game.
  assert(turtle.suck(1), 'Could not retrieve programmed child from drive')
  sleep(0.2)
  mark('retrieved')
  child = assert(findTurtle(), 'Programmed child not found in parent inventory')

  assert(nav.right())
  assert(nav.right())
  mark('turned_to_deploy')
  assert(not turtle.detect(), 'Deployment cell behind original position must be air')
  turtle.select(child)
  assert(turtle.place(), 'Could not place child')
  mark('placed')
  turtle.select(coal)
  assert(turtle.drop(config.childFuelItems), 'Could not insert starting fuel into child')
  mark('fuel_transferred')
  assert(peripheral.getType('front') == 'turtle', 'Placed child is not a turtle peripheral')
  local childPeripheral = assert(peripheral.wrap('front'))
  childPeripheral.turnOn()
  sleep(0.2)
  assert(childPeripheral.isOn(), 'Child did not boot')
  mark('booted')

  assert(nav.right())
  assert(nav.right())
  state.data.children = state.data.children + 1
  state.data.replication = nil
  state.save()
  log.event('child_complete', 'generation=' .. (state.data.generation + 1))
  print('SUCCESS: child powered on with copied startup program')
  return true
end
return M
