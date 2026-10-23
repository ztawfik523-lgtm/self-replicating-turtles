local args = {...}
local command = args[1] or 'status'
local config = require('config')
local state = require('state')
local log = require('log')
local fuel = require('fuel')

state.load()

local function status()
  local d = state.data
  print(('TURTLE GENESIS %s  ID=%d  generation=%d'):format(config.version, os.getComputerID(), d.generation))
  print('Mode:', config.mode, 'Fuel:', turtle.getFuelLevel())
  print(('Pose local x=%d y=%d z=%d dir=%d'):format(d.pose.x, d.pose.y, d.pose.z, d.pose.dir))
  print(('Boots=%d moves=%d surveys=%d children=%d'):format(d.bootCount, d.moves, d.surveys, d.children))
  if d.pending then printError('HALTED uncertain action: ' .. tostring(d.pending.action)) end
  if d.trip then printError('HALTED interrupted survey: ' .. tostring(d.trip.out) .. ' steps out') end
  if d.replication then printError('HALTED interrupted replication: ' .. tostring(d.replication.stage)) end
end

local ok, err = pcall(function()
  if command == 'boot' then
    state.data.bootCount = state.data.bootCount + 1
    state.save()
    log.event('boot', 'generation=' .. tostring(state.data.generation))
    status()
    if config.mode ~= 'lab' then printError('Unknown mode; autonomous loop not yet implemented') end
  elseif command == 'status' then
    status()
  elseif command == 'probe' then
    require('probe').run()
  elseif command == 'recover' then
    -- Safe only for surveys aborted before the first physical movement.
    local d = state.data
    assert(not d.pending and not d.replication, 'Cannot recover: uncertain movement or replication')
    assert(d.trip and d.trip.out == 0 and d.trip.origin, 'Cannot recover: survey may have moved; investigate manually')
    local p, o = d.pose, d.trip.origin
    assert(p.x == o.x and p.y == o.y and p.z == o.z and p.dir == o.dir,
      'Cannot recover: current pose differs from survey origin')
    d.trip = nil
    state.save()
    log.event('recover', 'cleared zero-movement survey')
    print('Recovered: aborted survey had no recorded movement.')
  elseif command == 'survey' then
    print('Survey:', require('survey').run(tonumber(args[2] or '4')))
  elseif command == 'install' then
    state.assertSafe()
    print('Child code installed on mount:', require('clone').install(args[2] or 'front'))
  elseif command == 'replicate' then
    require('replicate').lab()
  elseif command == 'resume' then
    require('replicate').resume()
  elseif command == 'help' then
    print('tg/main.lua status | probe | recover | survey <1..12> | install [drive-side] | replicate | resume')
  else
    error('Unknown command. Run: tg/main.lua help')
  end
end)
if not ok then
  log.event('error', err)
  printError('GENESIS: ' .. tostring(err))
end
