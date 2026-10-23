-- Deliberately conservative tunnel probe, NOT autonomous resource gathering.
local M = {}
local config = require('config')
local state = require('state')
local nav = require('nav')
local fuel = require('fuel')
local log = require('log')

-- Let the pickaxe handle ordinary blocks (including short grass).
-- Only protect obvious liquids, unbreakable blocks, and player infrastructure.
local protected = {
  ['minecraft:bedrock'] = true, ['minecraft:barrier'] = true,
  ['minecraft:water'] = true, ['minecraft:lava'] = true,
  ['minecraft:chest'] = true, ['minecraft:trapped_chest'] = true,
  ['minecraft:barrel'] = true, ['minecraft:ender_chest'] = true,
  ['minecraft:furnace'] = true, ['minecraft:blast_furnace'] = true,
  ['minecraft:smoker'] = true, ['minecraft:hopper'] = true,
  ['minecraft:dispenser'] = true, ['minecraft:dropper'] = true,
  ['minecraft:crafting_table'] = true, ['minecraft:tnt'] = true,
  ['minecraft:spawner'] = true, ['minecraft:beehive'] = true,
  ['minecraft:bee_nest'] = true,
}
local function mineable(block)
  if not block or not block.name then return false end
  local n = block.name
  -- Avoid breaking unknown mod machinery during this lab test.
  if not n:find('^minecraft:') then return false end
  if protected[n] or n:find('shulker_box') or n:find('command_block') then return false end
  return true
end
local function inventoryHasSpace()
  for i = 1, 16 do if turtle.getItemCount(i) == 0 then return true end end
  return false
end

function M.run(steps)
  state.assertSafe()
  steps = tonumber(steps)
  assert(steps and steps >= 1 and steps % 1 == 0 and steps <= config.surveyLimit,
    'Survey distance must be integer 1..' .. config.surveyLimit)
  local required = 2 * steps + config.fuelReserve
  assert(fuel.ensure(required), 'Not enough coal/charcoal: need at least ' .. required .. ' fuel')
  state.data.trip = {out = 0, goal = steps, origin = textutils.unserialize(textutils.serialize(state.data.pose))}
  state.save()
  log.event('survey_begin', steps)

  local stopped = 'distance reached'
  for _ = 1, steps do
    if not inventoryHasSpace() then stopped = 'inventory full'; break end
    local block, data = turtle.inspect()
    if block then
      if not mineable(data) then stopped = 'unsafe block: ' .. tostring(data.name); break end
      local cleared = false
      -- Gravel may fall in after digging. Limit retries to avoid infinite loops.
      for _ = 1, 4 do
        local hasBlock, b = turtle.inspect()
        if not hasBlock then cleared = true; break end
        if not mineable(b) then stopped = 'unsafe falling block'; break end
        local ok = turtle.dig()
        if not ok then stopped = 'unable to mine'; break end
        sleep(0.2)
      end
      if not cleared and turtle.detect() then stopped = 'block remains'; break end
    end
    local ok, reason = nav.forward()
    if not ok then stopped = 'movement blocked: ' .. tostring(reason); break end
    state.data.trip.out = state.data.trip.out + 1
    state.save()
  end

  local stepsHome = state.data.trip.out
  for i = stepsHome, 1, -1 do
    if fuel.level() < i then
      log.event('survey_stranded', 'insufficient fuel returning')
      error('Not enough fuel to return; interrupted trip preserved')
    end
    local ok, reason = nav.back()
    if not ok then
      log.event('survey_stranded', tostring(reason))
      error('Return blocked; survey state preserved: ' .. tostring(reason))
    end
    state.data.trip.out = i - 1
    state.save()
  end
  -- Direction does not change during the probe; verify the starting pose.
  local p, o = state.data.pose, state.data.trip.origin
  assert(p.x == o.x and p.y == o.y and p.z == o.z and p.dir == o.dir,
    'Pose mismatch after return; trip preserved')
  state.data.trip = nil
  state.data.surveys = state.data.surveys + 1
  state.save()
  log.event('survey_done', stopped)
  return stopped
end
return M
