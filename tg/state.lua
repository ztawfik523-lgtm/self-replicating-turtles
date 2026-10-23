local M = {}
local PATH, BAK, TMP, SEED = '/tg/state.dat', '/tg/state.bak', '/tg/state.tmp', '/tg/seed.dat'

local function read(path)
  if not fs.exists(path) then return nil end
  local file = fs.open(path, 'r')
  if not file then return nil end
  local contents = file.readAll()
  file.close()
  local result = textutils.unserialize(contents)
  if type(result) == 'table' and result.schema == 1 then return result end
  return nil
end

local function fresh()
  local seed = read(SEED)
  local generation = seed and tonumber(seed.generation) or 0
  local parentID = seed and seed.parentID or nil
  return {
    schema = 1, generation = generation or 0, parentID = parentID,
    autoSeed = seed and seed.auto == true or false,
    autonomyEnabled = seed and seed.auto == true or false,
    pose = {x = 0, y = 0, z = 0, dir = 0}, -- local axes; not world coordinates
    pending = nil, trip = nil, replication = nil,
    bootCount = 0, moves = 0, surveys = 0, children = 0,
  }
end

local function write(data)
  -- Serialize first so a bad table never leaves a half-written temp file.
  local serialized = textutils.serialize(data)
  local out = assert(fs.open(TMP, 'w'), 'Unable to write state temp file')
  out.write(serialized)
  out.close()
  -- Keep a complete previous version. If power fails mid-replace, load BAK.
  if fs.exists(BAK) then fs.delete(BAK) end
  if fs.exists(PATH) then fs.move(PATH, BAK) end
  fs.move(TMP, PATH)
end

function M.load()
  local data = read(PATH) or read(BAK)
  if not data then
    if fs.exists(PATH) or fs.exists(BAK) then
      error('Corrupted state: manual recovery required; refusing to reset pose')
    end
    data = fresh()
    write(data)
    if fs.exists(SEED) then fs.delete(SEED) end
  end
  M.data = data
  return data
end

function M.save()
  assert(M.data, 'State not loaded')
  write(M.data)
end

function M.assertSafe()
  assert(M.data, 'State not loaded')
  assert(not M.data.pending, 'Uncertain previous movement: inspect /tg/state.dat before resuming')
  assert(not M.data.trip, 'Interrupted survey: manual recovery required')
  assert(not M.data.replication, 'Interrupted replication: manual recovery required')
end

return M
