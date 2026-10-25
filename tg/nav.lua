-- Persist an intent BEFORE any movement/rotation. An ambiguous reboot halts.
local M = {}
local state = require('state')
local vectors = {
  {x = 0, z = 1}, {x = 1, z = 0},
  {x = 0, z = -1}, {x = -1, z = 0},
}

-- While the M2 forager explores, maintain an inverse path in the same
-- durable state write as its successful position update. A reboot between
-- movements can retrace this exact trail; an interrupted movement with a
-- pending intent is still ambiguous and must NEVER be guessed.
local inverse={forward='back',back='forward',up='down',down='up'}
local function recordStep(name,oldDir)
  local walk=state.data.forageTrail
  if not walk or not inverse[name] then return end
  local trail=walk.moves
  local last=trail[#trail]
  if last and last.action==inverse[name]
      and ((name=='up' or name=='down') or last.dir==oldDir) then
    trail[#trail]=nil
  else
    trail[#trail+1]={action=name,dir=oldDir}
  end
end

local function action(name, fn, update)
  assert(not state.data.pending, 'Pending physical action; manual recovery required')
  -- Save a snapshot, NOT another reference to state.data.pose.
  -- ComputerCraft's serializer rejects repeated table references.
  local p = state.data.pose
  state.data.pending = {
    action = name,
    pose = {x = p.x, y = p.y, z = p.z, dir = p.dir},
  }
  state.save()
  local oldDir=p.dir
  local ok, reason = fn()
  if ok then
    update(state.data.pose)
    recordStep(name,oldDir)
  end
  state.data.pending = nil
  state.save()
  return ok, reason
end

function M.forward()
  return action('forward', turtle.forward, function(p)
    local v = vectors[p.dir + 1]
    p.x, p.z = p.x + v.x, p.z + v.z
    state.data.moves = state.data.moves + 1
  end)
end
function M.back()
  return action('back', turtle.back, function(p)
    local v = vectors[p.dir + 1]
    p.x, p.z = p.x - v.x, p.z - v.z
    state.data.moves = state.data.moves + 1
  end)
end
function M.up()
  return action('up', turtle.up, function(p)
    p.y = p.y + 1
    state.data.moves = state.data.moves + 1
  end)
end
function M.down()
  return action('down', turtle.down, function(p)
    p.y = p.y - 1
    state.data.moves = state.data.moves + 1
  end)
end
function M.left()
  return action('turnLeft', turtle.turnLeft, function(p) p.dir = (p.dir + 3) % 4 end)
end
function M.right()
  return action('turnRight', turtle.turnRight, function(p) p.dir = (p.dir + 1) % 4 end)
end
return M
